import 'package:beacon_app/features/beacon/data/beacon_config_dto.dart';
import 'package:beacon_app/features/beacon/domain/beacon_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

/// [BeaconScanConfig]는 여전히 Task 1에서 만든 순수 계약이지만, 서버가
/// 내려주는 [BeaconConfig]를 여기로 매핑하는 배선은 Task 3(이 파일)에서
/// 처음 생긴다. `maxSampleGap`이 `stabilizationSeconds`보다 길면, 그 사이의
/// 진짜 침묵(신호 없음)도 "연속 감지"로 오인되어 안정화 판정 자체가
/// 무의미해진다 — 그래서 생성자가 이 조합을 거부해야 한다.
void main() {
  test('maxSampleGap이 stabilizationSeconds 이하면 정상 생성된다', () {
    expect(
      () => BeaconScanConfig(
        uuid: 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0',
        stabilizationSeconds: 3,
        maxSampleGap: const Duration(seconds: 2),
      ),
      returnsNormally,
    );
  });

  test('maxSampleGap이 stabilizationSeconds보다 길면 릴리즈에서도 생성이 거부된다', () {
    // 잡아야 할 잘못된 구현 두 가지:
    // 1) 생성자에 검증이 아예 없어 이 조합도 그냥 통과시킨다 — 그러면 3초
    //    침묵 뒤에 온 샘플 하나가 5초짜리 "연속 감지"로 둔갑할 수 있다.
    // 2) 검증이 `assert`뿐이다. `assert`는 릴리즈 빌드에서 통째로 제거되므로
    //    프로덕션에서는 1)과 완전히 같아진다. `AssertionError`는
    //    `ArgumentError`가 아니므로, 이 기대는 assert만 쓰는 구현에서
    //    (디버그 모드에서조차) 실패한다 — 그게 이 테스트가 릴리즈 구멍을
    //    지목하는 방식이다.
    expect(
      () => BeaconScanConfig(
        uuid: 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0',
        stabilizationSeconds: 2,
        maxSampleGap: const Duration(seconds: 5),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  group('BeaconConfig.toScanConfig()', () {
    test('서버 설정의 4개 필드를 BeaconScanConfig로 매핑한다', () {
      const serverConfig = BeaconConfig(
        uuid: 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0',
        lateThresholdMinutes: 10,
        rssiStabilizationSeconds: 5,
        rssiThreshold: -70,
      );

      final scanConfig = serverConfig.toScanConfig();

      expect(scanConfig.uuid, serverConfig.uuid);
      expect(scanConfig.rssiThreshold, -70);
      expect(scanConfig.stabilizationSeconds, 5);
    });

    test('rssiStabilizationSeconds가 기본 maxSampleGap(2초)보다 짧으면 그 값에 맞춰 줄인다', () {
      // 잡아야 할 잘못된 구현: maxSampleGap을 항상 고정 2초로 넘겨, 서버가
      // stabilizationSeconds를 1초로 내려준 클럽에서 BeaconScanConfig
      // 생성 자체가 ArgumentError로 죽는다.
      const serverConfig = BeaconConfig(
        uuid: 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0',
        lateThresholdMinutes: 10,
        rssiStabilizationSeconds: 1,
        rssiThreshold: -70,
      );

      final scanConfig = serverConfig.toScanConfig();

      expect(scanConfig.maxSampleGap, lessThanOrEqualTo(const Duration(seconds: 1)));
    });
  });
}
