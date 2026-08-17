import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/dio_provider.dart';
import 'session_dto.dart';

/// 관리자 화면이 쓰는 세션 API.
///
/// 부원용 `AttendanceRepository`와 나눠 둔 이유: 부원은 `sessions/active`
/// 하나만 쓰고 나머지는 전부 ADMIN 권한이다. 한 리포지토리에 섞으면 부원
/// 화면의 테스트 더블이 쓰지도 않는 관리자 메서드를 전부 구현해야 한다.
abstract interface class SessionRepository {
  /// 세션 목록. 서버가 `Slice`(총 개수 없음)를 돌려주므로 다음 페이지가
  /// 있는지는 `last`로만 알 수 있다.
  Future<SessionPage> fetchSessions({
    required int clubId,
    SessionStatus? status,
    int page = 0,
    int size = 20,
  });

  Future<void> create({required int clubId, required SessionDraft draft});

  Future<void> update({
    required int clubId,
    required int sessionId,
    required SessionDraft draft,
  });

  Future<void> delete({required int clubId, required int sessionId});

  /// 세션을 시작하고 출석 코드·비콘 UUID를 받는다.
  Future<SessionStartResult> start({required int clubId, required int sessionId});

  Future<void> end({required int clubId, required int sessionId});

  /// 그 세션에 **출석으로 기록된 인원 수**.
  ///
  /// 서버가 개수만 주는 엔드포인트를 두지 않아서 출석 목록을 받아 센다.
  /// `SliceAttendanceDto`에는 `totalElements`가 없으므로(Slice다) 마지막
  /// 페이지에 닿을 때까지 이어 받는다.
  Future<int> countAttendees({required int clubId, required int sessionId});
}

/// 한 페이지 분량의 세션과, 다음 페이지가 있는지.
class SessionPage {
  const SessionPage({required this.sessions, required this.isLast});

  final List<AdminSession> sessions;
  final bool isLast;
}

class HttpSessionRepository implements SessionRepository {
  const HttpSessionRepository(this._client);

  final ApiClient _client;

  /// 출석 인원을 셀 때 한 번에 받아오는 크기. 한 세션의 출석 기록은 동아리
  /// 인원 수를 넘지 않으므로 대부분 한 번에 끝난다.
  static const int _attendancePageSize = 100;

  @override
  Future<SessionPage> fetchSessions({
    required int clubId,
    SessionStatus? status,
    int page = 0,
    int size = 20,
  }) {
    return _client.get<SessionPage>(
      '/clubs/$clubId/sessions',
      query: {
        if (status != null) 'status': status.wire,
        'page': page,
        'size': size,
      },
      parse: (json) => _parseSessionPage(json),
    );
  }

  @override
  Future<void> create({required int clubId, required SessionDraft draft}) {
    return _client.post<void>(
      '/clubs/$clubId/sessions',
      body: draft.toJson(),
      parse: (_) {},
    );
  }

  @override
  Future<void> update({
    required int clubId,
    required int sessionId,
    required SessionDraft draft,
  }) {
    return _client.patch<void>(
      '/clubs/$clubId/sessions/$sessionId',
      body: draft.toJson(),
      parse: (_) {},
    );
  }

  @override
  Future<void> delete({required int clubId, required int sessionId}) {
    return _client.delete<void>('/clubs/$clubId/sessions/$sessionId', parse: (_) {});
  }

  @override
  Future<SessionStartResult> start({required int clubId, required int sessionId}) {
    return _client.post<SessionStartResult>(
      '/clubs/$clubId/sessions/$sessionId/start',
      parse: (json) => SessionStartResult.fromJson(json! as Map<String, dynamic>),
    );
  }

  @override
  Future<void> end({required int clubId, required int sessionId}) {
    return _client.post<void>('/clubs/$clubId/sessions/$sessionId/end', parse: (_) {});
  }

  @override
  Future<int> countAttendees({required int clubId, required int sessionId}) async {
    var total = 0;
    var page = 0;
    while (true) {
      final result = await _client.get<({int count, bool isLast})>(
        '/clubs/$clubId/sessions/$sessionId/attendance',
        query: {'page': page, 'size': _attendancePageSize},
        parse: _parseAttendanceCount,
      );
      total += result.count;
      if (result.isLast) return total;
      page++;
      // 서버가 `last`를 영영 false로 주는 경우에 무한 루프에 빠지지 않도록
      // 상한을 둔다 — 동아리 인원이 이 값을 넘을 일은 없다.
      if (page > 50) return total;
    }
  }
}

SessionPage _parseSessionPage(Object? json) {
  final map = json! as Map<String, dynamic>;
  final content = (map['content'] as List<dynamic>? ?? const [])
      .map((item) => AdminSession.fromJson(item as Map<String, dynamic>))
      .toList();
  return SessionPage(
    sessions: content,
    // `last`가 없으면 더 받으려다 같은 페이지를 반복할 수 있으므로 "마지막"
    // 으로 본다 — 멈추는 쪽이 안전한 기본값이다.
    isLast: map['last'] as bool? ?? true,
  );
}

({int count, bool isLast}) _parseAttendanceCount(Object? json) {
  final map = json! as Map<String, dynamic>;
  final content = map['content'] as List<dynamic>? ?? const [];
  return (count: content.length, isLast: map['last'] as bool? ?? true);
}

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  return HttpSessionRepository(ref.watch(apiClientProvider));
});
