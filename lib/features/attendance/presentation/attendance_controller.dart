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
  const CheckInSuccess(this.status);

  final AttendanceStatus status;
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

/// 재시도 직전에 근접 조건이 더는 참이 아니어서 **보내지 않았다.**
///
/// [CheckInFailed]와 구분하는 이유: 실패한 게 아니라 보내지 않기로 한
/// 것이고, 화면은 여기에 "다시 시도" 버튼을 붙이면 안 된다 — 방을 나간
/// 사용자에게 재시도를 권하는 꼴이 된다.
class CheckInAborted extends CheckInResult {
  const CheckInAborted();
}

/// 출석 체크 제출과 재시도 정책을 화면 위젯에서 분리한 순수 로직 —
/// `AttendanceRepository`만 알고 `BuildContext`/`Widget`은 전혀 모른다.
///
/// 재시도 정책은 **허용 목록**이다 — 재시도해서 결과가 달라질 수 있는
/// 코드만 나열하고 나머지는 전부 즉시 확정한다. 거부 목록으로 두면 서버에
/// 새 코드가 생길 때마다 기본값이 "재시도함"이 되어, 불가능한 요청을 한 번
/// 더 보내고 수동 재시도 버튼까지 띄우게 된다(리뷰 Important 3 — 원래
/// `SESSION_NOT_ACTIVE`·`SESSION_NOT_FOUND`·권한 오류가 `default:`로 떨어져
/// 재시도됐다). 모르는 코드에 대해 "보내지 않는다"가 안전한 기본값이다.
///
/// 재시도는 **정확히 한 번**이다. 그마저 실패하면 `CheckInFailed`로 확정해
/// 화면이 수동 재시도 버튼을 보여줄 수 있게 한다.
class AttendanceController {
  const AttendanceController(this._repository);

  final AttendanceRepository _repository;

  /// 재시도해서 결과가 달라질 수 있는 오류만.
  static const Set<ErrorCode> _retryableCodes = {
    // 서버에 닿지도 못했다 — 다시 보내면 성공할 수 있다.
    ErrorCode.network,
    // 5xx와 매핑되지 않은 코드가 여기로 온다. 일시적 장애일 수 있다.
    ErrorCode.unknown,
  };

  /// [stillEligible]은 **재시도 직전에** 다시 평가된다.
  ///
  /// 첫 시도는 화면의 제출 직전 검사와 `dio.post` 사이에 `await`가 없어
  /// 보호되지만, 재시도는 Dio 타임아웃(10초) 뒤에 나갈 수 있고 그 사이에
  /// 부원이 방을 나갔을 수 있다. 컨트롤러는 비콘을 알아서는 안 되므로
  /// 판정은 화면이 하고 여기서는 **호출만** 한다(리뷰 Important 2).
  ///
  /// `checkIn`은 `{'otpCode': ...}`만 보내 서버가 근접을 재검증할 수 없다 —
  /// 이 검사가 보증의 일부다.
  Future<CheckInResult> submit({
    required int clubId,
    required int sessionId,
    required String otpCode,
    bool Function()? stillEligible,
  }) {
    return _attempt(
      clubId: clubId,
      sessionId: sessionId,
      otpCode: otpCode,
      allowRetry: true,
      stillEligible: stillEligible,
    );
  }

  Future<CheckInResult> _attempt({
    required int clubId,
    required int sessionId,
    required String otpCode,
    required bool allowRetry,
    bool Function()? stillEligible,
  }) async {
    try {
      final status = await _repository.checkIn(
        clubId: clubId,
        sessionId: sessionId,
        otpCode: otpCode,
      );
      return CheckInSuccess(status);
    } on ApiException catch (error) {
      switch (error.code) {
        case ErrorCode.invalidAttendanceCode:
          return const CheckInInvalidCode();
        case ErrorCode.alreadyCheckedIn:
          return const CheckInAlreadyDone();
        default:
          if (allowRetry && _retryableCodes.contains(error.code)) {
            if (stillEligible != null && !stillEligible()) {
              return const CheckInAborted();
            }
            return _attempt(
              clubId: clubId,
              sessionId: sessionId,
              otpCode: otpCode,
              allowRetry: false,
              stillEligible: stillEligible,
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
