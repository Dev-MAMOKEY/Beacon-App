import 'package:flutter_dotenv/flutter_dotenv.dart';

/// `.env` 는 에셋으로 번들되므로 비밀값을 넣지 않는다.
/// PSK 같은 값은 secure storage에 둔다.
abstract final class AppConfig {
  static const String apiPathPrefix = '/api/v1';

  static Future<void> load() => dotenv.load();

  static String get apiBaseUrl {
    final value = dotenv.env['API_BASE_URL'];
    if (value == null || value.isEmpty) {
      throw StateError('.env에 API_BASE_URL이 없습니다. .env.example을 참고하세요.');
    }
    return value;
  }

  /// dio BaseOptions에 넣을 최종 주소.
  static String get apiRoot => '$apiBaseUrl$apiPathPrefix';
}
