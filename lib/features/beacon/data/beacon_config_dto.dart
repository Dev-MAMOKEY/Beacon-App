import 'dart:math' as math;

import 'package:json_annotation/json_annotation.dart';

import '../domain/beacon_scanner.dart';

part 'beacon_config_dto.g.dart';

/// `GET /clubs/{id}/beacon` 응답. 클럽마다 다른 비콘 UUID와 판정 파라미터를
/// 담는다 — [BeaconScanConfig]는 이 값으로 채워진다.
@JsonSerializable(createToJson: false)
class BeaconConfig {
  const BeaconConfig({
    required this.uuid,
    required this.lateThresholdMinutes,
    required this.rssiStabilizationSeconds,
    required this.rssiThreshold,
  });

  /// 서버 응답을 파싱한 뒤 값 자체가 말이 되는지 확인한다. 형식은
  /// 맞지만(JSON 타입은 맞지만) 의미가 없는 값 — 예를 들어
  /// `rssiStabilizationSeconds: -1` — 은 그대로 두면 "첫 샘플이 바로
  /// `elapsed >= -1s`를 만족"하는 식으로 안정화 보장 자체를 조용히
  /// 무력화한다. 이런 값은 파싱 실패와 똑같이 [FormatException]으로
  /// 다뤄야 한다 — `ApiClient`가 이걸 잡아 `ApiException`으로 올린다.
  factory BeaconConfig.fromJson(Map<String, dynamic> json) {
    final config = _$BeaconConfigFromJson(json);

    if (config.uuid.trim().isEmpty) {
      throw const FormatException('BeaconConfig.uuid는 비어 있을 수 없습니다.');
    }
    if (config.rssiStabilizationSeconds <= 0) {
      throw FormatException(
        'BeaconConfig.rssiStabilizationSeconds는 1 이상이어야 합니다: ${config.rssiStabilizationSeconds}',
      );
    }
    // 실제 RSSI는 항상 음수다 — 0 이상인 임계값은 모든 판독값을 무조건
    // 통과시켜 안정화 조건을 무의미하게 만든다.
    if (config.rssiThreshold >= 0) {
      throw FormatException('BeaconConfig.rssiThreshold는 음수여야 합니다: ${config.rssiThreshold}');
    }

    return config;
  }

  final String uuid;
  final int lateThresholdMinutes;
  final int rssiStabilizationSeconds;
  final int rssiThreshold;
}

/// [BeaconConfig](서버 응답)를 [BeaconScanConfig](스캐너 입력)로 바꾸는
/// 유일한 경로. 서버는 `maxSampleGap`에 대응하는 필드를 내려주지 않으므로
/// [BeaconScanConfig]의 기본값(2초)을 쓰되, 그 기본값이 이 클럽의
/// `rssiStabilizationSeconds`보다 길면 안전 쪽으로 줄인다 — 그러지 않으면
/// 안정화 시간을 짧게 설정한 클럽에서 `BeaconScanConfig`의 생성 자체가
/// `ArgumentError`로 죽는다(`maxSampleGap`이 `stabilizationSeconds`를 넘을 수
/// 없다는 것이 그 생성자의 계약이고, 그 계약은 릴리즈 빌드에서도 살아 있다).
extension BeaconScanConfigMapping on BeaconConfig {
  BeaconScanConfig toScanConfig() {
    final gapSeconds = math.min(2, rssiStabilizationSeconds);
    return BeaconScanConfig(
      uuid: uuid,
      rssiThreshold: rssiThreshold,
      stabilizationSeconds: rssiStabilizationSeconds,
      maxSampleGap: Duration(seconds: gapSeconds),
    );
  }
}
