import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/network/error_code.dart';
import 'attendance_dto.dart';

abstract interface class AttendanceRepository {
  /// 진행 중인 활성 세션이 없으면 `null`을 돌려준다 — 이 신호가 "활성
  /// 세션 존재" AND 조건의 절반이다(나머지 절반은 비콘 감지).
  Future<ActiveSession?> fetchActiveSession(int clubId);

  /// 서버가 최종 판정한 상태를 돌려준다 — 지각 여부는 `lateThresholdMinutes`로
  /// 서버가 정하며 클라이언트는 계산하지 않는다.
  Future<AttendanceStatus> checkIn({
    required int clubId,
    required int sessionId,
    required String otpCode,
  });
}

class HttpAttendanceRepository implements AttendanceRepository {
  const HttpAttendanceRepository(this._client);

  final ApiClient _client;

  @override
  Future<ActiveSession?> fetchActiveSession(int clubId) async {
    try {
      return await _client.get<ActiveSession?>(
        '/clubs/$clubId/sessions/active',
        parse: (json) =>
            json == null ? null : ActiveSession.fromJson(json as Map<String, dynamic>),
      );
    } on ApiException catch (error) {
      // 일부 백엔드 구현은 "활성 세션 없음"을 success:true, data:null이
      // 아니라 SESSION_NOT_FOUND 에러로 표현한다 — 두 표현 모두 이
      // 리포지토리 계약에서는 동일하게 "없음"(null)이다.
      if (error.code == ErrorCode.sessionNotFound) return null;
      rethrow;
    }
  }

  @override
  Future<AttendanceStatus> checkIn({
    required int clubId,
    required int sessionId,
    required String otpCode,
  }) {
    return _client.post<AttendanceStatus>(
      '/clubs/$clubId/sessions/$sessionId/attendance',
      body: {'otpCode': otpCode},
      parse: (json) =>
          AttendanceStatus.fromWire((json! as Map<String, dynamic>)['status'] as String),
    );
  }
}

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return HttpAttendanceRepository(ref.watch(apiClientProvider));
});
