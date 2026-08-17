// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'beacon_config_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BeaconConfig _$BeaconConfigFromJson(Map<String, dynamic> json) => BeaconConfig(
  uuid: json['uuid'] as String,
  lateThresholdMinutes: (json['lateThresholdMinutes'] as num).toInt(),
  rssiStabilizationSeconds: (json['rssiStabilizationSeconds'] as num).toInt(),
  rssiThreshold: (json['rssiThreshold'] as num).toInt(),
);

Map<String, dynamic> _$BeaconConfigToJson(BeaconConfig instance) =>
    <String, dynamic>{
      'uuid': instance.uuid,
      'lateThresholdMinutes': instance.lateThresholdMinutes,
      'rssiStabilizationSeconds': instance.rssiStabilizationSeconds,
      'rssiThreshold': instance.rssiThreshold,
    };
