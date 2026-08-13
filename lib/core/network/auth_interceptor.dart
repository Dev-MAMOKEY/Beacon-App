import 'package:dio/dio.dart';

import '../storage/token_store.dart';

/// 동시에 여러 401이 몰려도 재발급은 한 번만 일어나야 한다. `QueuedInterceptor`로
/// 이 직렬화를 시도하면, 재시도가 인터셉터가 붙은 Dio를 다시 타는 순간 그 내부
/// 에러 큐가 자기 자신을 기다리며 교착될 수 있다(재시도가 또 실패하는 경우).
/// 그래서 이 인터셉터는 평범한 [Interceptor]로 두고, 재발급 중복 방지는
/// `Future` 기반 single-flight로 명시적으로 처리한다. 재발급/재시도는 인터셉터가
/// 없는 별도 Dio로 보내 애초에 재귀가 생기지 않도록 한다.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this._store,
    required this._dio,
    required this._onSessionExpired,
  });

  final TokenStore _store;

  /// 이 인터셉터가 붙은 바로 그 메인 Dio.
  final Dio _dio;

  final void Function() _onSessionExpired;

  /// 진행 중인 재발급이 있으면 그 Future를 공유한다. 스토어를 다시 읽는
  /// 시점(현재 토큰 비교, refresh token 읽기)이 전부 이 flight 안이어야
  /// "다른 flight가 이미 회전시킨 값"과 경합하지 않는다.
  Future<String?>? _inFlight;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _store.readAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401 || _isAuthEndpoint(err.requestOptions.path)) {
      return handler.next(err);
    }

    final sentToken = _bearerOf(err.requestOptions);
    final currentToken = await _store.readAccessToken();

    // 다른 요청이 이미 갱신을 끝냈다면 재발급 없이 재시도만 한다. 흔한
    // 경우엔 여기서 바로 끝나 flight를 만들 필요조차 없다 — 다만 이 검사는
    // flight 밖에서 이뤄지므로 최종 방어선은 아니다. 이 검사를 통과해도
    // `_tryRefresh` 안에서 한 번 더 같은 검사를 한다.
    if (currentToken != null && currentToken != sentToken) {
      return _retry(err, currentToken, handler);
    }

    final newAccessToken = await _refreshOnce(sentToken);
    return newAccessToken == null
        ? handler.next(err)
        : _retry(err, newAccessToken, handler);
  }

  static const _authEndpointNames = {'login', 'signup', 'refresh'};

  /// 마지막 두 세그먼트가 정확히 `auth/{login,signup,refresh}`일 때만 예외로
  /// 취급한다. 부분 문자열 매칭(`path.contains('/auth/login')`)은
  /// `/reports/auth/login-attempts` 같은 무관한 경로까지 예외로 만들어버린다.
  bool _isAuthEndpoint(String path) {
    final segments = Uri.parse(path).pathSegments;
    if (segments.length < 2) return false;
    final last = segments.last;
    final beforeLast = segments[segments.length - 2];
    return beforeLast == 'auth' && _authEndpointNames.contains(last);
  }

  String? _bearerOf(RequestOptions options) {
    final header = options.headers['Authorization'];
    if (header is! String || !header.startsWith('Bearer ')) return null;
    return header.substring('Bearer '.length);
  }

  /// 동시에 여러 401이 진행 중이어도 실제 재발급 호출은 하나만 나가도록 한다.
  /// null 체크와 대입 사이에 다른 코드가 끼어들 수 없다는 Dart 이벤트 루프의
  /// 특성 덕분에 `??=` 만으로 충분하다.
  Future<String?> _refreshOnce(String? sentAccessToken) {
    return _inFlight ??= _runRefresh(sentAccessToken).whenComplete(() => _inFlight = null);
  }

  /// 세션 만료는 정확히 이 한 곳에서만 일어난다. `_tryRefresh`가 무엇 때문에
  /// 실패했든(네트워크, 파싱, 저장, 스토리지 읽기) 전부 null로 뭉뚱그려져
  /// 여기로 오고, null이면 딱 한 번 `_expireSession()`을 부른다 — 그래서
  /// "실패 경로마다 만료 신호를 빼먹지 않고 넣었나"를 챙길 필요가 없고,
  /// 반대로 두 번 불릴 걱정도 없다.
  Future<String?> _runRefresh(String? sentAccessToken) async {
    final token = await _tryRefresh(sentAccessToken);
    if (token == null) {
      await _expireSession();
    }
    return token;
  }

  /// 실패는 전부 null로 환원한다. 여기서는 절대 `_expireSession()`을 부르지
  /// 않는다 — 그 책임은 호출부(`_runRefresh`) 한 곳에만 있다.
  ///
  /// 알려진 한계: `catch (_)`가 원래 예외와 스택 트레이스를 버린다. 그래서
  /// 이 안에 진짜 프로그래밍 오류가 있어도 요란하게 죽는 대신 조용히 세션
  /// 만료로 나타난다. 지금 이 프로젝트엔 로깅 인프라가 없고, 여기서 임의
  /// 예외를 밖으로 새게 두면 하류가 전부 의존하는 "호출자는 ApiException만
  /// 본다"는 계약이 깨지므로 감수한다. 로깅이 생기면 재검토한다.
  Future<String?> _tryRefresh(String? sentAccessToken) async {
    try {
      // 이 flight가 실제로 시작되기 전에 다른 flight가 이미 갱신을 끝냈을
      // 수 있다 — `onError`의 빠른 경로 검사는 flight 밖에서 이뤄지므로,
      // 그 검사 이후 이 flight가 실행될 때까지 사이에 다른 flight가 끼어들
      // 여지가 있다. `_inFlight`는 이전 flight가 저장을 마친 뒤에야
      // 비워지므로, 여기서 다시 읽은 값은 항상 최신이다.
      final current = await _store.readAccessToken();
      if (current != null && current != sentAccessToken) {
        return current;
      }

      final refreshToken = await _store.readRefreshToken();
      if (refreshToken == null) return null;

      final response = await _bare().post<Object?>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final body = response.data;
      if (body is! Map<String, dynamic> || body['success'] != true) return null;

      final data = body['data'];
      if (data is! Map<String, dynamic>) return null;

      final accessToken = data['accessToken'] as String?;
      final newRefreshToken = data['refreshToken'] as String?;
      if (accessToken == null || newRefreshToken == null) return null;

      await _store.save(accessToken: accessToken, refreshToken: newRefreshToken);
      return accessToken;
    } catch (_) {
      return null;
    }
  }

  Future<void> _expireSession() async {
    await _store.clear();
    _onSessionExpired();
  }

  Future<void> _retry(
    DioException err,
    String accessToken,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    options.headers['Authorization'] = 'Bearer $accessToken';
    try {
      final response = await _bare().fetch<Object?>(options);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  /// 인터셉터가 붙지 않은 일회용 Dio. 재발급/재시도 요청이 다시 401을 만나도
  /// 이 인터셉터로 돌아오지 않으므로 재귀·교착 걱정이 없다. 메인 Dio의
  /// connect/receive/send 타임아웃도 그대로 물려받는다 — 안 그러면 재발급이나
  /// 재시도가 걸려도 타임아웃으로 구제되지 않는다. `httpClientAdapter`는 호출
  /// 시점에 메인 Dio에서 읽는다 — 생성자에서 캐시하면, 어댑터를 Dio 생성 이후에
  /// 설치하는 테스트 환경에서 옛 어댑터를 붙잡게 된다.
  //
  // 알려진 한계(현재 스코프에서는 의도적으로 미해결):
  // - FormData나 한 번만 읽을 수 있는 스트림 바디는 재시도 시 재생할 수 없다.
  //   Phase 1의 엔드포인트는 전부 JSON이고 업로드는 스코프 밖이라 괜찮다.
  // - `SecureTokenStore.save`/`clear`는 순차적인 두 번의 쓰기라
  //   flutter_secure_storage 수준에서 원자적으로 만들 수 없다. 실패 시
  //   `catch`가 세션을 정리하는 것이 지금 가능한 완화책이다.
  // - 이 Dio는 메인 Dio의 응답 인터셉터·커스텀 트랜스포머를 타지 않는다.
  //   지금은 둘 다 없어서 문제가 되지 않는다.
  Dio _bare() => Dio(
        BaseOptions(
          baseUrl: _dio.options.baseUrl,
          connectTimeout: _dio.options.connectTimeout,
          receiveTimeout: _dio.options.receiveTimeout,
          sendTimeout: _dio.options.sendTimeout,
          contentType: _dio.options.contentType,
        ),
      )..httpClientAdapter = _dio.httpClientAdapter;
}
