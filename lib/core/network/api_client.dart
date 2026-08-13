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
    try {
      final response = await run();
      return _unwrap(response.data, parse, response.statusCode);
    } on DioException catch (error) {
      final body = error.response?.data;
      if (body is Map<String, dynamic>) {
        // 4xx/5xx라도 본문이 래퍼 형식이면 서버 에러 코드를 살린다.
        return _unwrap(body, parse, error.response?.statusCode);
      }
      throw ApiException(
        ErrorCode.network,
        '서버에 연결하지 못했습니다.',
        statusCode: error.response?.statusCode,
      );
    }
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
      final code = error is Map ? error['code'] as String? : null;
      final message = error is Map ? error['message'] as String? : null;
      throw ApiException(
        ErrorCode.fromWire(code),
        message ?? '알 수 없는 오류가 발생했습니다.',
        statusCode: statusCode,
      );
    }

    return parse(body['data']);
  }
}
