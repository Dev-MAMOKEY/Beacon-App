/// 서버 `error.code` 문자열을 타입 안전하게 다루기 위한 매핑.
/// 새 코드가 늘어도 화면 분기를 고칠 필요 없이 [unknown] 으로 흡수된다.
enum ErrorCode {
  // 인증
  invalidCredentials('INVALID_CREDENTIALS'),
  tokenMissing('TOKEN_MISSING'),
  tokenExpired('TOKEN_EXPIRED'),
  tokenInvalid('TOKEN_INVALID'),
  refreshTokenRevoked('REFRESH_TOKEN_REVOKED'),

  // 권한
  forbidden('FORBIDDEN'),
  notClubMember('NOT_CLUB_MEMBER'),

  // 회원 · 동아리
  duplicateStudentId('DUPLICATE_STUDENT_ID'),
  invalidInviteCode('INVALID_INVITE_CODE'),
  alreadyClubMember('ALREADY_CLUB_MEMBER'),
  clubNotFound('CLUB_NOT_FOUND'),

  // 세션
  sessionAlreadyActive('SESSION_ALREADY_ACTIVE'),
  sessionNotActive('SESSION_NOT_ACTIVE'),
  sessionNotFound('SESSION_NOT_FOUND'),
  otpGenerationFailed('OTP_GENERATION_FAILED'),

  // 출석
  invalidAttendanceCode('INVALID_ATTENDANCE_CODE'),
  alreadyCheckedIn('ALREADY_CHECKED_IN'),
  beaconNotDetected('BEACON_NOT_DETECTED'),

  /// 네트워크 자체가 실패해 서버 응답이 없는 경우. 서버가 내려주는 코드가 아니다.
  network('__NETWORK__'),

  /// 매핑되지 않은 모든 코드.
  unknown('__UNKNOWN__');

  const ErrorCode(this.wire);

  final String wire;

  static ErrorCode fromWire(String? wire) {
    if (wire == null) return ErrorCode.unknown;
    for (final code in ErrorCode.values) {
      if (code.wire == wire) return code;
    }
    return ErrorCode.unknown;
  }
}
