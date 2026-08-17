import 'package:json_annotation/json_annotation.dart';

part 'attendance_dto.g.dart';

/// `GET /clubs/{clubId}/sessions/active` 응답. 진행 중인 세션이 없으면
/// [AttendanceRepository.fetchActiveSession]이 이 타입 대신 `null`을
/// 돌려준다 — 이 클래스 자체가 "없음"을 표현하지 않는다.
@JsonSerializable(createToJson: false)
class ActiveSession {
  const ActiveSession({
    required this.sessionId,
    required this.sessionName,
    required this.status,
    this.startAt,
  });

  factory ActiveSession.fromJson(Map<String, dynamic> json) =>
      _$ActiveSessionFromJson(json);

  final int sessionId;
  final String sessionName;

  /// `'SCHEDULED' | 'ACTIVE' | 'ENDED'`. 화면은 이 필드로 다시 분기하지
  /// 않는다 — "활성 세션 존재"의 정본은 `fetchActiveSession`이 null을
  /// 돌려주는지 여부다(엔드포인트 자체가 활성 세션만 돌려준다).
  final String status;

  final DateTime? startAt;
}

/// 출석 상태 4종(명세서 §출석 상태 관리). `ETC`는 서버가 자동으로 부여하지
/// 않고 관리자만 수동으로 남긴다 — 그래도 부원 화면이 자기 기록에서 그
/// 값을 받을 수는 있으므로 클라이언트도 이 값을 다뤄야 한다.
enum AttendanceStatus {
  present,
  late,
  absent,
  etc;

  /// 서버 `status` 문자열을 타입 안전하게 바꾼다. 인식하지 못하는 값은
  /// (형식은 맞지만 의미가 없는 값이라) [FormatException]으로 다룬다 —
  /// `ApiClient`가 이걸 잡아 `ApiException`으로 올린다. 지각 여부를 비롯한
  /// 모든 판정은 서버가 최종 결정하므로, 여기서 실수로 기본값을 골라주면
  /// (예: 모르는 값을 조용히 `present`로) "서버가 내려준 상태를 그대로
  /// 보여준다"는 보증이 깨진다.
  /// 서버로 되돌려 보낼 문자열. [fromWire]의 짝이다 — 관리자가 출석 상태를
  /// 손으로 바꿀 때(`PATCH .../attendance/{recordId}`) 이 값을 보낸다.
  ///
  /// Dart enum 이름(`present`)을 그대로 보내면 서버가 알아듣지 못한다.
  String get wire => switch (this) {
    AttendanceStatus.present => 'PRESENT',
    AttendanceStatus.late => 'LATE',
    AttendanceStatus.absent => 'ABSENT',
    AttendanceStatus.etc => 'ETC',
  };

  static AttendanceStatus fromWire(String wire) => switch (wire) {
    'PRESENT' => AttendanceStatus.present,
    'LATE' => AttendanceStatus.late,
    'ABSENT' => AttendanceStatus.absent,
    'ETC' => AttendanceStatus.etc,
    _ => throw FormatException('알 수 없는 출석 상태: $wire'),
  };
}
