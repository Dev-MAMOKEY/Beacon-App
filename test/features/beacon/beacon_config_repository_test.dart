import 'package:beacon_app/core/network/api_client.dart';
import 'package:beacon_app/core/network/api_exception.dart';
import 'package:beacon_app/features/beacon/data/beacon_config_dto.dart';
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
  late List<RequestOptions> sent;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    sent = [];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          sent.add(options);
          handler.next(options);
        },
      ),
    );
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

  group('설정 수정', () {
    const stored = BeaconConfig(
      uuid: 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0',
      lateThresholdMinutes: 10,
      rssiStabilizationSeconds: 3,
      rssiThreshold: -70,
    );

    test('네 필드를 전부 담아 PUT한다', () async {
      // `PUT /clubs/{id}/beacon`은 네 필드가 전부 required인 **전체 교체**다.
      // uuid만 담아 보내면 지각 기준·안정화 시간·임계값이 함께 사라진다.
      final next = stored.copyWith(uuid: '11111111-2222-3333-4444-555555555555');
      adapter.onPut(
        '/clubs/7/beacon',
        (server) => server.reply(200, {
          'success': true,
          'data': {
            'uuid': '11111111-2222-3333-4444-555555555555',
            'lateThresholdMinutes': 10,
            'rssiStabilizationSeconds': 3,
            'rssiThreshold': -70,
          },
        }),
        data: {
          'uuid': '11111111-2222-3333-4444-555555555555',
          'lateThresholdMinutes': 10,
          'rssiStabilizationSeconds': 3,
          'rssiThreshold': -70,
        },
      );

      final saved = await repository.update(7, next);

      expect(sent.single.method, 'PUT');
      expect(sent.single.data, {
        'uuid': '11111111-2222-3333-4444-555555555555',
        'lateThresholdMinutes': 10,
        'rssiStabilizationSeconds': 3,
        'rssiThreshold': -70,
      });
      expect(saved.uuid, '11111111-2222-3333-4444-555555555555');
      expect(saved.lateThresholdMinutes, 10, reason: '보낸 값이 살아 돌아와야 한다');
    });

    test('서버가 다듬은 값을 돌려주면 그걸 쓴다', () async {
      // 보낸 것을 그대로 화면에 반영하면, 서버가 조정한 값과 화면이 어긋난다.
      adapter.onPut(
        '/clubs/7/beacon',
        (server) => server.reply(200, {
          'success': true,
          'data': {
            'uuid': 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0',
            'lateThresholdMinutes': 15,
            'rssiStabilizationSeconds': 3,
            'rssiThreshold': -70,
          },
        }),
        data: {
          'uuid': 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0',
          'lateThresholdMinutes': 999,
          'rssiStabilizationSeconds': 3,
          'rssiThreshold': -70,
        },
      );

      final saved = await repository.update(7, stored.copyWith(lateThresholdMinutes: 999));

      expect(saved.lateThresholdMinutes, 15);
    });

    test('돌려받은 값도 조회와 같은 규칙으로 검증한다', () async {
      // 저장 응답만 검증을 건너뛰면, 말이 안 되는 값이 그대로 화면과
      // 스캐너 설정으로 흘러든다.
      adapter.onPut(
        '/clubs/7/beacon',
        (server) => server.reply(200, {
          'success': true,
          'data': {
            'uuid': 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0',
            'lateThresholdMinutes': 10,
            'rssiStabilizationSeconds': 3,
            'rssiThreshold': 0,
          },
        }),
        data: {
          'uuid': 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0',
          'lateThresholdMinutes': 10,
          'rssiStabilizationSeconds': 3,
          'rssiThreshold': -70,
        },
      );

      await expectLater(repository.update(7, stored), throwsA(isA<ApiException>()));
    });

    test('copyWith는 네 필드를 각각 덮을 수 있다', () {
      // 한 필드만 덮어 보면, **덮지 못하는 필드**가 있어도(그 자리에
      // `this.x`를 그대로 쓴 구현) 눈치채지 못한다. 넷을 각각 본다.
      expect(stored.copyWith(uuid: 'X').uuid, 'X');
      expect(stored.copyWith(lateThresholdMinutes: 25).lateThresholdMinutes, 25);
      expect(stored.copyWith(rssiStabilizationSeconds: 9).rssiStabilizationSeconds, 9);
      expect(stored.copyWith(rssiThreshold: -85).rssiThreshold, -85);
    });

    test('copyWith는 지정하지 않은 값을 그대로 둔다', () {
      final next = stored.copyWith(rssiThreshold: -85);
      expect(next.uuid, stored.uuid);
      expect(next.lateThresholdMinutes, stored.lateThresholdMinutes);
      expect(next.rssiStabilizationSeconds, stored.rssiStabilizationSeconds);
    });
  });
}
