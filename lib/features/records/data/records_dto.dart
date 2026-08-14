import 'package:json_annotation/json_annotation.dart';

import '../../attendance/data/attendance_dto.dart';

part 'records_dto.g.dart';

/// 이번 달 기록 목록의 항목 하나. `GET /clubs/{clubId}/members/me/records`의
/// `records[]`.
@JsonSerializable(createToJson: false)
class AttendanceRecordItem {
  const AttendanceRecordItem({
    required this.sessionId,
    required this.sessionName,
    required this.date,
    required this.status,
    this.checkedAt,
    this.adminNote,
  });

  factory AttendanceRecordItem.fromJson(Map<String, dynamic> json) =>
      _$AttendanceRecordItemFromJson(json);

  final int sessionId;
  final String sessionName;
  final DateTime date;

  @JsonKey(fromJson: AttendanceStatus.fromWire)
  final AttendanceStatus status;

  /// 출석/지각인 경우에만 값이 있다.
  final DateTime? checkedAt;

  /// 관리자가 상태를 수동 변경할 때 남긴 사유. 대부분 비어 있다.
  final String? adminNote;
}

/// `GET /clubs/{clubId}/members/me/records?year=&month=` 응답 전체.
/// 홈 화면의 요약 카드 3종(출석률/지각/결석)과, Task 4의 기록 캘린더가
/// 그대로 소비한다.
@JsonSerializable(createToJson: false)
class MonthlyRecords {
  const MonthlyRecords({
    required this.year,
    required this.month,
    required this.records,
    required this.present,
    required this.absent,
    required this.late,
    required this.etc,
    required this.attendanceRate,
  });

  factory MonthlyRecords.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    if (status is! Map<String, dynamic>) {
      throw const FormatException('MonthlyRecords.status가 객체가 아닙니다.');
    }
    return _$MonthlyRecordsFromJson({...json, ...status});
  }

  final int year;
  final int month;
  final List<AttendanceRecordItem> records;

  // 서버 응답에서는 이 4개가 `status: {present, absent, late, etc}`로
  // 중첩돼 있다 — fromJson이 파싱 전에 평평하게 펼친다. **클라이언트가
  // records[]를 세어 이 값을 다시 계산하지 않는다** — 출석률 공식은 가입
  // 이전 세션을 분모에서 빼는 등 서버만 아는 규칙을 포함한다(Task 4 요구
  // 4번과 동일한 이유).
  final int present;
  final int absent;
  final int late;
  final int etc;

  final double attendanceRate;
}
