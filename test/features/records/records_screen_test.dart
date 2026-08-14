import 'dart:async';

import 'package:beacon_app/core/theme/app_colors.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:beacon_app/features/attendance/data/attendance_dto.dart';
import 'package:beacon_app/features/auth/data/auth_dto.dart';
import 'package:beacon_app/features/auth/presentation/session_controller.dart';
import 'package:beacon_app/features/records/data/records_dto.dart';
import 'package:beacon_app/features/records/data/records_repository.dart';
import 'package:beacon_app/features/records/presentation/records_calendar.dart';
import 'package:beacon_app/features/records/presentation/records_screen.dart';
import 'package:beacon_app/features/records/presentation/session_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

const _profile = MemberProfile(
  name: '김민준',
  stdId: '20250101',
  clubIds: [7],
  pushEnabled: true,
);

class _ReadySessionController extends SessionController {
  @override
  Future<SessionState> build() async => const SessionReady(_profile);
}

/// 호출 인자를 전부 기록하고, 응답 시점을 테스트가 정할 수 있는 페이크.
///
/// [gate]에 (year, month)를 넣어 두면 그 달의 조회는 [complete]를 부를
/// 때까지 끝나지 않는다 — "늦게 도착한 옛 달의 응답"을 재현하는 데 쓴다.
class _RecordingRecordsRepository implements RecordsRepository {
  _RecordingRecordsRepository({this.responses = const {}, this.gated = const {}});

  /// (year, month) → 그 달의 응답. 없으면 빈 달을 돌려준다.
  final Map<(int, int), MonthlyRecords> responses;

  /// 응답을 붙잡아 둘 (year, month) 집합.
  final Set<(int, int)> gated;

  final List<({int clubId, int year, int month})> calls = [];
  final Map<(int, int), Completer<void>> _gates = {};

  @override
  Future<MonthlyRecords> fetch({
    required int clubId,
    required int year,
    required int month,
  }) async {
    calls.add((clubId: clubId, year: year, month: month));
    if (gated.contains((year, month))) {
      await (_gates[(year, month)] ??= Completer<void>()).future;
    }
    return responses[(year, month)] ??
        MonthlyRecords(
          year: year,
          month: month,
          records: const [],
          present: 0,
          absent: 0,
          late: 0,
          etc: 0,
          attendanceRate: 0,
        );
  }

  void release(int year, int month) {
    (_gates[(year, month)] ??= Completer<void>()).complete();
  }
}

/// 루트 내비게이터에 실제로 남아 있는 라우트를 추적한다. "시트가 안 떴다"를
/// 위젯 유무로만 확인하면, 아무 내용도 없는 라우트를 밀어 넣어 모달 배리어로
/// 화면을 막아 버리는 구현도 통과한다.
class _RouteStackObserver extends NavigatorObserver {
  final List<Route<dynamic>> stack = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => stack.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => stack.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => stack.remove(route);
}

AttendanceRecordItem _record({
  required int day,
  required AttendanceStatus status,
  int year = 2026,
  int month = 8,
  String name = '정기모임',
  DateTime? checkedAt,
}) {
  return AttendanceRecordItem(
    sessionId: year * 10000 + month * 100 + day,
    sessionName: name,
    date: DateTime(year, month, day),
    status: status,
    checkedAt: checkedAt,
  );
}

MonthlyRecords _monthly({
  required int year,
  required int month,
  List<AttendanceRecordItem> records = const [],
  int present = 0,
  int absent = 0,
  int late = 0,
  int etc = 0,
  double attendanceRate = 0,
}) {
  return MonthlyRecords(
    year: year,
    month: month,
    records: records,
    present: present,
    absent: absent,
    late: late,
    etc: etc,
    attendanceRate: attendanceRate,
  );
}

Future<({_RouteStackObserver routes, ValueNotifier<bool> visible})> _pumpRecords(
  WidgetTester tester, {
  required _RecordingRecordsRepository repository,
  required DateTime now,
  bool visible = true,
}) async {
  final container = ProviderContainer(
    overrides: [
      sessionControllerProvider.overrideWith(_ReadySessionController.new),
      recordsRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  final routes = _RouteStackObserver();
  final visibility = ValueNotifier<bool>(visible);
  addTearDown(visibility.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAppTheme(),
        navigatorObservers: [routes],
        // 실제 앱에서는 AppShell의 Scaffold 안에서 렌더된다(app_router.dart).
        // `TickerMode(enabled: false)`는 `StatefulShellRoute.indexedStack`이
        // 숨은 브랜치를 감싸는 방식 그대로다 — 그 상태를 여기서 재현한다.
        // `RecordsScreen`은 이 바깥에서 만들어 두므로 가시성이 뒤집혀도
        // **같은 State**가 유지된다(실제 셸도 브랜치를 dispose하지 않는다).
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: visibility,
            child: RecordsScreen(clock: () => now),
            builder: (context, enabled, child) =>
                TickerMode(enabled: enabled, child: child!),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (routes: routes, visible: visibility);
}

/// 달력 안에서만 찾는다 — 요약 카드의 숫자("2" 같은)와 섞이지 않게.
Finder _calendarText(String label) =>
    find.descendant(of: find.byType(RecordsCalendar), matching: find.text(label));

/// 날짜 배지가 **실제로 칠한** 색. 위젯의 프로퍼티가 아니라 렌더에 쓰이는
/// `BoxDecoration`을 읽는다.
Color? _badgeColor(WidgetTester tester, String label) {
  final container = tester.widget<Container>(
    find.ancestor(of: _calendarText(label), matching: find.byType(Container)).first,
  );
  return (container.decoration! as BoxDecoration).color;
}

/// 월 이동 화살표. `Semantics`의 라벨로 찾는다 — 두 화살표가 같은 에셋을
/// 쓰므로 위젯 타입만으로는 구분할 수 없다.
Finder _arrow(String label) =>
    find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label);

ColorFilter? _arrowColorFilter(WidgetTester tester, String label) {
  return tester
      .widget<SvgPicture>(find.descendant(of: _arrow(label), matching: find.byType(SvgPicture)))
      .colorFilter;
}

void main() {
  // ---------------------------------------------------------------------
  // 배지 색
  // ---------------------------------------------------------------------
  testWidgets('출석/지각/결석/기타가 각각 지정된 배지 색으로 렌더된다', (tester) async {
    // 잡아야 할 잘못된 구현: 상태별 색이 서로 뒤바뀐다(출석에 지각 색),
    // 또는 상태와 무관하게 한 색으로 통일한다.
    final repo = _RecordingRecordsRepository(
      responses: {
        (2026, 8): _monthly(
          year: 2026,
          month: 8,
          records: [
            _record(day: 3, status: AttendanceStatus.present),
            _record(day: 4, status: AttendanceStatus.late),
            _record(day: 5, status: AttendanceStatus.absent),
            _record(day: 6, status: AttendanceStatus.etc),
          ],
        ),
      },
    );
    await _pumpRecords(tester, repository: repo, now: DateTime(2026, 8, 15));

    const colors = AppColors.light;
    expect(_badgeColor(tester, '3'), colors.attendancePresent);
    expect(_badgeColor(tester, '4'), colors.attendanceLate);
    expect(_badgeColor(tester, '5'), colors.attendanceAbsent);
    expect(_badgeColor(tester, '6'), colors.attendanceEtc);

    // 네 색이 실제로 서로 다르다는 것도 함께 본다 — 토큰이 전부 같은 값이면
    // 위의 네 줄은 "한 색으로 통일"한 구현도 통과시킨다.
    expect(
      {
        colors.attendancePresent.toARGB32(),
        colors.attendanceLate.toARGB32(),
        colors.attendanceAbsent.toARGB32(),
        colors.attendanceEtc.toARGB32(),
      },
      hasLength(4),
    );
  });

  testWidgets('기록이 없는 날짜는 배지 없이 숫자만 렌더된다', (tester) async {
    // 잡아야 할 잘못된 구현: 모든 날짜에 배지를 칠한다(기록 없는 날에도
    // 기본 배경색을 준다).
    final repo = _RecordingRecordsRepository(
      responses: {
        (2026, 8): _monthly(
          year: 2026,
          month: 8,
          records: [_record(day: 3, status: AttendanceStatus.present)],
        ),
      },
    );
    await _pumpRecords(tester, repository: repo, now: DateTime(2026, 8, 15));

    // 숫자 자체는 그려진다.
    expect(_calendarText('7'), findsOneWidget);
    expect(_badgeColor(tester, '7'), isNull);
    // 대조군 — 기록이 있는 날은 칠해져 있다(둘 다 null이면 이 테스트는
    // 아무것도 보증하지 않는다).
    expect(_badgeColor(tester, '3'), isNotNull);
  });

  // ---------------------------------------------------------------------
  // 월 그리드 오프셋 (일요일 시작)
  // ---------------------------------------------------------------------
  //
  // 1일이 몇 번째 칸인지를 "칸 인덱스"로 확인하면 그리드를 잘못 그려도
  // (예: 월요일 시작) 통과할 수 있다 — 실제로 렌더된 x좌표가 그 요일 머리글의
  // x좌표와 같은지 본다.
  testWidgets('2026년 8월 1일은 토요일 칸에서 시작한다', (tester) async {
    // 잡아야 할 잘못된 구현: 오프셋을 아예 안 줘서 항상 첫 칸(일요일)부터
    // 시작하거나, 월요일 시작 달력을 그린다.
    final repo = _RecordingRecordsRepository();
    await _pumpRecords(tester, repository: repo, now: DateTime(2026, 8, 15));

    expect(
      tester.getCenter(_calendarText('1')).dx,
      closeTo(tester.getCenter(_calendarText('토')).dx, 0.5),
    );
    // 마지막 날도 함께 본다 — 8월 31일은 월요일이다.
    expect(
      tester.getCenter(_calendarText('31')).dx,
      closeTo(tester.getCenter(_calendarText('월')).dx, 0.5),
    );
  });

  testWidgets('2026년 11월 1일은 일요일 칸에서 시작한다', (tester) async {
    // 위 테스트만 있으면 "항상 6칸 밀기" 같은 구현도 통과한다 — 오프셋이
    // 0인 달을 함께 확인해야 그 구현이 걸린다.
    final repo = _RecordingRecordsRepository();
    await _pumpRecords(tester, repository: repo, now: DateTime(2026, 11, 15));

    expect(
      tester.getCenter(_calendarText('1')).dx,
      closeTo(tester.getCenter(_calendarText('일')).dx, 0.5),
    );
    expect(
      tester.getCenter(_calendarText('30')).dx,
      closeTo(tester.getCenter(_calendarText('월')).dx, 0.5),
    );
  });

  // ---------------------------------------------------------------------
  // 월 이동
  // ---------------------------------------------------------------------
  testWidgets('이번 달에서는 다음 달 화살표가 비활성이고 눌러도 아무 일이 없다', (tester) async {
    // 잡아야 할 잘못된 구현: 다음 달 화살표가 항상 활성이라 미래 월을
    // 조회한다.
    final repo = _RecordingRecordsRepository();
    await _pumpRecords(tester, repository: repo, now: DateTime(2026, 8, 15));

    expect(repo.calls, hasLength(1));
    expect(find.text('2026. 08'), findsOneWidget);

    const colors = AppColors.light;
    expect(
      _arrowColorFilter(tester, '다음 달'),
      ColorFilter.mode(colors.gray1, BlendMode.srcIn),
      reason: '비활성 화살표는 눈에도 비활성으로 보여야 한다',
    );
    expect(
      _arrowColorFilter(tester, '이전 달'),
      ColorFilter.mode(colors.main, BlendMode.srcIn),
      reason: '대조군 — 활성 화살표는 main이다',
    );

    await tester.tap(_arrow('다음 달'));
    await tester.pumpAndSettle();

    expect(repo.calls, hasLength(1), reason: '미래 월을 조회해서는 안 된다');
    expect(find.text('2026. 09'), findsNothing);
    expect(find.text('2026. 08'), findsOneWidget);
  });

  testWidgets('이전 달 화살표를 누르면 그 달을 정확한 인자로 조회한다', (tester) async {
    // 잡아야 할 잘못된 구현: 아예 조회하지 않고 화면만 바꾸거나, 연도 넘김을
    // 처리하지 않아 2026년 0월/2026년 12월을 조회한다. 1월에서 시작하는
    // 이유가 바로 그 연도 넘김을 강제로 태우기 위해서다.
    final repo = _RecordingRecordsRepository();
    await _pumpRecords(tester, repository: repo, now: DateTime(2026, 1, 15));

    expect(repo.calls, [(clubId: 7, year: 2026, month: 1)]);

    await tester.tap(_arrow('이전 달'));
    await tester.pumpAndSettle();

    expect(repo.calls, [
      (clubId: 7, year: 2026, month: 1),
      (clubId: 7, year: 2025, month: 12),
    ]);
    expect(find.text('2025. 12'), findsOneWidget);

    // 과거 달로 왔으니 다음 달 화살표는 다시 활성이어야 한다 — 그러지
    // 않으면 "항상 비활성"인 구현이 위 테스트를 통과해 버린다.
    await tester.tap(_arrow('다음 달'));
    await tester.pumpAndSettle();

    expect(repo.calls.last, (clubId: 7, year: 2026, month: 1));
    expect(find.text('2026. 01'), findsOneWidget);
  });

  testWidgets('월을 빠르게 넘겼을 때 늦게 도착한 옛 달의 응답이 화면을 덮지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: 세대 검사 없이 `setState(() => _records = ...)`.
    // 12월 조회가 느리게 끝나 11월 응답보다 **뒤에** 도착하면, 화면은 11월을
    // 가리키는데 내용은 12월 것이 된다.
    //
    // 두 달의 요약값을 41/42로 잡은 이유: 날짜 칸에 나올 수 있는 숫자(1~31)와
    // 겹치지 않아야 "요약 카드에 어느 달 값이 들어갔는가"만 정확히 가려낼 수
    // 있다. 처음엔 11/12를 썼는데 달력의 11일·12일 칸과 충돌해 테스트가
    // 엉뚱한 이유로 실패했다.
    final repo = _RecordingRecordsRepository(
      gated: {(2025, 12), (2025, 11)},
      responses: {
        (2025, 12): _monthly(year: 2025, month: 12, late: 42, attendanceRate: 42),
        (2025, 11): _monthly(year: 2025, month: 11, late: 41, attendanceRate: 41),
      },
    );
    await _pumpRecords(tester, repository: repo, now: DateTime(2026, 1, 15));

    await tester.tap(_arrow('이전 달'));
    await tester.pump();
    await tester.tap(_arrow('이전 달'));
    await tester.pump();

    expect(find.text('2025. 11'), findsOneWidget);
    expect(repo.calls, hasLength(3));

    // 11월(현재 화면)이 먼저 도착하고...
    repo.release(2025, 11);
    await tester.pumpAndSettle();
    expect(find.text('41'), findsWidgets);

    // ...12월(이미 지나간 달)이 **나중에** 도착한다.
    repo.release(2025, 12);
    await tester.pumpAndSettle();

    expect(find.text('2025. 11'), findsOneWidget);
    expect(
      find.text('41'),
      findsWidgets,
      reason: '11월 요약이 그대로 남아 있어야 한다',
    );
    expect(
      find.text('42'),
      findsNothing,
      reason: '늦게 온 12월 응답(지각 42회·출석률 42%)이 11월 화면을 덮어서는 안 된다',
    );
  });

  // ---------------------------------------------------------------------
  // 탭 가시성
  // ---------------------------------------------------------------------
  testWidgets('숨어 있는 동안에는 조회하지 않고, 보이는 순간 조회한다', (tester) async {
    // 잡아야 할 잘못된 구현: `initState`/`build`에서 가시성과 무관하게 곧장
    // 조회한다. `StatefulShellRoute.indexedStack`은 숨은 브랜치를 dispose하지
    // 않고 `TickerMode(enabled: false)`로 감싼 채 계속 build하므로, 이 가드가
    // 없으면 보이지도 않는 화면이 네트워크를 두드린다.
    final repo = _RecordingRecordsRepository();
    final (routes: _, :visible) = await _pumpRecords(
      tester,
      repository: repo,
      now: DateTime(2026, 8, 15),
      visible: false,
    );

    expect(repo.calls, isEmpty);

    // 브랜치가 선택되는 순간을 재현한다 — 화면은 다시 만들어지지 않고
    // `TickerMode`의 값만 뒤집힌다.
    visible.value = true;
    await tester.pumpAndSettle();

    expect(repo.calls, [(clubId: 7, year: 2026, month: 8)]);
  });

  testWidgets('숨겨지면 열려 있던 날짜 상세 시트를 닫는다', (tester) async {
    // 잡아야 할 잘못된 구현: 시트를 `showModalBottomSheet`로만 띄우고
    // 라우트를 소유하지 않는다 — 탭 전환은 dispose를 부르지 않으므로 시트가
    // 다음 탭 위에 그대로 남아 앱을 막는다.
    final repo = _RecordingRecordsRepository(
      responses: {
        (2026, 8): _monthly(
          year: 2026,
          month: 8,
          records: [_record(day: 3, status: AttendanceStatus.present)],
        ),
      },
    );
    final (:routes, :visible) = await _pumpRecords(
      tester,
      repository: repo,
      now: DateTime(2026, 8, 15),
    );

    await tester.tap(_calendarText('3'));
    await tester.pumpAndSettle();
    expect(find.byType(SessionDetailSheetContent), findsOneWidget);
    expect(routes.stack, hasLength(2));

    visible.value = false;
    await tester.pumpAndSettle();

    expect(find.byType(SessionDetailSheetContent), findsNothing);
    expect(routes.stack, hasLength(1), reason: '보이는 내용만 사라지고 모달 배리어가 남으면 앱이 막힌다');
  });

  // ---------------------------------------------------------------------
  // 요약 카드
  // ---------------------------------------------------------------------
  testWidgets('요약 카드는 서버가 준 status 집계와 attendanceRate를 그대로 보여준다', (tester) async {
    // 잡아야 할 잘못된 구현: 클라이언트가 records[]를 세어 다시 계산한다.
    // 이 픽스처는 그 두 구현이 **다른 숫자**를 내도록 짜여 있다 —
    // records[]로 세면 출석률 67%(2/3)·지각 0회지만, 서버는 94%·지각 5회를
    // 줬다(가입 이전 세션을 분모에서 빼는 등 서버만 아는 규칙 때문이다).
    final repo = _RecordingRecordsRepository(
      responses: {
        (2026, 8): _monthly(
          year: 2026,
          month: 8,
          records: [
            _record(day: 3, status: AttendanceStatus.present),
            _record(day: 4, status: AttendanceStatus.present),
            _record(day: 5, status: AttendanceStatus.absent),
          ],
          present: 2,
          absent: 3,
          late: 5,
          attendanceRate: 94,
        ),
      },
    );
    await _pumpRecords(tester, repository: repo, now: DateTime(2026, 8, 15));

    expect(find.text('94'), findsOneWidget);
    expect(find.text('%'), findsOneWidget);
    expect(find.text('이번 달 출석률'), findsOneWidget);

    // 지각 5회 — records[]에는 LATE가 하나도 없다.
    expect(find.text('5'), findsWidgets);
    expect(find.text('이번 달 지각 횟수'), findsOneWidget);

    // 결석 3회 — records[]에는 ABSENT가 하나뿐이다.
    expect(find.text('이번 달 결석 횟수'), findsOneWidget);
    final absentCard = find.ancestor(
      of: find.text('이번 달 결석 횟수'),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: absentCard.last, matching: find.text('3')),
      findsOneWidget,
      reason: 'records[]를 세면 1이 나온다 — 서버가 준 3이어야 한다',
    );
    expect(find.text('67'), findsNothing, reason: '클라이언트가 출석률을 다시 계산한 흔적');
  });

  // ---------------------------------------------------------------------
  // 날짜 탭 → 바텀시트
  // ---------------------------------------------------------------------
  testWidgets('기록이 있는 날짜를 탭하면 그 날의 세션 상세 시트가 뜬다', (tester) async {
    // 잡아야 할 잘못된 구현: 탭에 아무 반응이 없다.
    final repo = _RecordingRecordsRepository(
      responses: {
        (2026, 8): _monthly(
          year: 2026,
          month: 8,
          records: [
            _record(
              day: 3,
              status: AttendanceStatus.late,
              name: '8월 첫 정기모임',
              checkedAt: DateTime(2026, 8, 3, 19, 7),
            ),
            _record(day: 3, status: AttendanceStatus.present, name: '뒤풀이'),
            _record(day: 4, status: AttendanceStatus.present, name: '다른 날 세션'),
          ],
        ),
      },
    );
    await _pumpRecords(tester, repository: repo, now: DateTime(2026, 8, 15));

    await tester.tap(_calendarText('3'));
    await tester.pumpAndSettle();

    expect(find.byType(SessionDetailSheetContent), findsOneWidget);
    expect(find.text('2026년 08월 03일'), findsOneWidget);
    // 하루에 여러 세션이 있으면 전부 보여준다.
    expect(find.text('8월 첫 정기모임'), findsOneWidget);
    expect(find.text('뒤풀이'), findsOneWidget);
    expect(find.text('19:07 처리'), findsOneWidget);
    // 다른 날짜의 세션이 섞여 들어오지 않는다.
    expect(find.text('다른 날 세션'), findsNothing);
  });

  testWidgets('기록이 없는 날짜를 탭하면 시트가 뜨지 않고 라우트도 쌓이지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: 기록이 없어도 시트를 열어 빈 시트가 뜬다.
    // 위젯 유무만 보면 "내용은 비었지만 라우트는 밀어 넣는" 구현이 통과하므로
    // 라우트 스택도 함께 본다.
    final repo = _RecordingRecordsRepository(
      responses: {
        (2026, 8): _monthly(
          year: 2026,
          month: 8,
          records: [_record(day: 3, status: AttendanceStatus.present)],
        ),
      },
    );
    final (:routes, visible: _) = await _pumpRecords(
      tester,
      repository: repo,
      now: DateTime(2026, 8, 15),
    );

    await tester.tap(_calendarText('7'));
    await tester.pumpAndSettle();

    expect(find.byType(SessionDetailSheetContent), findsNothing);
    expect(
      routes.stack,
      hasLength(1),
      reason: '보이는 내용만 비우고 모달 라우트를 남기면 배리어가 화면을 막는다',
    );

    // 대조군 — 같은 하네스에서 기록이 있는 날짜는 실제로 시트를 연다.
    await tester.tap(_calendarText('3'));
    await tester.pumpAndSettle();
    expect(routes.stack, hasLength(2));
  });
}
