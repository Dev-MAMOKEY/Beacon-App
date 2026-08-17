import 'package:json_annotation/json_annotation.dart';

import '../../attendance/data/attendance_dto.dart';

part 'attendance_admin_dto.g.dart';

/// `GET /clubs/{clubId}/sessions/{sessionId}/attendance`의 항목.
///
/// 부원용 `AttendanceRecordItem`(기록 화면)과 다른 타입인 이유: 이쪽은
/// **누가** 출석했는지가 핵심이라 `memberId`/`memberName`/`stdId`를 담고,
/// 수동 처리 여부(`isManual`)와 관리자 메모(`adminNote`)가 있다. 부원은
/// 자기 기록만 보므로 그 필드가 없다.
@JsonSerializable(createToJson: false)
class AdminAttendanceRecord {
  const AdminAttendanceRecord({
    required this.recordId,
    required this.memberId,
    required this.memberName,
    required this.stdId,
    required this.attendanceStatus,
    this.checkedAt,
    this.isManual = false,
    this.adminNote,
  });

  factory AdminAttendanceRecord.fromJson(Map<String, dynamic> json) =>
      _$AdminAttendanceRecordFromJson(json);

  final int recordId;
  final int memberId;
  final String memberName;
  final String stdId;

  @JsonKey(fromJson: AttendanceStatus.fromWire)
  final AttendanceStatus attendanceStatus;

  /// 체크인 시각. 결석은 체크인 자체가 없으므로 null이다.
  final DateTime? checkedAt;

  /// 관리자가 손으로 넣었는지. 웹의 "처리 여부"(자동/수동) 열이 이 값이다.
  final bool isManual;

  /// 관리자 메모. 웹의 "사유" 열이다.
  final String? adminNote;
}

/// 출석 현황 요약. 서버가 주지 않아 목록에서 센다.
///
/// 웹 화면(`356:1800`)은 상단에 출석·지각·결석·기타 네 수를 카드로 보여준다.
/// `SliceAttendanceDto`에는 그런 집계가 없고 `totalElements`조차 없으므로
/// 받은 목록을 직접 센다 — 목록을 이미 전부 받았으니 추가 요청은 없다.
class AttendanceSummary {
  const AttendanceSummary({
    required this.present,
    required this.late,
    required this.absent,
    required this.etc,
  });

  factory AttendanceSummary.of(Iterable<AdminAttendanceRecord> records) {
    var present = 0;
    var late = 0;
    var absent = 0;
    var etc = 0;
    for (final record in records) {
      switch (record.attendanceStatus) {
        case AttendanceStatus.present:
          present++;
        case AttendanceStatus.late:
          late++;
        case AttendanceStatus.absent:
          absent++;
        case AttendanceStatus.etc:
          etc++;
      }
    }
    return AttendanceSummary(present: present, late: late, absent: absent, etc: etc);
  }

  final int present;
  final int late;
  final int absent;
  final int etc;

  int countOf(AttendanceStatus status) => switch (status) {
    AttendanceStatus.present => present,
    AttendanceStatus.late => late,
    AttendanceStatus.absent => absent,
    AttendanceStatus.etc => etc,
  };
}
