import 'package:json_annotation/json_annotation.dart';

part 'session_dto.g.dart';

/// 세션의 진행 상태. 서버 enum(`SCHEDULED | ACTIVE | ENDED`)을 그대로 옮긴다.
///
/// 인식하지 못하는 값을 조용히 기본값으로 고르지 않는 이유는
/// `AttendanceStatus.fromWire`와 같다 — 관리자 화면의 모든 분기(시작 버튼을
/// 보일지, 종료 버튼을 보일지)가 이 값 위에 서 있어서, 모르는 값을 임의로
/// 접으면 끝난 세션에 "출석 종료하기"를 띄우는 식으로 조용히 어긋난다.
enum SessionStatus {
  scheduled,
  active,
  ended;

  static SessionStatus fromWire(String wire) => switch (wire) {
    'SCHEDULED' => SessionStatus.scheduled,
    'ACTIVE' => SessionStatus.active,
    'ENDED' => SessionStatus.ended,
    _ => throw FormatException('알 수 없는 세션 상태: $wire'),
  };

  String get wire => switch (this) {
    SessionStatus.scheduled => 'SCHEDULED',
    SessionStatus.active => 'ACTIVE',
    SessionStatus.ended => 'ENDED',
  };
}

/// `GET /clubs/{clubId}/sessions`의 `content` 항목이자 상세 조회 응답.
///
/// **출석 인원은 이 응답에 없다.** Figma 관리자 화면(`353:2033`)은 카드마다
/// "출석인원 14/15"를 보여주지만 `SessionResponseDto`에는 그런 필드가 없고,
/// 세는 방법은 `GET .../attendance`(세션마다 한 번, 페이지네이션)뿐이다.
/// 목록의 모든 카드에 대해 부르면 N+1이 되므로 화면은 **진행 중 세션에
/// 대해서만** 센다(#14에 기록).
@JsonSerializable(createToJson: false)
class AdminSession {
  const AdminSession({
    required this.sessionId,
    required this.sessionName,
    required this.status,
    this.expectStartAt,
    this.expectEndAt,
    this.startAt,
    this.endAt,
  });

  factory AdminSession.fromJson(Map<String, dynamic> json) => _$AdminSessionFromJson(json);

  final int sessionId;
  final String sessionName;

  @JsonKey(fromJson: SessionStatus.fromWire)
  final SessionStatus status;

  /// 예정 시각. 목록 카드가 보여주는 "2026. 04. 07. 오후 6시"가 이 값이다.
  ///
  /// 실제 시작/종료 시각([startAt]/[endAt])과 다른 필드다 — 시작 전 세션은
  /// [startAt]이 비어 있으므로 카드가 예정 시각을 써야 한다.
  final DateTime? expectStartAt;
  final DateTime? expectEndAt;

  final DateTime? startAt;
  final DateTime? endAt;
}

/// 세션 시작 응답(`POST .../start`) — 출석 코드와 비콘에 실어 보낼 UUID.
///
/// [uuid]는 #15의 GATT 명령 페이로드 가운데 16바이트가 된다.
@JsonSerializable(createToJson: false)
class SessionStartResult {
  const SessionStartResult({required this.otpCode, required this.uuid});

  factory SessionStartResult.fromJson(Map<String, dynamic> json) =>
      _$SessionStartResultFromJson(json);

  final String otpCode;
  final String uuid;
}

/// 세션 생성/수정 요청.
///
/// **`expectEndAt`이 서버 필수 필드다.** 이슈 #14는 "이름, 예정 시간만
/// 입력"이라고 적었지만 `SessionCreateRequestDto`의 `required`는
/// `sessionName`·`expectStartAt`·`expectEndAt` 셋이다. 종료 예정 시각 없이는
/// 생성 자체가 되지 않으므로 폼이 그것도 받는다(#14에 기록).
///
/// 나머지 선택 필드(`sessionCategory`/`location`/`description`/반복 설정)는
/// 이슈가 명시적으로 제외했으므로 보내지 않는다 — 서버가 기본값을 정한다.
class SessionDraft {
  const SessionDraft({
    required this.sessionName,
    required this.expectStartAt,
    required this.expectEndAt,
  });

  final String sessionName;
  final DateTime expectStartAt;
  final DateTime expectEndAt;

  Map<String, dynamic> toJson() => {
    'sessionName': sessionName,
    // 서버는 UTC ISO 8601을 받는다 — 로컬 시각을 그대로 보내면 시간대만큼
    // 어긋난 세션이 만들어진다.
    'expectStartAt': expectStartAt.toUtc().toIso8601String(),
    'expectEndAt': expectEndAt.toUtc().toIso8601String(),
  };
}
