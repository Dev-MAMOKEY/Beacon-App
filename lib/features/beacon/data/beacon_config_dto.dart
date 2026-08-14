import 'package:json_annotation/json_annotation.dart';

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
