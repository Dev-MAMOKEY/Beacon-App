import 'package:beacon_app/core/theme/app_colors.dart';
import 'package:beacon_app/features/attendance/data/attendance_dto.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:beacon_app/features/admin/data/beacon_psk_store.dart';
import 'package:beacon_app/features/admin/data/attendance_admin_dto.dart';
import 'package:beacon_app/features/admin/data/club_member_repository.dart';
import 'package:beacon_app/features/admin/data/session_dto.dart';
import 'package:beacon_app/features/admin/data/session_repository.dart';
import 'package:beacon_app/features/admin/presentation/admin_screen.dart';
import 'package:beacon_app/features/admin/presentation/attendance_status_popup.dart';
import 'package:beacon_app/features/admin/presentation/manual_attendance_popup.dart';
import 'package:beacon_app/features/admin/presentation/admin_session_card.dart';
import 'package:beacon_app/features/auth/data/auth_dto.dart';
import 'package:beacon_app/features/auth/presentation/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _ScriptedSessionRepository implements SessionRepository {
  _ScriptedSessionRepository({List<AdminSession>? sessions, this.attendees = 0})
    : sessions = sessions ?? [];

  List<AdminSession> sessions;
  int attendees;
  bool listThrows = false;
  bool countThrows = false;

  final List<int> endedSessionIds = [];
  int listCalls = 0;
  int countCalls = 0;

  @override
  Future<SessionPage> fetchSessions({
    required int clubId,
    SessionStatus? status,
    int page = 0,
    int size = 20,
  }) async {
    listCalls++;
    if (listThrows) throw Exception('목록 조회 실패');
    return SessionPage(sessions: sessions, isLast: true);
  }

  @override
  Future<int> countAttendees({required int clubId, required int sessionId}) async {
    countCalls++;
    if (countThrows) throw Exception('집계 실패');
    return attendees;
  }

  @override
  Future<void> end({required int clubId, required int sessionId}) async {
    endedSessionIds.add(sessionId);
    sessions = sessions
        .map(
          (s) => s.sessionId == sessionId
              ? AdminSession(
                  sessionId: s.sessionId,
                  sessionName: s.sessionName,
                  status: SessionStatus.ended,
                  expectStartAt: s.expectStartAt,
                )
              : s,
        )
        .toList();
  }

  final List<SessionDraft> created = [];
  final List<(int sessionId, SessionDraft draft)> updated = [];
  final List<int> deletedSessionIds = [];
  final List<int> startedSessionIds = [];
  bool startThrows = false;

  List<AdminAttendanceRecord> attendanceRecords = [];
  final List<(int recordId, AttendanceStatus status, String? note)> statusUpdates = [];
  final List<(int memberId, AttendanceStatus status)> manualAdds = [];

  bool attendanceThrows = false;
  int attendanceCalls = 0;

  @override
  Future<List<AdminAttendanceRecord>> fetchAttendance({
    required int clubId,
    required int sessionId,
  }) async {
    attendanceCalls++;
    if (attendanceThrows) throw Exception('조회 실패');
    return attendanceRecords;
  }

  @override
  Future<void> updateAttendanceStatus({
    required int clubId,
    required int sessionId,
    required int recordId,
    required AttendanceStatus status,
    String? adminNote,
  }) async {
    statusUpdates.add((recordId, status, adminNote));
    attendanceRecords = attendanceRecords
        .map(
          (r) => r.recordId == recordId
              ? AdminAttendanceRecord(
                  recordId: r.recordId,
                  memberId: r.memberId,
                  memberName: r.memberName,
                  stdId: r.stdId,
                  attendanceStatus: status,
                  checkedAt: r.checkedAt,
                  isManual: true,
                  adminNote: adminNote,
                )
              : r,
        )
        .toList();
  }

  @override
  Future<void> addManualAttendance({
    required int clubId,
    required int sessionId,
    required int memberId,
    required AttendanceStatus status,
    String? adminNote,
  }) async {
    manualAdds.add((memberId, status));
  }

  @override
  Future<void> create({required int clubId, required SessionDraft draft}) async {
    created.add(draft);
  }

  @override
  Future<void> update({
    required int clubId,
    required int sessionId,
    required SessionDraft draft,
  }) async {
    updated.add((sessionId, draft));
  }

  @override
  Future<void> delete({required int clubId, required int sessionId}) async {
    deletedSessionIds.add(sessionId);
    sessions = sessions.where((s) => s.sessionId != sessionId).toList();
  }

  @override
  Future<SessionStartResult> start({required int clubId, required int sessionId}) async {
    startedSessionIds.add(sessionId);
    if (startThrows) throw Exception('시작 실패');
    sessions = sessions
        .map(
          (s) => s.sessionId == sessionId
              ? AdminSession(
                  sessionId: s.sessionId,
                  sessionName: s.sessionName,
                  status: SessionStatus.active,
                  expectStartAt: s.expectStartAt,
                )
              : s,
        )
        .toList();
    return const SessionStartResult(otpCode: '7329', uuid: 'u');
  }
}

class _FakePskStore implements BeaconPskStore {
  _FakePskStore([this.stored]);

  String? stored;
  final List<String> saved = [];

  @override
  Future<String?> read() async => stored;

  @override
  Future<void> save(String psk) async {
    saved.add(psk);
    stored = psk;
  }

  @override
  Future<void> clear() async => stored = null;
}

class _StubMemberRepository implements ClubMemberRepository {
  _StubMemberRepository(this.count);

  final int count;

  @override
  Future<List<ClubMember>> fetchMembers(int clubId) async => List.generate(
    count,
    // 이름과 학번을 **서로 다른 모양**으로 만든다 — 둘 다 '$i'면 어느 쪽을
    // 찾았는지 테스트가 구별하지 못한다.
    (i) => ClubMember(memberId: i, name: '부원$i', stdId: '2025000$i', role: ClubRole.member),
  );
}

class _ReadySessionController extends SessionController {
  @override
  Future<SessionState> build() async => const SessionReady(
    MemberProfile(name: '김민준', stdId: '20250101', clubIds: [7], pushEnabled: true),
  );
}

AdminSession _session({
  required int id,
  required SessionStatus status,
  String? name,
  DateTime? expectStartAt,
}) => AdminSession(
  sessionId: id,
  sessionName: name ?? '세션#000$id',
  status: status,
  expectStartAt: expectStartAt ?? DateTime.utc(2026, 4, 7, 9),
);

Future<void> _pumpAdmin(
  WidgetTester tester, {
  required _ScriptedSessionRepository repository,
  int memberCount = 15,
  _FakePskStore? pskStore,
}) async {
  final container = ProviderContainer(
    overrides: [
      sessionControllerProvider.overrideWith(_ReadySessionController.new),
      sessionRepositoryProvider.overrideWithValue(repository),
      clubMemberRepositoryProvider.overrideWithValue(_StubMemberRepository(memberCount)),
      // 기본값은 **이미 저장된 유효한 PSK** — 대부분의 테스트는 PSK 흐름을
      // 보려는 게 아니다. 없는 경우는 그 테스트가 직접 빈 저장소를 준다.
      beaconPskStoreProvider.overrideWithValue(
        pskStore ?? _FakePskStore('000102030405060708090a0b0c0d0e0f'),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildAppTheme(), home: const AdminScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('세션 시각 표기', () {
    test('KST 오후 6시로 읽는다', () {
      // 잡아야 할 잘못된 구현: 기기 시계를 그대로 쓴다. UTC 09:00은 KST
      // 18:00이다 — #43이 홈 화면에서 고친 것과 같은 결함이다.
      expect(
        formatSessionMoment(DateTime.utc(2026, 4, 7, 9)),
        '2026. 04. 07. 오후 6시',
      );
    });

    test('정오와 자정을 12시로 읽는다', () {
      // 잡아야 할 잘못된 구현: `hour % 12`만 쓴다 — 정오와 자정이 모두 0시가 된다.
      expect(formatSessionMoment(DateTime.utc(2026, 4, 7, 3)), '2026. 04. 07. 오후 12시');
      expect(formatSessionMoment(DateTime.utc(2026, 4, 6, 15)), '2026. 04. 07. 오전 12시');
    });

    test('분이 있으면 함께 적는다', () {
      expect(
        formatSessionMoment(DateTime.utc(2026, 4, 7, 9, 30)),
        '2026. 04. 07. 오후 6시 30분',
      );
    });
  });

  testWidgets('진행 중 세션은 흰 카드로, 종료된 세션은 회색 카드로 그린다', (tester) async {
    // 잡아야 할 잘못된 구현: 상태와 무관하게 같은 카드를 쓴다 — 관리자가
    // 끝난 세션에서 "출석 종료하기"를 누르게 된다.
    final repo = _ScriptedSessionRepository(
      sessions: [
        _session(id: 4, status: SessionStatus.active),
        _session(id: 3, status: SessionStatus.ended),
      ],
    );
    await _pumpAdmin(tester, repository: repo);

    expect(find.byType(ActiveSessionCard), findsOneWidget);
    expect(find.byType(EndedSessionCard), findsOneWidget);
    expect(find.text('진행 중'), findsOneWidget);
    expect(find.text('종료'), findsOneWidget);
    expect(find.text('출석 종료하기'), findsOneWidget, reason: '진행 중 카드에만 있다');
  });

  testWidgets('출석 인원은 진행 중 세션에 대해서만 센다', (tester) async {
    // #14 판정: 카드마다 세면 목록 하나에 요청이 N번 나간다. 서버가 개수를
    // 주는 엔드포인트를 두지 않아 진행 중 하나로 제한했다.
    final repo = _ScriptedSessionRepository(
      sessions: [
        _session(id: 4, status: SessionStatus.active),
        _session(id: 3, status: SessionStatus.ended),
        _session(id: 2, status: SessionStatus.ended),
      ],
      attendees: 14,
    );
    await _pumpAdmin(tester, repository: repo, memberCount: 15);

    expect(repo.countCalls, 1, reason: '종료된 카드까지 세면 요청이 N번 나간다');
    expect(find.text('14/15'), findsOneWidget);
  });

  testWidgets('진행 중 세션이 없으면 인원을 세지 않는다', (tester) async {
    final repo = _ScriptedSessionRepository(
      sessions: [_session(id: 3, status: SessionStatus.ended)],
    );
    await _pumpAdmin(tester, repository: repo);

    expect(repo.countCalls, 0);
    expect(find.byType(ActiveSessionCard), findsNothing);
  });

  testWidgets('인원 집계가 실패하면 0이 아니라 대시로 보여준다', (tester) async {
    // 잡아야 할 잘못된 구현: 실패를 0으로 접는다 — 14명이 출석한 세션이
    // "아무도 안 왔다"로 보인다.
    final repo = _ScriptedSessionRepository(
      sessions: [_session(id: 4, status: SessionStatus.active)],
    )..countThrows = true;
    await _pumpAdmin(tester, repository: repo, memberCount: 15);

    expect(find.text('-/15'), findsOneWidget);
    expect(find.text('0/15'), findsNothing);
  });

  testWidgets('시작하지 않은 화면에서는 출석코드 자리를 대시로 둔다', (tester) async {
    // 세션 시작은 한 번뿐이라 화면을 다시 열면 서버가 코드를 다시 주지
    // 않는다 — 없는 코드를 지어내거나 빈칸으로 두지 않는다.
    final repo = _ScriptedSessionRepository(
      sessions: [_session(id: 4, status: SessionStatus.active)],
    );
    await _pumpAdmin(tester, repository: repo);

    expect(find.text('----'), findsOneWidget);
  });

  testWidgets('종료를 누르면 그 세션만 종료하고 목록을 다시 읽는다', (tester) async {
    final repo = _ScriptedSessionRepository(
      sessions: [
        _session(id: 4, status: SessionStatus.active),
        _session(id: 3, status: SessionStatus.ended),
      ],
    );
    await _pumpAdmin(tester, repository: repo);
    final callsBefore = repo.listCalls;

    await tester.tap(find.text('출석 종료하기'));
    await tester.pumpAndSettle();

    expect(repo.endedSessionIds, [4], reason: '누른 세션만 종료한다');
    expect(repo.listCalls, greaterThan(callsBefore), reason: '종료 뒤 목록을 다시 읽는다');
    expect(find.byType(ActiveSessionCard), findsNothing);
  });

  testWidgets('목록 조회가 실패하면 옛 목록을 남기지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: 실패 시 아무것도 하지 않는다 — 이미 끝난
    // 세션에 "출석 종료하기"가 계속 떠 있다.
    final repo = _ScriptedSessionRepository(
      sessions: [_session(id: 4, status: SessionStatus.active)],
    );
    await _pumpAdmin(tester, repository: repo);
    expect(find.byType(ActiveSessionCard), findsOneWidget);

    repo.listThrows = true;
    await tester.tap(find.text('출석 종료하기'));
    await tester.pumpAndSettle();

    expect(find.byType(ActiveSessionCard), findsNothing);
    expect(find.text('세션을 불러오지 못했습니다'), findsOneWidget);
  });

  testWidgets('예정 세션에는 시작 버튼이 있고, 시작하면 출석 코드가 보인다', (tester) async {
    // Figma에 예정 세션 카드가 없어(진행 중·종료 두 종류뿐) 종료 카드 모양에
    // 시작 버튼만 얹었다 — 시작 경로가 없으면 세션을 만들어도 쓸 수 없다.
    final repo = _ScriptedSessionRepository(
      sessions: [_session(id: 5, status: SessionStatus.scheduled)],
    );
    await _pumpAdmin(tester, repository: repo);

    expect(find.text('예정'), findsOneWidget);
    await tester.tap(find.text('출석 시작하기'));
    await tester.pumpAndSettle();

    expect(repo.startedSessionIds, [5]);
    expect(find.byType(ActiveSessionCard), findsOneWidget);
    expect(find.text('7329'), findsOneWidget, reason: '시작 응답의 코드를 그대로 보여준다');
  });

  testWidgets('PSK가 없으면 시작 전에 물어보고, 저장한 뒤 시작한다', (tester) async {
    // PSK는 서버가 주지 않는다 — 펌웨어에 구워진 값과 같아야 GATT 명령이
    // 받아들여진다. 관리자 설정 화면(#18)이 웹 전용이라 갈 곳이 없어
    // **실제로 쓰이는 순간**인 여기서 받는다.
    final repo = _ScriptedSessionRepository(
      sessions: [_session(id: 5, status: SessionStatus.scheduled)],
    );
    final psk = _FakePskStore();
    await _pumpAdmin(tester, repository: repo, pskStore: psk);

    await tester.tap(find.text('출석 시작하기'));
    await tester.pumpAndSettle();

    expect(find.text('비콘 키 입력'), findsOneWidget);
    expect(repo.startedSessionIds, isEmpty, reason: 'PSK를 받기 전에는 시작하지 않는다');

    await tester.enterText(find.byType(TextField), '000102030405060708090a0b0c0d0e0f');
    await tester.tap(find.text('저장하고 시작'));
    await tester.pumpAndSettle();

    expect(psk.saved, ['000102030405060708090a0b0c0d0e0f']);
    expect(repo.startedSessionIds, [5], reason: '저장한 뒤에 시작한다');
  });

  testWidgets('PSK 형식이 틀리면 저장도 시작도 하지 않는다', (tester) async {
    // 형식이 틀린 PSK는 **증상이 늦게 나타난다** — 저장되고, 세션도
    // 시작되고, 비콘만 광고를 시작하지 않는다.
    final repo = _ScriptedSessionRepository(
      sessions: [_session(id: 5, status: SessionStatus.scheduled)],
    );
    final psk = _FakePskStore();
    await _pumpAdmin(tester, repository: repo, pskStore: psk);

    await tester.tap(find.text('출석 시작하기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.tap(find.text('저장하고 시작'));
    await tester.pumpAndSettle();

    expect(psk.saved, isEmpty);
    expect(repo.startedSessionIds, isEmpty);
    expect(find.text('32자 16진수를 입력해주세요 (0-9, a-f)'), findsOneWidget);
    expect(find.text('비콘 키 입력'), findsOneWidget, reason: '고칠 수 있게 팝업이 남는다');
  });

  testWidgets('PSK가 이미 있으면 묻지 않고 곧장 시작한다', (tester) async {
    // 잡아야 할 잘못된 구현: 매번 묻는다 — 세션을 시작할 때마다 32자를
    // 다시 치게 된다.
    final repo = _ScriptedSessionRepository(
      sessions: [_session(id: 5, status: SessionStatus.scheduled)],
    );
    final psk = _FakePskStore('000102030405060708090a0b0c0d0e0f');
    await _pumpAdmin(tester, repository: repo, pskStore: psk);

    await tester.tap(find.text('출석 시작하기'));
    await tester.pumpAndSettle();

    expect(find.text('비콘 키 입력'), findsNothing);
    expect(repo.startedSessionIds, [5]);
  });

  testWidgets('저장된 PSK가 형식에 안 맞으면 다시 묻는다', (tester) async {
    // 비콘 기기를 교체하면 저장값이 틀리게 된다 — 바꿀 경로가 없으면
    // 관리자가 영영 시작하지 못한다. 채워 둔 값에서 고칠 수 있어야 한다.
    final repo = _ScriptedSessionRepository(
      sessions: [_session(id: 5, status: SessionStatus.scheduled)],
    );
    final psk = _FakePskStore('짧은키');
    await _pumpAdmin(tester, repository: repo, pskStore: psk);

    await tester.tap(find.text('출석 시작하기'));
    await tester.pumpAndSettle();

    expect(find.text('비콘 키 입력'), findsOneWidget);
  });

  group('출석 현황', () {
    AdminAttendanceRecord record({
      required int id,
      required String name,
      required AttendanceStatus status,
      DateTime? checkedAt,
      bool isManual = false,
    }) => AdminAttendanceRecord(
      recordId: id,
      memberId: id,
      memberName: name,
      stdId: '2025000$id',
      attendanceStatus: status,
      checkedAt: checkedAt,
      isManual: isManual,
    );

    testWidgets('카드를 눌러 출석 현황을 열면 요약과 목록이 보인다', (tester) async {
      // 웹은 7열 표(`356:1800`)인데 390px에 안 들어간다 — 정보를 버리지 않고
      // 재배치했는지 확인한다.
      final repo = _ScriptedSessionRepository(
        sessions: [_session(id: 4, status: SessionStatus.active)],
      )..attendanceRecords = [
        record(
          id: 1,
          name: '강네모',
          status: AttendanceStatus.present,
          checkedAt: DateTime.utc(2026, 4, 7, 9, 20),
        ),
        record(id: 2, name: '박신한', status: AttendanceStatus.late, checkedAt: DateTime.utc(2026, 4, 7, 9, 25)),
        record(id: 3, name: '정세모', status: AttendanceStatus.absent, isManual: true),
      ];
      await _pumpAdmin(tester, repository: repo);

      await tester.tap(find.byType(ActiveSessionCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('출석 현황'));
      await tester.pumpAndSettle();

      expect(find.text('강네모'), findsOneWidget);
      expect(find.text('20250001'), findsOneWidget, reason: '학번 열도 살아 있다');
      expect(find.text('6:20'), findsOneWidget, reason: '체크인 시각은 KST로 읽는다');
      expect(find.text('6:25'), findsOneWidget);
      expect(find.text('-'), findsOneWidget, reason: '결석은 체크인이 없다');
      expect(find.text('수동'), findsOneWidget, reason: '자동은 표시하지 않는다');
    });

    testWidgets('요약 네 칸이 각 상태 수를 따로 센다', (tester) async {
      // 잡아야 할 잘못된 구현: 상태 매핑이 뒤바뀐다. **네 수를 전부 다르게**
      // 만들어야 구별된다 — 같은 수가 섞이면 뒤바뀌어도 통과한다.
      final repo = _ScriptedSessionRepository(
        sessions: [_session(id: 4, status: SessionStatus.active)],
      )..attendanceRecords = [
        for (var i = 0; i < 5; i++)
          record(id: i, name: 'p$i', status: AttendanceStatus.present),
        record(id: 10, name: 'l', status: AttendanceStatus.late),
        for (var i = 0; i < 2; i++)
          record(id: 20 + i, name: 'a$i', status: AttendanceStatus.absent),
        for (var i = 0; i < 3; i++)
          record(id: 30 + i, name: 'e$i', status: AttendanceStatus.etc),
      ];
      await _pumpAdmin(tester, repository: repo);

      await tester.tap(find.byType(ActiveSessionCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('출석 현황'));
      await tester.pumpAndSettle();

      expect(find.text('5'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('행을 눌러 상태를 바꾸면 서버로 보내고 목록이 갱신된다', (tester) async {
      final repo = _ScriptedSessionRepository(
        sessions: [_session(id: 4, status: SessionStatus.active)],
      )..attendanceRecords = [
        record(id: 1, name: '강네모', status: AttendanceStatus.absent),
      ];
      await _pumpAdmin(tester, repository: repo);

      await tester.tap(find.byType(ActiveSessionCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('출석 현황'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('강네모'));
      await tester.pumpAndSettle();
      expect(find.text('20250001'), findsWidgets, reason: '누구를 바꾸는지 보여준다');

      // 시트 뒤의 요약 라벨과 팝업의 선택지가 같은 문구다 — 어느 쪽을
      // 눌렀는지 분명히 하려면 팝업 안으로 한정해야 한다.
      await tester.tap(
        find.descendant(
          of: find.byType(AttendanceStatusPopupContent),
          matching: find.text('지각'),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('변경하기'));
      await tester.pumpAndSettle();

      expect(repo.statusUpdates, hasLength(1));
      expect(repo.statusUpdates.single.$1, 1);
      expect(repo.statusUpdates.single.$2, AttendanceStatus.late);
    });

    testWidgets('ACTIVE 세션은 주기적으로 목록을 다시 읽는다', (tester) async {
      // 명세서가 MVP는 SSE가 아니라 폴링 우선으로 규정한다(#16).
      //
      // **간격을 상수로 pump하지 않는다** — `pump(attendanceRefreshInterval)`
      // 로 검사하면 상수를 1시간으로 바꿔도 통과한다(#63에서 실제로 그
      // 함정을 밟았다). 리터럴 시간으로 앞뒤를 조인다.
      final repo = _ScriptedSessionRepository(
        sessions: [_session(id: 4, status: SessionStatus.active)],
      )..attendanceRecords = [
        record(id: 1, name: '강네모', status: AttendanceStatus.present),
      ];
      await _pumpAdmin(tester, repository: repo);

      await tester.tap(find.byType(ActiveSessionCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('출석 현황'));
      await tester.pumpAndSettle();
      final initial = repo.attendanceCalls;

      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(repo.attendanceCalls, initial, reason: '10초 만에 다시 읽으면 너무 잦다');

      await tester.pump(const Duration(seconds: 25));
      await tester.pumpAndSettle();
      expect(
        repo.attendanceCalls,
        greaterThan(initial),
        reason: '35초 안에 따라잡지 못하면 폴링의 의미가 없다',
      );
    });

    testWidgets('끝난 세션은 폴링하지 않는다', (tester) async {
      // 잡아야 할 잘못된 구현: 상태와 무관하게 폴링한다 — 끝난 세션의 기록은
      // 더 바뀌지 않으므로 그대로 낭비다.
      final repo = _ScriptedSessionRepository(
        sessions: [_session(id: 3, status: SessionStatus.ended)],
      );
      await _pumpAdmin(tester, repository: repo);

      await tester.tap(find.byType(EndedSessionCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('출석 현황'));
      await tester.pumpAndSettle();
      final initial = repo.attendanceCalls;

      await tester.pump(const Duration(seconds: 90));
      await tester.pumpAndSettle();

      expect(repo.attendanceCalls, initial);
    });

    testWidgets('폴링 중 일시적 실패로 보고 있던 목록을 지우지 않는다', (tester) async {
      // 잡아야 할 잘못된 구현: 폴링 실패도 화면을 실패 상태로 되돌린다 —
      // 관리자가 읽고 있던 목록이 사라지고 다음 주기에 다시 나타난다.
      final repo = _ScriptedSessionRepository(
        sessions: [_session(id: 4, status: SessionStatus.active)],
      )..attendanceRecords = [
        record(id: 1, name: '강네모', status: AttendanceStatus.present),
      ];
      await _pumpAdmin(tester, repository: repo);

      await tester.tap(find.byType(ActiveSessionCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('출석 현황'));
      await tester.pumpAndSettle();
      expect(find.text('강네모'), findsOneWidget);

      repo.attendanceThrows = true;
      await tester.pump(const Duration(seconds: 35));
      await tester.pumpAndSettle();

      expect(find.text('강네모'), findsOneWidget, reason: '보고 있던 목록이 사라지면 안 된다');
      expect(find.text('출석 현황을 불러오지 못했습니다'), findsNothing);
    });

    testWidgets('수동 출석은 기록이 없는 부원만 후보로 준다', (tester) async {
      // 잡아야 할 잘못된 구현: 전체 부원을 후보로 준다 — 이미 기록이 있는
      // 사람을 또 넣으면 서버가 중복으로 거절하거나 기존 기록을 덮어쓴다.
      // 그건 상태 변경으로 해야 할 일이다.
      final repo = _ScriptedSessionRepository(
        sessions: [_session(id: 4, status: SessionStatus.active)],
      )..attendanceRecords = [
        record(id: 1, name: '부원1', status: AttendanceStatus.present),
      ];
      await _pumpAdmin(tester, repository: repo, memberCount: 3);

      await tester.tap(find.byType(ActiveSessionCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('출석 현황'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('수동 출석'));
      await tester.pumpAndSettle();

      // 더블의 멤버는 memberId 0,1,2 — 기록이 있는 1번이 빠져야 한다.
      //
      // **팝업 안으로 한정해야 한다** — 시트의 출석 행에도 같은 이름이
      // 보이므로, 화면 전체에서 찾으면 후보에서 빠졌는지 알 수 없다.
      Finder inPopup(String text) => find.descendant(
        of: find.byType(ManualAttendancePopupContent),
        matching: find.text(text),
      );

      expect(inPopup('부원0'), findsOneWidget);
      expect(inPopup('부원2'), findsOneWidget);
      expect(inPopup('부원1'), findsNothing, reason: '이미 기록이 있는 부원은 후보에서 빠진다');
    });

    testWidgets('수동 출석을 등록하면 서버로 memberId와 상태를 보낸다', (tester) async {
      final repo = _ScriptedSessionRepository(
        sessions: [_session(id: 4, status: SessionStatus.active)],
      );
      await _pumpAdmin(tester, repository: repo, memberCount: 2);

      await tester.tap(find.byType(ActiveSessionCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('출석 현황'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('수동 출석'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('부원1'));
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(ManualAttendancePopupContent),
          matching: find.text('지각'),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('등록하기'));
      await tester.pumpAndSettle();

      expect(repo.manualAdds, [(1, AttendanceStatus.late)]);
    });

    testWidgets('부원을 고르지 않으면 등록하지 않는다', (tester) async {
      final repo = _ScriptedSessionRepository(
        sessions: [_session(id: 4, status: SessionStatus.active)],
      );
      await _pumpAdmin(tester, repository: repo, memberCount: 2);

      await tester.tap(find.byType(ActiveSessionCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('출석 현황'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('수동 출석'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('등록하기'));
      await tester.pumpAndSettle();

      expect(repo.manualAdds, isEmpty);
      expect(find.text('부원을 선택해주세요'), findsOneWidget);
    });

    testWidgets('조회가 실패하면 빈 목록이 아니라 실패를 알린다', (tester) async {
      // 잡아야 할 잘못된 구현: 실패를 빈 목록으로 접는다 — 관리자가
      // "아무도 출석하지 않았다"로 읽는다.
      final repo = _ScriptedSessionRepository(
        sessions: [_session(id: 4, status: SessionStatus.active)],
      )..attendanceThrows = true;
      await _pumpAdmin(tester, repository: repo);

      await tester.tap(find.byType(ActiveSessionCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('출석 현황'));
      await tester.pumpAndSettle();

      expect(find.text('출석 현황을 불러오지 못했습니다'), findsOneWidget);
      expect(find.text('아직 출석 기록이 없습니다'), findsNothing);
    });
  });

  testWidgets('시작 버튼은 예정 세션에만 붙는다', (tester) async {
    // 잡아야 할 잘못된 구현: 상태와 무관하게 시작 버튼을 단다.
    // - 진행 중 세션을 다시 시작하면 서버가 새 코드를 발급해 부원이 든
    //   코드가 죽는다.
    // - **끝난 세션에도 붙는다** — 진행 중 카드만 확인하면 이 쪽을 놓친다
    //   (실제로 처음엔 놓쳤다).
    final repo = _ScriptedSessionRepository(
      sessions: [
        _session(id: 4, status: SessionStatus.active),
        _session(id: 3, status: SessionStatus.ended),
        _session(id: 5, status: SessionStatus.scheduled),
      ],
    );
    await _pumpAdmin(tester, repository: repo);

    expect(
      find.text('출석 시작하기'),
      findsOneWidget,
      reason: '예정 세션 하나에만 있어야 한다 — 진행 중·종료에는 없다',
    );
  });

  testWidgets('FAB로 세션을 만들면 이름과 두 시각을 함께 보낸다', (tester) async {
    // 서버 `SessionCreateRequestDto`의 required는 sessionName·expectStartAt·
    // **expectEndAt** 셋이다 — 이슈는 "이름, 예정 시간만"이라고 적었지만
    // 종료 예정 시각 없이는 생성이 되지 않는다.
    final repo = _ScriptedSessionRepository(sessions: []);
    await _pumpAdmin(tester, repository: repo);

    await tester.tap(find.byKey(const ValueKey('admin_create_session')));
    await tester.pumpAndSettle();
    expect(find.text('세션 만들기'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '정기모임');
    await tester.tap(find.text('만들기'));
    await tester.pumpAndSettle();

    expect(repo.created, hasLength(1));
    final draft = repo.created.single;
    expect(draft.sessionName, '정기모임');
    expect(draft.expectEndAt.isAfter(draft.expectStartAt), isTrue);
  });

  testWidgets('이름이 비면 요청을 보내지 않고 팝업 안에 메시지를 남긴다', (tester) async {
    // 메시지가 토스트면 팝업 스크림 아래로 가려진다(#42) — 팝업 안에 적어야
    // 한다.
    final repo = _ScriptedSessionRepository(sessions: []);
    await _pumpAdmin(tester, repository: repo);

    await tester.tap(find.byKey(const ValueKey('admin_create_session')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('만들기'));
    await tester.pumpAndSettle();

    expect(repo.created, isEmpty);
    expect(find.text('세션 이름을 입력해주세요'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('카드를 누르면 수정·삭제를 고를 수 있고 삭제는 확인을 받는다', (tester) async {
    // 잡아야 할 잘못된 구현: 확인 없이 곧장 지운다 — 되돌릴 방법이 없다.
    final repo = _ScriptedSessionRepository(
      sessions: [_session(id: 3, status: SessionStatus.ended)],
    );
    await _pumpAdmin(tester, repository: repo);

    await tester.tap(find.byType(EndedSessionCard));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제하기'));
    await tester.pumpAndSettle();

    expect(repo.deletedSessionIds, isEmpty, reason: '확인 전에는 지우지 않는다');
    expect(find.text('세션 삭제'), findsOneWidget);

    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    expect(repo.deletedSessionIds, [3]);
    expect(find.byType(EndedSessionCard), findsNothing);
  });

  testWidgets('진행 중 배지와 종료 버튼이 실측 색을 쓴다', (tester) async {
    // 잡아야 할 잘못된 구현: 배지 글자를 `main`으로, 종료 버튼을 `gray3`로
    // 칠한다. 실측(`353:2420`/`353:2418`)은 `#005BBF`와 `#FF5D5D`다.
    final repo = _ScriptedSessionRepository(
      sessions: [_session(id: 4, status: SessionStatus.active)],
    );
    await _pumpAdmin(tester, repository: repo);

    final badge = tester.widget<Text>(find.text('진행 중'));
    expect(badge.style!.color, AppColors.light.sessionActiveBadge);

    final endLabel = tester.widget<Text>(find.text('출석 종료하기'));
    expect(endLabel.style!.color, AppColors.light.white);
  });
}
