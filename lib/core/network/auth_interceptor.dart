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

  /// 진행 중인 재발급이 있으면 그 Future를 공유한다. refresh token을 읽는 것부터
  /// 실패 처리까지 전부 이 flight 안에서 일어나야 한다 — 밖에서 먼저 읽어두면,
  /// 그 사이 다른 flight가 이미 토큰을 회전시켜서 낡은 refresh token으로 또
  /// 재발급을 시도하는 경쟁 상태가 생긴다.
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

    // 다른 요청이 이미 갱신을 끝냈다면 재발급 없이 재시도만 한다.
    if (currentToken != null && currentToken != sentToken) {
      return _retry(err, currentToken, handler);
    }

    final newAccessToken = await _refreshOnce();
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
  Future<String?> _refreshOnce() {
    return _inFlight ??= _runRefresh().whenComplete(() => _inFlight = null);
  }

  /// refresh token 읽기, 실패 처리, 세션 만료 신호까지 전부 이 안에서 한다 —
  /// 바깥(예: `onError`)에서 미리 읽으면, 그 사이 다른 flight가 이미 토큰을
  /// 회전시켜서 이 호출이 낡은 refresh token을 들고 들어올 수 있다. 성공 시
  /// 새 access token을 반환하고, 실패 시 세션을 정리하고 null을 반환한다.
  Future<String?> _runRefresh() async {
    final refreshToken = await _store.readRefreshToken();
    if (refreshToken == null) {
      await _expireSession();
      return null;
    }

    try {
      final response = await _bare().post<Object?>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final body = response.data;
      if (body is! Map<String, dynamic> || body['success'] != true) {
        await _expireSession();
        return null;
      }

      final data = body['data'];
      if (data is! Map<String, dynamic>) {
        await _expireSession();
        return null;
      }

      final accessToken = data['accessToken'] as String?;
      final newRefreshToken = data['refreshToken'] as String?;
      if (accessToken == null || newRefreshToken == null) {
        await _expireSession();
        return null;
      }

      await _store.save(accessToken: accessToken, refreshToken: newRefreshToken);
      return accessToken;
    } catch (_) {
      // DioException뿐 아니라 응답 파싱 실패·저장 실패까지 전부 여기로 와서
      // 세션 정리로 이어져야 한다 — 그중 무엇도 밖으로 새어나가면 안 된다.
      await _expireSession();
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
