import 'package:dio/dio.dart';

import '../storage/token_store.dart';
import 'error_code.dart';

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

  /// 세션 만료는 정확히 이 한 곳에서만 일어난다. `_tryRefresh`가 [_RefreshOutcome]
  /// 으로 실패 성격을 분류해 돌려주면, 그중 "자격 증명 자체가 죽었다"는
  /// 뜻인 것만 `_expireSession()`을 부른다. 네트워크 단절·5xx·파싱 실패
  /// 같은 일시적 실패는 토큰을 그대로 두고 원요청의 에러만 흘려보낸다 —
  /// SessionController(_resolve)가 세운 것과 동일한 정책이다. 예전엔 이유를
  /// 가리지 않고 실패하면 무조건 세션을 지웠는데, 그러면 재발급 도중의
  /// 네트워크 끊김 한 번으로도 로그아웃되는 문제가 있었다.
  Future<String?> _runRefresh(String? sentAccessToken) async {
    final outcome = await _tryRefresh(sentAccessToken);
    if (outcome.accessToken == null && outcome.isAuthFailure) {
      await _expireSession();
    }
    return outcome.accessToken;
  }

  /// 실패를 두 갈래로 분류해 돌려준다 — 자격 증명이 죽었다는 뜻인지, 아니면
  /// 나중에 다시 시도하면 성공할 수도 있는 일시적 문제인지. 여기서는 절대
  /// `_expireSession()`을 부르지 않는다 — 그 책임은 호출부(`_runRefresh`)
  /// 한 곳에만 있다.
  ///
  /// 알려진 한계: 마지막 `catch (_)`가 원래 예외와 스택 트레이스를 버린다.
  /// 그래서 이 안에 진짜 프로그래밍 오류가 있어도 요란하게 죽는 대신 조용히
  /// 일시적 실패로 나타난다(더 이상 세션을 지우지도 않는다). 지금 이
  /// 프로젝트엔 로깅 인프라가 없고, 여기서 임의 예외를 밖으로 새게 두면
  /// 하류가 전부 의존하는 "호출자는 ApiException만 본다"는 계약이
  /// 깨지므로 감수한다. 로깅이 생기면 재검토한다.
  Future<_RefreshOutcome> _tryRefresh(String? sentAccessToken) async {
    try {
      // 이 flight가 실제로 시작되기 전에 다른 flight가 이미 갱신을 끝냈을
      // 수 있다 — `onError`의 빠른 경로 검사는 flight 밖에서 이뤄지므로,
      // 그 검사 이후 이 flight가 실행될 때까지 사이에 다른 flight가 끼어들
      // 여지가 있다. `_inFlight`는 이전 flight가 저장을 마친 뒤에야
      // 비워지므로, 여기서 다시 읽은 값은 항상 최신이다.
      final current = await _store.readAccessToken();
      if (current != null && current != sentAccessToken) {
        return _RefreshOutcome.success(current);
      }

      final refreshToken = await _store.readRefreshToken();
      if (refreshToken == null) {
        // 시도할 재발급 토큰 자체가 없다 — 확실히 로그인되지 않은 상태이므로
        // 이 경우는 (네트워크를 타지도 않았지만) 자격 증명 실패로 취급해
        // 세션을 정리하고 만료 콜백을 부른다.
        return const _RefreshOutcome.authFailure();
      }

      final response = await _bare().post<Object?>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final body = response.data;
      if (body is! Map<String, dynamic> || body['success'] != true) {
        return const _RefreshOutcome.transientFailure();
      }

      final data = body['data'];
      if (data is! Map<String, dynamic>) return const _RefreshOutcome.transientFailure();

      final accessToken = data['accessToken'] as String?;
      final newRefreshToken = data['refreshToken'] as String?;
      if (accessToken == null || newRefreshToken == null) {
        return const _RefreshOutcome.transientFailure();
      }

      await _store.save(accessToken: accessToken, refreshToken: newRefreshToken);
      return _RefreshOutcome.success(accessToken);
    } on DioException catch (error) {
      return _isAuthFailureResponse(error.response)
          ? const _RefreshOutcome.authFailure()
          : const _RefreshOutcome.transientFailure();
    } catch (_) {
      return const _RefreshOutcome.transientFailure();
    }
  }

  /// [response]가 "자격 증명 자체가 죽었다"를 뜻하는지 판정한다. 401/403
  /// 이면서 응답 바디가 표준 래퍼 형태이고 그 code가 [authFailureCodes]에
  /// 속할 때만 true다. 응답 자체가 없거나(네트워크 단절, 타임아웃), 5xx
  /// 이거나, 래퍼가 아닌 바디(프록시 HTML 등)는 전부 false다 — 그런
  /// 경우엔 세션을 지울 근거가 없다.
  bool _isAuthFailureResponse(Response<Object?>? response) {
    final statusCode = response?.statusCode;
    if (statusCode != 401 && statusCode != 403) return false;
    final body = response?.data;
    if (body is! Map<String, dynamic>) return false;
    final error = body['error'];
    final code = error is Map ? error['code'] : null;
    return authFailureCodes.contains(ErrorCode.fromWire(code is String ? code : null));
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

/// [AuthInterceptor._tryRefresh]의 결과. 실패는 두 갈래로 나뉜다 — 자격
/// 증명이 죽었다는 뜻인지(재로그인 전까지 재발급이 다시는 성공할 수 없다),
/// 아니면 일시적인 문제인지(네트워크 단절, 5xx, 타임아웃, 응답 파싱 실패
/// 등 — 나중에 다시 시도하면 성공할 수도 있다). 후자는 세션을 지울 근거가
/// 없다.
class _RefreshOutcome {
  const _RefreshOutcome.success(this.accessToken) : isAuthFailure = false;

  const _RefreshOutcome.transientFailure()
      : accessToken = null,
        isAuthFailure = false;

  const _RefreshOutcome.authFailure()
      : accessToken = null,
        isAuthFailure = true;

  final String? accessToken;
  final bool isAuthFailure;
}
