// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'attendance_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ActiveSession _$ActiveSessionFromJson(Map<String, dynamic> json) =>
    ActiveSession(
      sessionId: (json['sessionId'] as num).toInt(),
      sessionName: json['sessionName'] as String,
      status: json['status'] as String,
      startAt: json['startAt'] == null
          ? null
          : DateTime.parse(json['startAt'] as String),
    );
