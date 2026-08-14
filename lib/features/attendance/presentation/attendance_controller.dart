import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/error_code.dart';
import '../data/attendance_dto.dart';
import '../data/attendance_repository.dart';

/// 출석 체크 한 번의 결과. 홈 화면은 이 값으로만 분기한다 — `ApiException`을
/// 화면까지 그대로 흘려보내지 않는다.
sealed class CheckInResult {
  const CheckInResult();
}

class CheckInSuccess extends CheckInResult {
  const CheckInSuccess(this.status, this.checkedAt);

  final AttendanceStatus status;

  /// checkIn API는 상태만 돌려주고 처리 시각을 돌려주지 않는다 —
  /// 성공 응답을 받은 이 순간을 처리 시각으로 쓴다.
  final DateTime checkedAt;
}

class CheckInInvalidCode extends CheckInResult {
  const CheckInInvalidCode();
}

class CheckInAlreadyDone extends CheckInResult {
  const CheckInAlreadyDone();
}

class CheckInFailed extends CheckInResult {
  const CheckInFailed(this.message);

  final String message;
}

/// 출석 체크 제출과 재시도 정책을 화면 위젯에서 분리한 순수 로직 —
/// `AttendanceRepository`만 알고 `BuildContext`/`Widget`은 전혀 모른다.
///
/// 재시도 정책: `INVALID_ATTENDANCE_CODE`·`ALREADY_CHECKED_IN`은 같은
/// 코드를 다시 보내도 결과가 달라지지 않으므로 재시도하지 않는다. 그 외
/// (네트워크 단절, 5xx, 파싱 실패 등)만 **정확히 한 번** 자동 재시도한다 —
/// 그 재시도마저 실패하면 더는 반복하지 않고 `CheckInFailed`로 확정해,
/// 화면이 수동 재시도 버튼을 보여줄 수 있게 한다.
class AttendanceController {
  const AttendanceController(this._repository);

  final AttendanceRepository _repository;

  Future<CheckInResult> submit({
    required int clubId,
    required int sessionId,
    required String otpCode,
  }) {
    return _attempt(clubId: clubId, sessionId: sessionId, otpCode: otpCode, allowRetry: true);
  }

  Future<CheckInResult> _attempt({
    required int clubId,
    required int sessionId,
    required String otpCode,
    required bool allowRetry,
  }) async {
    try {
      final status = await _repository.checkIn(
        clubId: clubId,
        sessionId: sessionId,
        otpCode: otpCode,
      );
      return CheckInSuccess(status, DateTime.now());
    } on ApiException catch (error) {
      switch (error.code) {
        case ErrorCode.invalidAttendanceCode:
          return const CheckInInvalidCode();
        case ErrorCode.alreadyCheckedIn:
          return const CheckInAlreadyDone();
        default:
          if (allowRetry) {
            return _attempt(
              clubId: clubId,
              sessionId: sessionId,
              otpCode: otpCode,
              allowRetry: false,
            );
          }
          return CheckInFailed(error.message);
      }
    }
  }
}

final attendanceControllerProvider = Provider<AttendanceController>((ref) {
  return AttendanceController(ref.watch(attendanceRepositoryProvider));
});
