import 'package:beacon_app/core/network/api_exception.dart';
import 'package:beacon_app/core/network/error_code.dart';
import 'package:beacon_app/features/attendance/data/attendance_dto.dart';
import 'package:beacon_app/features/attendance/data/attendance_repository.dart';
import 'package:beacon_app/features/attendance/presentation/attendance_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// checkIn 호출을 스크립트로 넣을 수 있는 페이크. 몇 번째 호출인지도 함께
/// 기록해 재시도 횟수를 정확히 셀 수 있게 한다.
class _ScriptedAttendanceRepository implements AttendanceRepository {
  _ScriptedAttendanceRepository(this._results);

  final List<Object> _results; // AttendanceStatus 또는 ApiException
  int checkInCalls = 0;
  final List<(int clubId, int sessionId, String otpCode)> checkInArgs = [];

  @override
  Future<ActiveSession?> fetchActiveSession(int clubId) async => null;

  @override
  Future<AttendanceStatus> checkIn({
    required int clubId,
    required int sessionId,
    required String otpCode,
  }) async {
    checkInArgs.add((clubId, sessionId, otpCode));
    final result = _results[checkInCalls];
    checkInCalls++;
    if (result is ApiException) throw result;
    return result as AttendanceStatus;
  }
}

const _networkError = ApiException(ErrorCode.network, '서버에 연결하지 못했습니다.');

void main() {
  group('재시도 허용 목록 — 종결성 오류는 즉시 확정한다', () {
    // 잡아야 할 잘못된 구현: 거부 목록(`default:` 로 전부 재시도). 그러면
    // 종료된 세션에 대해 **같은 불가능한 요청을 한 번 더** 보내고 수동
    // 재시도 버튼까지 띄운다. 서버에 새 코드가 생길 때마다 기본값이
    // "재시도함"이 되는 것도 문제다(리뷰 Important 3).
    for (final code in <ErrorCode>[
      ErrorCode.sessionNotActive,
      ErrorCode.sessionNotFound,
      ErrorCode.forbidden,
      ErrorCode.notClubMember,
      ErrorCode.beaconNotDetected,
    ]) {
      test('$code 는 재시도하지 않는다', () async {
        final repo = _ScriptedAttendanceRepository([
          ApiException(code, '확정 오류'),
          ApiException(code, '확정 오류'),
        ]);
        final result = await AttendanceController(
          repo,
        ).submit(clubId: 7, sessionId: 88, otpCode: '1234');

        expect(result, isA<CheckInFailed>());
        expect(repo.checkInCalls, 1, reason: '$code: 재시도하면 안 된다');
      });
    }

    test('네트워크 오류는 여전히 정확히 한 번 재시도한다', () async {
      final repo = _ScriptedAttendanceRepository([
        const ApiException(ErrorCode.network, '연결 실패'),
        AttendanceStatus.present,
      ]);
      final result = await AttendanceController(
        repo,
      ).submit(clubId: 7, sessionId: 88, otpCode: '1234');

      expect(result, isA<CheckInSuccess>());
      expect(repo.checkInCalls, 2);
    });

    test('알 수 없는 코드(5xx 포함)도 한 번 재시도한다', () async {
      final repo = _ScriptedAttendanceRepository([
        const ApiException(ErrorCode.unknown, '일시적 오류'),
        AttendanceStatus.present,
      ]);
      final result = await AttendanceController(
        repo,
      ).submit(clubId: 7, sessionId: 88, otpCode: '1234');

      expect(result, isA<CheckInSuccess>());
      expect(repo.checkInCalls, 2);
    });
  });

  group('재시도 직전 조건 재확인', () {
    test('조건이 거짓이 되면 재시도를 보내지 않고 CheckInAborted를 돌려준다', () async {
      // 잡아야 할 잘못된 구현: 재시도가 조건을 다시 보지 않는다. 첫 시도는
      // 제출 직전 검사와 `dio.post` 사이에 `await`가 없어 보호되지만,
      // 재시도는 Dio 타임아웃(10초) 뒤에 나갈 수 있고 그 사이에 부원이 방을
      // 나갔을 수 있다(리뷰 Important 2).
      final repo = _ScriptedAttendanceRepository([
        const ApiException(ErrorCode.network, '연결 실패'),
        AttendanceStatus.present,
      ]);
      final result = await AttendanceController(repo).submit(
        clubId: 7,
        sessionId: 88,
        otpCode: '1234',
        stillEligible: () => false,
      );

      expect(result, isA<CheckInAborted>());
      expect(repo.checkInCalls, 1, reason: '두 번째 요청이 나가면 안 된다');
    });

    test('조건이 참이면 재시도를 그대로 보낸다', () async {
      // 부정 짝이 없으면 `stillEligible`을 항상 거짓으로 취급하는 구현도 통과한다.
      final repo = _ScriptedAttendanceRepository([
        const ApiException(ErrorCode.network, '연결 실패'),
        AttendanceStatus.present,
      ]);
      final result = await AttendanceController(repo).submit(
        clubId: 7,
        sessionId: 88,
        otpCode: '1234',
        stillEligible: () => true,
      );

      expect(result, isA<CheckInSuccess>());
      expect(repo.checkInCalls, 2);
    });

    test('첫 시도는 조건을 다시 묻지 않는다', () async {
      // 첫 시도는 화면이 이미 직전에 검사했다 — 여기서 또 물으면 그 사이
      // 도착한 이벤트 하나로 정상 제출이 취소될 수 있다.
      var asked = 0;
      final repo = _ScriptedAttendanceRepository([AttendanceStatus.present]);
      await AttendanceController(repo).submit(
        clubId: 7,
        sessionId: 88,
        otpCode: '1234',
        stillEligible: () {
          asked++;
          return true;
        },
      );

      expect(asked, 0);
      expect(repo.checkInCalls, 1);
    });
  });

  test('네트워크 오류가 나면 정확히 1회만 자동 재시도한 뒤 실패로 확정한다', () async {
    // 잡아야 할 잘못된 구현: 재시도를 아예 하지 않거나(checkInCalls==1에서
    // 실패 확정), 실패할 때마다 무한히 재시도한다(_results가 바닥나 예외로
    // 죽거나 매우 오래 걸린다). 정답은 정확히 2번(최초 시도 + 자동 재시도
    // 1회) 호출되고 그 이상은 스스로 멈춘다.
    final repository = _ScriptedAttendanceRepository([_networkError, _networkError]);
    final controller = AttendanceController(repository);

    final result = await controller.submit(clubId: 7, sessionId: 42, otpCode: '1234');

    expect(repository.checkInCalls, 2, reason: '최초 시도 + 자동 재시도 1회 = 정확히 2번');
    expect(result, isA<CheckInFailed>());
  });

  test('자동 재시도가 성공하면 CheckInSuccess를 돌려준다', () async {
    final repository = _ScriptedAttendanceRepository([_networkError, AttendanceStatus.present]);
    final controller = AttendanceController(repository);

    final result = await controller.submit(clubId: 7, sessionId: 42, otpCode: '1234');

    expect(repository.checkInCalls, 2);
    expect(result, isA<CheckInSuccess>());
    expect((result as CheckInSuccess).status, AttendanceStatus.present);
  });

  test('첫 시도가 바로 성공하면 재시도하지 않는다', () async {
    final repository = _ScriptedAttendanceRepository([AttendanceStatus.present]);
    final controller = AttendanceController(repository);

    await controller.submit(clubId: 7, sessionId: 42, otpCode: '1234');

    expect(repository.checkInCalls, 1);
  });

  test('INVALID_ATTENDANCE_CODE는 재시도하지 않고 즉시 확정한다', () async {
    final repository = _ScriptedAttendanceRepository([
      const ApiException(ErrorCode.invalidAttendanceCode, '비밀번호가 올바르지 않습니다.'),
    ]);
    final controller = AttendanceController(repository);

    final result = await controller.submit(clubId: 7, sessionId: 42, otpCode: '0000');

    expect(repository.checkInCalls, 1, reason: '같은 코드를 다시 보내도 결과는 똑같으므로 재시도하지 않는다');
    expect(result, isA<CheckInInvalidCode>());
  });

  test('ALREADY_CHECKED_IN은 재시도하지 않고 즉시 확정한다', () async {
    final repository = _ScriptedAttendanceRepository([
      const ApiException(ErrorCode.alreadyCheckedIn, '이미 출석 처리되었습니다.'),
    ]);
    final controller = AttendanceController(repository);

    final result = await controller.submit(clubId: 7, sessionId: 42, otpCode: '1234');

    expect(repository.checkInCalls, 1);
    expect(result, isA<CheckInAlreadyDone>());
  });

  test('submit은 clubId/sessionId/otpCode를 그대로 리포지토리에 전달한다', () async {
    final repository = _ScriptedAttendanceRepository([AttendanceStatus.present]);
    final controller = AttendanceController(repository);

    await controller.submit(clubId: 11, sessionId: 99, otpCode: '5678');

    expect(repository.checkInArgs.single, (11, 99, '5678'));
  });
}
