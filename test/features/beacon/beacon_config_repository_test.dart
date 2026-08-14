import 'package:beacon_app/core/network/api_client.dart';
import 'package:beacon_app/core/network/api_exception.dart';
import 'package:beacon_app/features/beacon/data/beacon_config_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

/// club_repository_test.dart와 같은 스타일을 유지하려고 needsExactBody: true를
/// 쓴다. 이 값은 **요청** 바디가 등록한 값과 정확히 일치하는지(여분의 키가
/// 없는지)만 따진다 — 이 파일은 전부 GET이라 요청 바디 자체가 없으니
/// needsExactBody는 사실상 이 스위트에 영향이 없고, 응답 바디의 여분 키
/// 여부와는 아무 관계가 없다. 경로(`onGet`에 등록한 문자열)는 이 플래그와
/// 무관하게 항상 정확히 일치해야 매칭된다. "4개 필드를 정확히 파싱한다"는
/// 보증은 이 매처가 아니라 각 테스트의 `expect(config.xxx, ...)` 자체에서
/// 나온다.
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

  test('필드가 누락된 응답은 캐스팅 예외 대신 ApiException으로 올라온다', () async {
    // ApiClient._unwrap의 catch-all이 parse() 내부의 어떤 예외든
    // ApiException으로 감싼다는 계약을 이 DTO 파싱 경로에서도 확인한다 —
    // 화면이 raw TypeError/캐스팅 예외를 볼 일이 없어야 한다.
    adapter.onGet(
      '/clubs/9/beacon',
      (server) => server.reply(200, {
        'success': true,
        'data': {
          'uuid': 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0',
          'lateThresholdMinutes': 10,
          // rssiStabilizationSeconds가 통째로 빠졌다.
          'rssiThreshold': -70,
        },
        'error': null,
        'timestamp': '2026-08-14T00:00:00Z',
      }),
    );

    await expectLater(repository.fetch(9), throwsA(isA<ApiException>()));
  });

  test('rssiStabilizationSeconds가 0 이하면 설정 오류로 취급한다', () async {
    // 잡아야 할 잘못된 구현: 값을 검증 없이 그대로 통과시킨다 — 그러면
    // 첫 샘플이 곧장 `elapsed >= 0s`(또는 음수)를 만족해 안정화 보장이
    // 조용히 무력화된다.
    adapter.onGet(
      '/clubs/11/beacon',
      (server) => server.reply(200, {
        'success': true,
        'data': {
          'uuid': 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0',
          'lateThresholdMinutes': 10,
          'rssiStabilizationSeconds': -1,
          'rssiThreshold': -70,
        },
        'error': null,
        'timestamp': '2026-08-14T00:00:00Z',
      }),
    );

    await expectLater(repository.fetch(11), throwsA(isA<ApiException>()));
  });

  test('rssiThreshold가 0 이상이면 설정 오류로 취급한다', () async {
    // 잡아야 할 잘못된 구현: 값을 검증 없이 그대로 통과시킨다 — 실제
    // RSSI는 항상 음수이므로 0 이상인 임계값은 모든 판독값을 무조건
    // 통과시켜 안정화 조건 자체를 무의미하게 만든다.
    adapter.onGet(
      '/clubs/12/beacon',
      (server) => server.reply(200, {
        'success': true,
        'data': {
          'uuid': 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0',
          'lateThresholdMinutes': 10,
          'rssiStabilizationSeconds': 3,
          'rssiThreshold': 0,
        },
        'error': null,
        'timestamp': '2026-08-14T00:00:00Z',
      }),
    );

    await expectLater(repository.fetch(12), throwsA(isA<ApiException>()));
  });

  test('uuid가 빈 문자열이면 설정 오류로 취급한다', () async {
    adapter.onGet(
      '/clubs/13/beacon',
      (server) => server.reply(200, {
        'success': true,
        'data': {
          'uuid': '   ',
          'lateThresholdMinutes': 10,
          'rssiStabilizationSeconds': 3,
          'rssiThreshold': -70,
        },
        'error': null,
        'timestamp': '2026-08-14T00:00:00Z',
      }),
    );

    await expectLater(repository.fetch(13), throwsA(isA<ApiException>()));
  });
}
