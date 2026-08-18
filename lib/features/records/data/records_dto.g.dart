// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'records_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AttendanceRecordItem _$AttendanceRecordItemFromJson(
  Map<String, dynamic> json,
) => AttendanceRecordItem(
  sessionId: (json['sessionId'] as num).toInt(),
  sessionName: json['sessionName'] as String,
  date: DateTime.parse(json['date'] as String),
  status: AttendanceStatus.fromWire(json['status'] as String),
  checkedAt: json['checkedAt'] == null
      ? null
      : DateTime.parse(json['checkedAt'] as String),
  adminNote: json['adminNote'] as String?,
);

MonthlyRecords _$MonthlyRecordsFromJson(Map<String, dynamic> json) =>
    MonthlyRecords(
      year: (json['year'] as num).toInt(),
      month: (json['month'] as num).toInt(),
      records: (json['records'] as List<dynamic>)
          .map((e) => AttendanceRecordItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      present: (json['present'] as num).toInt(),
      absent: (json['absent'] as num).toInt(),
      late: (json['late'] as num).toInt(),
      etc: (json['etc'] as num).toInt(),
      attendanceRate: (json['attendanceRate'] as num).toDouble(),
    );
