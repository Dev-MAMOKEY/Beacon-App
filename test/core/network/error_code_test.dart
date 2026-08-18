import 'package:beacon_app/core/network/error_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fromWire', () {
    // 오타 회귀 방지: 각 코드가 정확히 그 wire 문자열에만 매핑돼야 한다.
    // enum 상수 이름이 아니라 서버가 실제로 내려주는 문자열을 정본으로 삼는다.
    test('REFRESH_TOKEN_EXPIRED는 refreshTokenExpired로 매핑된다', () {
      expect(ErrorCode.fromWire('REFRESH_TOKEN_EXPIRED'), ErrorCode.refreshTokenExpired);
    });

    test('REFRESH_TOKEN_INVALID는 refreshTokenInvalid로 매핑된다', () {
      expect(ErrorCode.fromWire('REFRESH_TOKEN_INVALID'), ErrorCode.refreshTokenInvalid);
    });

    test('REFRESH_TOKEN_REVOKED는 refreshTokenRevoked로 매핑된다', () {
      expect(ErrorCode.fromWire('REFRESH_TOKEN_REVOKED'), ErrorCode.refreshTokenRevoked);
    });

    test('MEMBER_NOT_FOUND는 memberNotFound로 매핑된다', () {
      expect(ErrorCode.fromWire('MEMBER_NOT_FOUND'), ErrorCode.memberNotFound);
    });

    test('알려지지 않은 문자열은 unknown으로 흡수된다', () {
      expect(ErrorCode.fromWire('SOMETHING_NEW'), ErrorCode.unknown);
    });

    test('null은 unknown으로 흡수된다', () {
      expect(ErrorCode.fromWire(null), ErrorCode.unknown);
    });
  });

  group('authFailureCodes', () {
    // 실 백엔드(/v3/api-docs)에서 확인한 세 refresh 실패 코드와
    // MEMBER_NOT_FOUND는 전부 "재로그인이 필요하다"는 뜻이다. 이 집합에서
    // 하나라도 빠지면(실수로 지우거나 오타를 내면) SessionController와
    // AuthInterceptor 양쪽 다 그 코드를 "일시적 실패"로 오분류해
    // 사용자를 복구 불가능한 재시도 화면에 가둔다.
    test('refresh 관련 인증 실패 코드를 전부 포함한다', () {
      expect(authFailureCodes, contains(ErrorCode.refreshTokenExpired));
      expect(authFailureCodes, contains(ErrorCode.refreshTokenInvalid));
      expect(authFailureCodes, contains(ErrorCode.refreshTokenRevoked));
      expect(authFailureCodes, contains(ErrorCode.memberNotFound));
    });

    test('로그인/토큰 관련 인증 실패 코드를 전부 포함한다', () {
      expect(authFailureCodes, contains(ErrorCode.invalidCredentials));
      expect(authFailureCodes, contains(ErrorCode.tokenExpired));
      expect(authFailureCodes, contains(ErrorCode.tokenInvalid));
      expect(authFailureCodes, contains(ErrorCode.tokenMissing));
    });

    test('네트워크/알 수 없음은 포함하지 않는다', () {
      expect(authFailureCodes, isNot(contains(ErrorCode.network)));
      expect(authFailureCodes, isNot(contains(ErrorCode.unknown)));
    });

    test('isAuthFailureCode는 authFailureCodes 멤버십과 일치한다', () {
      for (final code in ErrorCode.values) {
        expect(isAuthFailureCode(code), authFailureCodes.contains(code));
      }
    });
  });

  // SessionController와 AuthInterceptor가 **같은** 이 함수를 부른다. 예전에는
  // 집합만 공유하고 판정은 각자 했는데, 인터셉터 쪽이 401/403이 아닌 응답을
  // code를 보기도 전에 걸러내는 바람에 404 MEMBER_NOT_FOUND가 조용히
  // 일시적 실패로 새어나갔다.
  group('isAuthFailure — 상태 코드보다 error.code가 정본이다', () {
    test('인식된 인증 실패 코드는 상태 코드가 404여도 인증 실패다', () {
      expect(
        isAuthFailure(code: ErrorCode.memberNotFound, statusCode: 404),
        isTrue,
      );
    });

    test('인식된 인증 실패 코드는 상태 코드가 없어도 인증 실패다', () {
      expect(
        isAuthFailure(code: ErrorCode.refreshTokenRevoked, statusCode: null),
        isTrue,
      );
    });

    test('인증 실패 집합 밖의 인식된 코드는 401이어도 인증 실패가 아니다', () {
      // 권한 부족(FORBIDDEN)은 자격 증명이 죽었다는 뜻이 아니다 — 여기서
      // 로그아웃시키면 멀쩡한 세션을 날린다.
      expect(isAuthFailure(code: ErrorCode.forbidden, statusCode: 403), isFalse);
      expect(isAuthFailure(code: ErrorCode.notClubMember, statusCode: 401), isFalse);
    });

    test('code를 읽지 못한 경우에만 401/403을 근거로 삼는다', () {
      expect(isAuthFailure(code: ErrorCode.unknown, statusCode: 401), isTrue);
      expect(isAuthFailure(code: ErrorCode.unknown, statusCode: 403), isTrue);
      expect(isAuthFailure(code: ErrorCode.unknown, statusCode: 500), isFalse);
      expect(isAuthFailure(code: ErrorCode.unknown, statusCode: null), isFalse);
    });

    test('네트워크 실패는 어떤 상태 코드에서도 인증 실패가 아니다', () {
      expect(isAuthFailure(code: ErrorCode.network, statusCode: null), isFalse);
      expect(isAuthFailure(code: ErrorCode.network, statusCode: 401), isFalse);
    });
  });
}
