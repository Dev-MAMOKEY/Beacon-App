import 'error_code.dart';

class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.statusCode});

  final ErrorCode code;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException(${code.name}, $message, status: $statusCode)';
}
