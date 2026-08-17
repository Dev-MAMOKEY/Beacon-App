// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AdminSession _$AdminSessionFromJson(Map<String, dynamic> json) => AdminSession(
  sessionId: (json['sessionId'] as num).toInt(),
  sessionName: json['sessionName'] as String,
  status: SessionStatus.fromWire(json['status'] as String),
  expectStartAt: json['expectStartAt'] == null
      ? null
      : DateTime.parse(json['expectStartAt'] as String),
  expectEndAt: json['expectEndAt'] == null
      ? null
      : DateTime.parse(json['expectEndAt'] as String),
  startAt: json['startAt'] == null
      ? null
      : DateTime.parse(json['startAt'] as String),
  endAt: json['endAt'] == null ? null : DateTime.parse(json['endAt'] as String),
);

SessionStartResult _$SessionStartResultFromJson(Map<String, dynamic> json) =>
    SessionStartResult(
      otpCode: json['otpCode'] as String,
      uuid: json['uuid'] as String,
    );
