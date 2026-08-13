// 필드는 캡슐화를 위해 private으로 두면서 생성자 파라미터명은 공개 API로
// 노출해야 해서(예: `store:`), 필드명을 그대로 쓰는 initializing formal을 쓸
// 수 없다. 그래서 이 파일에서는 이 lint를 따르지 않는다.
// ignore_for_file: prefer_initializing_formals
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
    required TokenStore store,
    required Dio dio,
    required void Function() onSessionExpired,
  })  : _store = store,
        _dio = dio,
        _onSessionExpired = onSessionExpired;

  final TokenStore _store;

  /// 이 인터셉터가 붙은 바로 그 메인 Dio.
  final Dio _dio;

  final void Function() _onSessionExpired;

  /// 진행 중인 재발급이 있으면 그 Future를 공유한다. 동시에 여러 401이 와도
  /// 실제 네트워크 재발급 호출은 하나만 나간다.
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

    final refreshToken = await _store.readRefreshToken();
    if (refreshToken == null) {
      await _store.clear();
      _onSessionExpired();
      return handler.next(err);
    }

    final newAccessToken = await _refreshOnce(refreshToken);
    if (newAccessToken == null) {
      await _store.clear();
      _onSessionExpired();
      return handler.next(err);
    }

    return _retry(err, newAccessToken, handler);
  }

  bool _isAuthEndpoint(String path) {
    return path.contains('/auth/login') ||
        path.contains('/auth/signup') ||
        path.contains('/auth/refresh');
  }

  String? _bearerOf(RequestOptions options) {
    final header = options.headers['Authorization'];
    if (header is! String || !header.startsWith('Bearer ')) return null;
    return header.substring('Bearer '.length);
  }

  /// 동시에 여러 401이 진행 중이어도 실제 재발급 호출은 하나만 나가도록 한다.
  /// null 체크와 대입 사이에 다른 코드가 끼어들 수 없다는 Dart 이벤트 루프의
  /// 특성 덕분에 `??=` 만으로 충분하다.
  Future<String?> _refreshOnce(String refreshToken) {
    return _inFlight ??= _refresh(refreshToken).whenComplete(() => _inFlight = null);
  }

  /// 성공 시 새 access token을 반환하고, 실패 시 null을 반환한다.
  Future<String?> _refresh(String refreshToken) async {
    try {
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
    } on DioException {
      return null;
    }
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
  /// 이 인터셉터로 돌아오지 않으므로 재귀·교착 걱정이 없다. `httpClientAdapter`는
  /// 호출 시점에 메인 Dio에서 읽는다 — 생성자에서 캐시하면, 어댑터를 나중에
  /// 설치하는 테스트 환경에서 옛 어댑터를 붙잡게 된다.
  Dio _bare() => Dio(BaseOptions(baseUrl: _dio.options.baseUrl))
    ..httpClientAdapter = _dio.httpClientAdapter;
}
