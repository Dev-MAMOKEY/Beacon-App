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

  factory BeaconConfig.fromJson(Map<String, dynamic> json) => _$BeaconConfigFromJson(json);

  final String uuid;
  final int lateThresholdMinutes;
  final int rssiStabilizationSeconds;
  final int rssiThreshold;
}
