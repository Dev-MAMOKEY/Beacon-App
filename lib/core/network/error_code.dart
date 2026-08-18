/// 서버 `error.code` 문자열을 타입 안전하게 다루기 위한 매핑.
/// 새 코드가 늘어도 화면 분기를 고칠 필요 없이 [unknown] 으로 흡수된다.
enum ErrorCode {
  // 인증
  invalidCredentials('INVALID_CREDENTIALS'),
  tokenMissing('TOKEN_MISSING'),
  tokenExpired('TOKEN_EXPIRED'),
  tokenInvalid('TOKEN_INVALID'),
  refreshTokenExpired('REFRESH_TOKEN_EXPIRED'),
  refreshTokenInvalid('REFRESH_TOKEN_INVALID'),
  refreshTokenRevoked('REFRESH_TOKEN_REVOKED'),

  // 권한
  forbidden('FORBIDDEN'),
  notClubMember('NOT_CLUB_MEMBER'),

  // 회원 · 동아리
  duplicateStudentId('DUPLICATE_STUDENT_ID'),
  invalidInviteCode('INVALID_INVITE_CODE'),
  alreadyClubMember('ALREADY_CLUB_MEMBER'),
  clubNotFound('CLUB_NOT_FOUND'),
  memberNotFound('MEMBER_NOT_FOUND'),

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

/// "자격 증명 자체가 죽었다" — 재시도가 아니라 재로그인이 필요하다는 뜻인
/// 코드들의 공용 집합.
///
/// 여기 없는 코드는 전부 일시적 실패로 취급된다(네트워크 단절, 5xx, 응답
/// 파싱 실패 등) — 토큰을 지울 근거가 없다.
const Set<ErrorCode> authFailureCodes = {
  ErrorCode.invalidCredentials,
  ErrorCode.tokenMissing,
  ErrorCode.tokenExpired,
  ErrorCode.tokenInvalid,
  ErrorCode.refreshTokenExpired,
  ErrorCode.refreshTokenInvalid,
  ErrorCode.refreshTokenRevoked,
  ErrorCode.memberNotFound,
};

bool isAuthFailureCode(ErrorCode code) => authFailureCodes.contains(code);

/// 실패 응답 하나가 "자격 증명 자체가 죽었다"를 뜻하는지 판정하는 **정본**.
/// SessionController와 AuthInterceptor가 둘 다 이 함수를 부른다 — 예전에는
/// 집합만 공유하고 판정은 각자 했는데, 그 결과 인터셉터는 401/403이 아닌
/// 응답을 코드도 보지 않고 일시적 실패로 넘겨버리고 컨트롤러는 상태 코드와
/// 무관하게 코드만 봤다. 실 백엔드가 `MEMBER_NOT_FOUND`를 **404**로
/// 내려주기 때문에 이 어긋남은 그대로 버그였다: 재발급이 404
/// MEMBER_NOT_FOUND로 실패해도 인터셉터는 토큰을 남기고 만료 콜백도 부르지
/// 않아, 사용자가 모든 요청이 실패하는 화면에서 로그인으로 돌아갈 길 없이
/// 갇혔다.
///
/// 판정 규칙:
/// - 서버가 내려준 `error.code`가 정본이다. 인식된 코드라면 상태 코드가
///   무엇이든(404 포함) 그 코드가 말하는 대로 따른다.
/// - 코드를 읽어내지 못했을 때([ErrorCode.unknown] — 래퍼가 아닌 바디,
///   `code` 누락, 매핑되지 않은 새 코드)에만 상태 코드를 근거로 삼는다.
///   401/403은 그 자체로 "자격 증명이 거부됐다"는 충분한 증거다.
/// - 응답이 아예 없거나(네트워크 단절·타임아웃 → [ErrorCode.network]) 5xx면
///   자격 증명을 무효라고 볼 근거가 없다.
bool isAuthFailure({required ErrorCode code, required int? statusCode}) {
  if (code != ErrorCode.unknown) return isAuthFailureCode(code);
  return statusCode == 401 || statusCode == 403;
}
