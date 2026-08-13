import 'package:dio/dio.dart';

import '../storage/token_write_coordinator.dart';
import 'error_code.dart';

/// 동시에 여러 401이 몰려도 재발급은 한 번만 일어나야 한다. `QueuedInterceptor`로
/// 이 직렬화를 시도하면, 재시도가 인터셉터가 붙은 Dio를 다시 타는 순간 그 내부
/// 에러 큐가 자기 자신을 기다리며 교착될 수 있다(재시도가 또 실패하는 경우).
/// 그래서 이 인터셉터는 평범한 [Interceptor]로 두고, 재발급 중복 방지는
/// `Future` 기반 single-flight로 명시적으로 처리한다. 재발급/재시도는 인터셉터가
/// 없는 별도 Dio로 보내 애초에 재귀가 생기지 않도록 한다.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this._tokens,
    required this._dio,
    required this._onSessionExpired,
  });

  /// 토큰 읽기·쓰기는 전부 이 조정자를 통한다. 인터셉터는 [TokenStore]를
  /// 직접 들고 있지 않다 — 그래야 큐와 세대 검사를 우회하는 쓰기 경로가
  /// 애초에 존재할 수 없다.
  final TokenWriteCoordinator _tokens;

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
    final token = await _tokens.readAccessToken();
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
    final currentToken = await _tokens.readAccessToken();

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
  /// SessionController(_resolve)가 세운 것과 동일한 정책이고, 판정 자체도
  /// [isAuthFailure] 한 함수를 같이 쓴다. 예전엔 이유를 가리지 않고
  /// 실패하면 무조건 세션을 지웠는데, 그러면 재발급 도중의 네트워크 끊김
  /// 한 번으로도 로그아웃되는 문제가 있었다.
  ///
  /// flight가 시작되는 이 시점의 세대를 캡처해 끝까지 들고 다닌다. 이
  /// flight가 네트워크를 기다리는 동안 사용자가 로그아웃하거나 다른 계정으로
  /// 새로 로그인하면 세대가 바뀌고, 그러면 이 flight의 저장/삭제는 남의
  /// 세션을 건드리는 일이 되므로 전부 건너뛴다.
  Future<String?> _runRefresh(String? sentAccessToken) async {
    final generation = _tokens.generation;
    final outcome = await _tryRefresh(generation, sentAccessToken);
    if (outcome.accessToken == null && outcome.isAuthFailure) {
      await _expireSession(generation);
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
  Future<_RefreshOutcome> _tryRefresh(int generation, String? sentAccessToken) async {
    try {
      // 이 flight가 실제로 시작되기 전에 다른 flight가 이미 갱신을 끝냈을
      // 수 있다 — `onError`의 빠른 경로 검사는 flight 밖에서 이뤄지므로,
      // 그 검사 이후 이 flight가 실행될 때까지 사이에 다른 flight가 끼어들
      // 여지가 있다. `_inFlight`는 이전 flight가 저장을 마친 뒤에야
      // 비워지므로, 여기서 다시 읽은 값은 항상 최신이다.
      final current = await _tokens.readAccessToken();
      if (current != null && current != sentAccessToken) {
        return _RefreshOutcome.success(current);
      }

      final refreshToken = await _tokens.readRefreshToken();
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

      final applied = await _tokens.save(
        generation,
        accessToken: accessToken,
        refreshToken: newRefreshToken,
      );
      if (!applied) {
        // 이 flight가 시작된 뒤 로그아웃이나 새 로그인이 시작됐다. 방금 받은
        // 토큰은 이제 남의 세션 것이므로 저장하지도, 원요청 재시도에 쓰지도
        // 않는다. 세션을 지울 근거는 아니므로 일시적 실패로 돌려보내
        // 원요청의 원래 에러가 그대로 호출부에 도달하게 한다.
        return const _RefreshOutcome.transientFailure();
      }
      return _RefreshOutcome.success(accessToken);
    } on DioException catch (error) {
      return _isAuthFailureResponse(error.response)
          ? const _RefreshOutcome.authFailure()
          : const _RefreshOutcome.transientFailure();
    } catch (_) {
      return const _RefreshOutcome.transientFailure();
    }
  }

  /// [response]에서 서버가 내려준 `error.code`를 꺼내 [isAuthFailure]에
  /// 넘긴다 — 판정 규칙 자체는 SessionController와 공유하는 그 함수에만
  /// 있다. 응답이 아예 없으면(네트워크 단절, 타임아웃) 세션을 지울 근거가
  /// 없으므로 여기서 바로 false다.
  ///
  /// 예전엔 이 함수가 401/403이 아닌 응답을 code를 보기도 전에 걸러냈는데,
  /// 실 백엔드는 `MEMBER_NOT_FOUND`를 404로 내려주기 때문에 그 상태 검사가
  /// 인식된 인증 실패 코드를 조용히 일시적 실패로 만들었다.
  bool _isAuthFailureResponse(Response<Object?>? response) {
    if (response == null) return false;
    final body = response.data;
    final error = body is Map<String, dynamic> ? body['error'] : null;
    final wire = error is Map ? error['code'] : null;
    return isAuthFailure(
      code: ErrorCode.fromWire(wire is String ? wire : null),
      statusCode: response.statusCode,
    );
  }

  /// [generation]이 여전히 최신일 때만 세션을 만료시킨다. 이 flight가
  /// 실패하는 사이 사용자가 새로 로그인했다면 지금 지워야 할 세션은 이미
  /// 없다 — 그런데도 지우면 방금 로그인한 사용자의 토큰을 날리고 만료
  /// 콜백까지 불러 로그인 화면으로 되돌려보낸다.
  Future<void> _expireSession(int generation) async {
    final cleared = await _tokens.clear(generation);
    if (!cleared) return;
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
  //   flutter_secure_storage 수준에서 원자적으로 만들 수 없다. 둘 사이에서
  //   실패하면(예: access는 새 값, refresh는 옛 값) 이 코드는 되돌리지
  //   않는다 — `catch`는 세션을 정리하지 않고 일시적 실패로만 분류한다.
  //   실제 복구는 다음 401에서 일어난다: 저장된 refresh token으로 재발급을
  //   다시 시도하고, 서버가 이미 그 토큰을 회전시켰다면 인증 실패 코드가
  //   돌아와 그때 세션이 정상적으로 만료된다(= 로그인 화면). 지우지 않는
  //   쪽을 택한 이유는, 여기서 지우면 저장 실패 한 번이 곧바로
  //   로그아웃이 되기 때문이다.
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
