// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'attendance_admin_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AdminAttendanceRecord _$AdminAttendanceRecordFromJson(
  Map<String, dynamic> json,
) => AdminAttendanceRecord(
  recordId: (json['recordId'] as num).toInt(),
  memberId: (json['memberId'] as num).toInt(),
  memberName: json['memberName'] as String,
  stdId: json['stdId'] as String,
  attendanceStatus: AttendanceStatus.fromWire(
    json['attendanceStatus'] as String,
  ),
  checkedAt: json['checkedAt'] == null
      ? null
      : DateTime.parse(json['checkedAt'] as String),
  isManual: json['isManual'] as bool? ?? false,
  adminNote: json['adminNote'] as String?,
);
