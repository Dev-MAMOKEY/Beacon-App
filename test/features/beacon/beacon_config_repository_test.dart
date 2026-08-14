import 'package:beacon_app/core/network/api_client.dart';
import 'package:beacon_app/features/beacon/data/beacon_config_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

/// club_repository_test.dart와 같은 이유로 needsExactBody: true를 쓴다 —
/// http_mock_adapter의 기본 매처(needsExactBody: false)는 응답 바디에 여분의
/// 키가 있어도 매칭에 성공하므로, "4개 필드를 정확히 파싱한다"는 이름이
/// 거짓 보증이 될 수 있다. GET 요청이라 요청 바디는 없지만, 매처 자체는
/// 등록한 경로와 실제 요청 경로가 정확히 일치하는지도 함께 검사한다.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late HttpBeaconConfigRepository repository;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    adapter = DioAdapter(
      dio: dio,
      matcher: const FullHttpRequestMatcher(needsExactBody: true),
    );
    repository = HttpBeaconConfigRepository(ApiClient(dio));
  });

  test('fetch는 /clubs/{id}/beacon을 호출해 4개 필드를 파싱한다', () async {
    adapter.onGet(
      '/clubs/7/beacon',
      (server) => server.reply(200, {
        'success': true,
        'data': {
          'uuid': 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0',
          'lateThresholdMinutes': 10,
          'rssiStabilizationSeconds': 3,
          'rssiThreshold': -70,
        },
        'error': null,
        'timestamp': '2026-08-14T00:00:00Z',
      }),
    );

    // 등록한 경로('/clubs/7/beacon')와 실제 요청 경로가 다르면(오타 등)
    // DioAdapter가 매칭되는 규칙을 찾지 못해 예외를 던지고, 그 예외는
    // ApiClient를 거쳐 여기까지 올라온다 — 이 await가 성공한다는 것 자체가
    // 경로가 정확히 일치했다는 증거다.
    final config = await repository.fetch(7);

    expect(config.uuid, 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0');
    expect(config.lateThresholdMinutes, 10);
    expect(config.rssiStabilizationSeconds, 3);
    expect(config.rssiThreshold, -70);
  });

  test('다른 클럽 id를 경로에 그대로 반영한다', () async {
    adapter.onGet(
      '/clubs/42/beacon',
      (server) => server.reply(200, {
        'success': true,
        'data': {
          'uuid': 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE',
          'lateThresholdMinutes': 15,
          'rssiStabilizationSeconds': 5,
          'rssiThreshold': -65,
        },
        'error': null,
        'timestamp': '2026-08-14T00:00:00Z',
      }),
    );

    final config = await repository.fetch(42);

    expect(config.uuid, 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE');
  });
}
