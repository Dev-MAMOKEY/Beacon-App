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
