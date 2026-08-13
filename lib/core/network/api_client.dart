import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'error_code.dart';

/// 서버의 `{success, data, error, timestamp}` 래퍼를 한 곳에서 벗긴다.
/// 호출부는 `data` 만 받고, 실패는 전부 [ApiException] 으로 올라온다.
class ApiClient {
  const ApiClient(this._dio);

  final Dio _dio;

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? query,
    required T Function(Object? json) parse,
  }) {
    return _send(() => _dio.get<Object?>(path, queryParameters: query), parse);
  }

  Future<T> post<T>(
    String path, {
    Object? body,
    required T Function(Object? json) parse,
  }) {
    return _send(() => _dio.post<Object?>(path, data: body), parse);
  }

  Future<T> patch<T>(
    String path, {
    Object? body,
    required T Function(Object? json) parse,
  }) {
    return _send(() => _dio.patch<Object?>(path, data: body), parse);
  }

  Future<T> put<T>(
    String path, {
    Object? body,
    required T Function(Object? json) parse,
  }) {
    return _send(() => _dio.put<Object?>(path, data: body), parse);
  }

  Future<T> delete<T>(
    String path, {
    Object? body,
    required T Function(Object? json) parse,
  }) {
    return _send(() => _dio.delete<Object?>(path, data: body), parse);
  }

  Future<T> _send<T>(
    Future<Response<Object?>> Function() run,
    T Function(Object? json) parse,
  ) async {
    final Response<Object?> response;
    try {
      response = await run();
    } on DioException catch (error) {
      final failed = error.response;
      final body = failed?.data;
      if (body is Map<String, dynamic>) {
        // 4xx/5xx라도 본문이 표준 래퍼면 서버 에러 코드를 살린다.
        return _unwrap(body, parse, failed?.statusCode);
      }
      if (failed != null) {
        // 서버가 응답은 했지만 래퍼 형식이 아니다 (프록시 HTML, 빈 본문 등).
        throw ApiException(
          ErrorCode.unknown,
          '서버 응답을 처리하지 못했습니다.',
          statusCode: failed.statusCode,
        );
      }
      // 응답 자체가 없다 — 연결 실패나 타임아웃.
      throw ApiException(ErrorCode.network, '서버에 연결하지 못했습니다.');
    }
    return _unwrap(response.data, parse, response.statusCode);
  }

  T _unwrap<T>(
    Object? body,
    T Function(Object? json) parse,
    int? statusCode,
  ) {
    if (body is! Map<String, dynamic>) {
      throw ApiException(
        ErrorCode.unknown,
        '응답 형식이 올바르지 않습니다.',
        statusCode: statusCode,
      );
    }

    if (body['success'] != true) {
      final error = body['error'];
      final code = error is Map ? error['code'] : null;
      final message = error is Map ? error['message'] : null;
      throw ApiException(
        // 서버가 code를 문자열이 아닌 값으로 보내도 unknown으로 흡수한다.
        ErrorCode.fromWire(code is String ? code : null),
        message is String && message.isNotEmpty
            ? message
            : '알 수 없는 오류가 발생했습니다.',
        statusCode: statusCode,
      );
    }

    // parse가 무엇을 던지든 호출자에게는 ApiException만 나가야 한다.
    try {
      return parse(body['data']);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
        ErrorCode.unknown,
        '응답 데이터를 해석하지 못했습니다.',
        statusCode: statusCode,
      );
    }
  }
}
