import 'package:beacon_app/core/theme/app_colors.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:beacon_app/features/admin/data/beacon_psk_store.dart';
import 'package:beacon_app/features/admin/data/club_member_repository.dart';
import 'package:beacon_app/features/admin/data/session_dto.dart';
import 'package:beacon_app/features/admin/data/session_repository.dart';
import 'package:beacon_app/features/admin/presentation/admin_screen.dart';
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
    (i) => ClubMember(memberId: i, name: '$i', stdId: '$i', role: ClubRole.member),
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
