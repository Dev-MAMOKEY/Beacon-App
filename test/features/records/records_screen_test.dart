import 'dart:async';

import 'package:beacon_app/components/ui/sheet.dart';
import 'package:beacon_app/core/theme/app_colors.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:beacon_app/core/theme/app_typography.dart';
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

/// 지금 로그인한 멤버가 속한 동아리. 테스트가 도중에 바꿔 "동아리 전환"을
/// 재현한다 — 세션 컨트롤러가 이 값을 `watch`하므로 바꾸면 새 프로필이 흐른다.
final _clubIdProvider = StateProvider<int>((ref) => 7);

class _ReadySessionController extends SessionController {
  @override
  Future<SessionState> build() async => SessionReady(
    MemberProfile(
      name: '김민준',
      stdId: '20250101',
      clubIds: [ref.watch(_clubIdProvider)],
      pushEnabled: true,
    ),
  );
}

/// 호출 인자를 전부 기록하고, 응답 시점과 성패를 테스트가 정할 수 있는 페이크.
///
/// [gated]에 (year, month)를, [gatedClubIds]에 clubId를 넣어 두면 그 조회는
/// [release]를 부를 때까지 끝나지 않는다 — "늦게 도착한 옛 달의 응답"과
/// "아직 오지 않은 새 클럽의 응답"을 재현하는 데 쓴다. [failures]에 든 달은
/// 예외로 끝난다.
class _RecordingRecordsRepository implements RecordsRepository {
  _RecordingRecordsRepository({
    this.responses = const {},
    this.gated = const {},
    this.gatedClubIds = const {},
    this.failures = const {},
  });

  /// (year, month) → 그 달의 응답. 없으면 빈 달을 돌려준다. 테스트가 도중에
  /// 값을 바꿔 "같은 달을 다시 조회하면 다른 결과가 온다"를 재현할 수 있도록
  /// 가변 맵을 넘겨도 된다.
  final Map<(int, int), MonthlyRecords> responses;

  /// 응답을 붙잡아 둘 (year, month) 집합.
  final Set<(int, int)> gated;

  /// 응답을 붙잡아 둘 clubId 집합. 클럽 전환 직후의 "아직 새 응답이 오기 전"
  /// 상태를 만들 때 쓴다.
  final Set<int> gatedClubIds;

  /// 예외로 끝낼 (year, month) 집합.
  final Set<(int, int)> failures;

  final List<({int clubId, int year, int month})> calls = [];

  /// (clubId, year, month) → 아직 풀리지 않은 조회들. 같은 달을 두 번
  /// 조회하는 시나리오가 있어 하나가 아니라 대기열이다.
  final Map<(int, int, int), List<Completer<void>>> _pending = {};

  @override
  Future<MonthlyRecords> fetch({
    required int clubId,
    required int year,
    required int month,
  }) async {
    calls.add((clubId: clubId, year: year, month: month));
    if (gated.contains((year, month)) || gatedClubIds.contains(clubId)) {
      final completer = Completer<void>();
      (_pending[(clubId, year, month)] ??= []).add(completer);
      await completer.future;
    }
    if (failures.contains((year, month))) {
      throw StateError('$year년 $month월 조회 실패');
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

  /// 그 달의 **대기 중인** 조회 하나를 풀어 준다. 대기 중인 것이 없으면
  /// 던진다 — 조용히 no-op이 되면 테스트가 재현하려던 상황이 실제로는
  /// 만들어지지 않았는데도 초록색이 된다.
  void release(int year, int month, {int clubId = 7}) {
    final queue = _pending[(clubId, year, month)];
    if (queue == null || queue.isEmpty) {
      throw StateError('clubId=$clubId $year년 $month월 조회가 대기 중이 아니다');
    }
    queue.removeAt(0).complete();
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

/// 시트 위에 하나 더 쌓아 볼 **비불투명** 루트 라우트.
///
/// 불투명 라우트(`MaterialPageRoute`)를 쓰면 `Overlay`가 그 아래 엔트리를
/// 전부 `TickerMode(enabled: false)`로 덮어 기록 화면이 "숨겨졌다"고 판단해
/// 스스로 시트를 닫아 버린다 — 그러면 정작 검사하려는 상황(시트와 다른
/// 라우트가 **함께** 살아 있는 상태)을 만들 수 없다. 이 앱의 팝업
/// (`DialogRoute`)도 비불투명이라 실제로 일어날 수 있는 배치다.
class _StackedTestRoute extends PopupRoute<void> {
  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => const Align(
    alignment: Alignment.topCenter,
    child: Material(child: Text('시트 위의 라우트')),
  );
}

/// 선언 순서대로 커지는 sessionId. 같은 시각의 세션이 여럿인 픽스처에서
/// 정렬 타이브레이크가 **선언 순서**를 그대로 보존하게 만든다 — 그래야
/// "그 날의 첫/마지막 기록을 쓴다"는 잘못된 구현을 순서로 잡아낼 수 있다.
var _nextSessionId = 1;

AttendanceRecordItem _record({
  required int day,
  required AttendanceStatus status,
  int year = 2026,
  int month = 8,
  String name = '정기모임',
  DateTime? checkedAt,
}) {
  return AttendanceRecordItem(
    sessionId: _nextSessionId++,
    sessionName: name,
    // 서버 payload와 같은 모양으로 만든다 — ISO 8601 UTC(`…Z`)다.
    date: DateTime.utc(year, month, day),
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

typedef _Harness = ({
  _RouteStackObserver routes,
  ValueNotifier<bool> visible,
  ValueNotifier<bool> attached,
  ProviderContainer container,
  GlobalKey<NavigatorState> navigator,
});

Future<_Harness> _pumpRecords(
  WidgetTester tester, {
  required _RecordingRecordsRepository repository,
  required DateTime now,
  bool visible = true,
  AppColors? colors,
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
  // false로 뒤집으면 화면이 트리에서 빠진다(=`dispose()`가 불린다). 탭 전환은
  // 브랜치를 dispose하지 않으므로 이 둘은 서로 다른 경로다.
  final attached = ValueNotifier<bool>(true);
  addTearDown(attached.dispose);
  final navigator = GlobalKey<NavigatorState>();

  final base = buildAppTheme();
  // 색 토큰 하나만 다른 테마로 pump할 수 있게 한다 — 기본 테마에서는 값이
  // 같아 서로 구별되지 않는 토큰(attendanceEtc와 gray4)을 갈라놓는 데 쓴다.
  final theme = colors == null
      ? base
      : base.copyWith(
          extensions: <ThemeExtension<dynamic>>[colors, base.extension<AppTypography>()!],
        );

  // `RecordsScreen`을 한 번만 만들어 두고 두 `ValueListenableBuilder`에
  // 넘긴다 — 가시성이 뒤집혀도 **같은 State**가 유지된다(실제 셸도 브랜치를
  // dispose하지 않는다).
  final screen = RecordsScreen(clock: () => now);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme,
        navigatorKey: navigator,
        navigatorObservers: [routes],
        // 실제 앱에서는 AppShell의 Scaffold 안에서 렌더된다(app_router.dart).
        // `TickerMode(enabled: false)`는 `StatefulShellRoute.indexedStack`이
        // 숨은 브랜치를 감싸는 방식 그대로다 — 그 상태를 여기서 재현한다.
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: attached,
            builder: (context, isAttached, _) => isAttached
                ? ValueListenableBuilder<bool>(
                    valueListenable: visibility,
                    child: screen,
                    builder: (context, enabled, child) =>
                        TickerMode(enabled: enabled, child: child!),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (
    routes: routes,
    visible: visibility,
    attached: attached,
    container: container,
    navigator: navigator,
  );
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

/// 요약 카드 하나의 값 텍스트. 카드 라벨에서 **가장 가까운** Row 조상으로
/// 스코프를 좁힌다 — `.last`(가장 바깥 Row)를 쓰면 위에 Row가 하나라도 생기는
/// 순간 스코프가 화면 전체로 조용히 넓어져 검사가 공허해진다.
Finder _summaryValue(String label, String value) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
  matching: find.text(value),
);

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
  testWidgets('같은 시각의 세션이 여럿이면 sessionId 순서로 결정론적으로 정렬된다', (tester) async {
    // 잡아야 할 잘못된 구현: 타이브레이크를 빼고 시각만으로 정렬한다.
    // Dart의 `List.sort`는 안정 정렬이 아니라 같은 시각의 세션 둘이
    // 리빌드마다 다른 순서로 뜰 수 있다. **입력 순서를 sessionId의 역순으로**
    // 넣어야 그 차이가 드러난다 — 같은 순서로 넣으면 두 구현이 같은 결과를
    // 낸다(#44에서 이 변이가 살아남았던 이유다).
    final repo = _RecordingRecordsRepository(
      responses: {
        (2026, 8): _monthly(
          year: 2026,
          month: 8,
          records: [
            AttendanceRecordItem(
              sessionId: 9,
              sessionName: '나중에 만든 세션',
              date: DateTime.utc(2026, 8, 10, 1),
              status: AttendanceStatus.present,
            ),
            AttendanceRecordItem(
              sessionId: 2,
              sessionName: '먼저 만든 세션',
              date: DateTime.utc(2026, 8, 10, 1),
              status: AttendanceStatus.present,
            ),
          ],
        ),
      },
    );
    await _pumpRecords(tester, repository: repo, now: DateTime(2026, 8, 15));

    await tester.tap(_calendarText('10'));
    await tester.pumpAndSettle();

    final first = tester.getTopLeft(find.text('먼저 만든 세션')).dy;
    final second = tester.getTopLeft(find.text('나중에 만든 세션')).dy;
    expect(
      first,
      lessThan(second),
      reason: 'sessionId가 작은 세션이 위에 와야 리빌드마다 순서가 바뀌지 않는다',
    );
  });

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

  testWidgets('기타 배지는 gray4가 아니라 attendanceEtc 토큰을 따라간다', (tester) async {
    // 잡아야 할 잘못된 구현: `records_calendar.dart`가 `AttendanceStatus.etc`를
    // `colors.gray4`로 칠한다. **기본 테마에서는 두 토큰의 값이 같아서** 위
    // 테스트로는 구별되지 않는다 — 실제로 그렇게 바꿔도 299개가 전부
    // 초록이었다(리뷰 Important 6). attendanceEtc만 다른 값으로 덮어쓴
    // 테마로 pump해야 두 구현이 갈린다.
    const sentinel = Color(0xFF123456);
    final repo = _RecordingRecordsRepository(
      responses: {
        (2026, 8): _monthly(
          year: 2026,
          month: 8,
          records: [
            _record(day: 3, status: AttendanceStatus.etc),
            _record(day: 4, status: AttendanceStatus.present),
          ],
        ),
      },
    );
    await _pumpRecords(
      tester,
      repository: repo,
      now: DateTime(2026, 8, 15),
      colors: AppColors.light.copyWith(attendanceEtc: sentinel),
    );

    expect(_badgeColor(tester, '3'), sentinel);
    expect(
      _badgeColor(tester, '3'),
      isNot(AppColors.light.gray4),
      reason: 'gray4를 쓰는 구현이면 이 줄에서 걸린다',
    );
    // 대조군 — 다른 상태는 이 override에 영향받지 않는다.
    expect(_badgeColor(tester, '4'), AppColors.light.attendancePresent);
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

  testWidgets('하루에 세션이 여러 개면 가장 무거운 상태의 색으로 칠한다', (tester) async {
    // 잡아야 할 잘못된 구현: 그 날의 **첫** 기록이나 **마지막** 기록의 상태를
    // 그대로 쓴다 — 출석 하나와 결석 하나가 같은 날에 있으면 결석이 파란
    // "출석" 색에 가려져 사용자가 영영 못 본다.
    //
    // 결석 vs 출석 한 쌍만으로는 "결석이면 결석, 아니면 첫 기록" 같은 구현이
    // 통과한다 — 인접한 두 상태(결석-지각, 지각-기타, 기타-출석)를 전부,
    // 그리고 각각 **순서를 뒤집어** 태운다(Codex 지적).
    final repo = _RecordingRecordsRepository(
      responses: {
        (2026, 8): _monthly(
          year: 2026,
          month: 8,
          records: [
            _record(day: 3, status: AttendanceStatus.present, name: '오전 세션'),
            _record(day: 3, status: AttendanceStatus.absent, name: '오후 세션'),
            _record(day: 4, status: AttendanceStatus.absent, name: '오전 세션'),
            _record(day: 4, status: AttendanceStatus.present, name: '오후 세션'),
            _record(day: 5, status: AttendanceStatus.absent, name: '오전 세션'),
            _record(day: 5, status: AttendanceStatus.late, name: '오후 세션'),
            _record(day: 6, status: AttendanceStatus.late, name: '오전 세션'),
            _record(day: 6, status: AttendanceStatus.absent, name: '오후 세션'),
            _record(day: 7, status: AttendanceStatus.late, name: '오전 세션'),
            _record(day: 7, status: AttendanceStatus.etc, name: '오후 세션'),
            _record(day: 8, status: AttendanceStatus.etc, name: '오전 세션'),
            _record(day: 8, status: AttendanceStatus.late, name: '오후 세션'),
            _record(day: 9, status: AttendanceStatus.etc, name: '오전 세션'),
            _record(day: 9, status: AttendanceStatus.present, name: '오후 세션'),
            _record(day: 10, status: AttendanceStatus.present, name: '오전 세션'),
            _record(day: 10, status: AttendanceStatus.etc, name: '오후 세션'),
            _record(day: 11, status: AttendanceStatus.late, name: '오전 세션'),
            _record(day: 11, status: AttendanceStatus.present, name: '오후 세션'),
            _record(day: 12, status: AttendanceStatus.present, name: '오전 세션'),
            _record(day: 12, status: AttendanceStatus.late, name: '오후 세션'),
          ],
        ),
      },
    );
    await _pumpRecords(tester, repository: repo, now: DateTime(2026, 8, 15));

    const colors = AppColors.light;
    // 결석 > 출석
    expect(_badgeColor(tester, '3'), colors.attendanceAbsent);
    expect(_badgeColor(tester, '4'), colors.attendanceAbsent);
    // 결석 > 지각
    expect(_badgeColor(tester, '5'), colors.attendanceAbsent);
    expect(_badgeColor(tester, '6'), colors.attendanceAbsent);
    // 지각 > 기타
    expect(_badgeColor(tester, '7'), colors.attendanceLate);
    expect(_badgeColor(tester, '8'), colors.attendanceLate);
    // 기타 > 출석
    expect(_badgeColor(tester, '9'), colors.attendanceEtc);
    expect(_badgeColor(tester, '10'), colors.attendanceEtc);
    // 지각 > 출석
    expect(_badgeColor(tester, '11'), colors.attendanceLate);
    expect(_badgeColor(tester, '12'), colors.attendanceLate);
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

  testWidgets('월을 바꾸면 새 응답이 오기 전에 옛 달의 배지와 요약이 사라진다', (tester) async {
    // 잡아야 할 잘못된 구현: `_goToMonth`가 `_records`를 비우지 않는다 —
    // 새 달 헤더("2025. 12") 아래에 1월의 배지와 요약 숫자가 그대로 남아
    // 날짜와 숫자가 어긋나 보인다(리뷰 Minor 3).
    final repo = _RecordingRecordsRepository(
      gated: {(2025, 12)},
      responses: {
        (2026, 1): _monthly(
          year: 2026,
          month: 1,
          records: [_record(day: 3, year: 2026, month: 1, status: AttendanceStatus.present)],
          late: 41,
        ),
      },
    );
    await _pumpRecords(tester, repository: repo, now: DateTime(2026, 1, 15));

    expect(_badgeColor(tester, '3'), isNotNull);
    expect(_summaryValue('이번 달 지각 횟수', '41'), findsOneWidget);

    await tester.tap(_arrow('이전 달'));
    await tester.pump();

    expect(find.text('2025. 12'), findsOneWidget);
    expect(_badgeColor(tester, '3'), isNull, reason: '12월 응답이 오기 전에 1월 배지가 남으면 안 된다');
    expect(find.text('41'), findsNothing, reason: '12월 화면에 1월 요약이 남으면 안 된다');
    expect(find.text('-'), findsNWidgets(3), reason: '요약 카드 3장이 전부 자리표시자여야 한다');
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
  // 조회 실패
  // ---------------------------------------------------------------------
  testWidgets('조회에 실패하면 배지 없는 달력과 자리표시자 대시로 수렴한다', (tester) async {
    // 이 경로는 지금까지 어떤 테스트도 실행하지 않았다 — `catch` 안에 `throw`를
    // 넣어도 299개가 전부 초록이었다(리뷰 Important 8).
    //
    // 잡아야 할 잘못된 구현: 실패를 그대로 흘려보낸다(비동기 예외가 새어 나가
    // 테스트가 그 자리에서 깨진다), 또는 오류 상태 화면을 발명한다 — 이
    // 화면에는 오류 디자인이 없다.
    final repo = _RecordingRecordsRepository(failures: {(2026, 8)});
    await _pumpRecords(tester, repository: repo, now: DateTime(2026, 8, 15));

    expect(repo.calls, hasLength(1));
    expect(find.text('-'), findsNWidgets(3), reason: '요약 카드 3장이 전부 자리표시자여야 한다');
    expect(_badgeColor(tester, '3'), isNull);
    expect(find.text('2026. 08'), findsOneWidget, reason: '달력 자체는 그대로 그려져야 한다');
  });

  testWidgets('버려진 달의 실패 응답이 지금 보고 있는 달의 요약을 지우지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: 세대 검사 없는
    // `catch { setState(() => _records = null); }`. 늦게 도착한 12월의
    // **실패**가 이미 화면에 있는 11월 요약을 지워 버린다(리뷰 Important 8).
    final repo = _RecordingRecordsRepository(
      gated: {(2025, 12)},
      failures: {(2025, 12)},
      responses: {
        (2025, 11): _monthly(year: 2025, month: 11, late: 41, attendanceRate: 41),
      },
    );
    await _pumpRecords(tester, repository: repo, now: DateTime(2026, 1, 15));

    await tester.tap(_arrow('이전 달'));
    await tester.pump();
    await tester.tap(_arrow('이전 달'));
    await tester.pumpAndSettle();

    expect(find.text('2025. 11'), findsOneWidget);
    expect(find.text('41'), findsWidgets);

    // 이제 12월 조회가 **실패**로 끝난다.
    repo.release(2025, 12);
    await tester.pumpAndSettle();

    expect(find.text('2025. 11'), findsOneWidget);
    expect(find.text('41'), findsWidgets, reason: '11월 요약이 그대로 남아 있어야 한다');
    expect(find.text('-'), findsNothing, reason: '버려진 달의 실패가 현재 달을 자리표시자로 되돌렸다');
  });

  // ---------------------------------------------------------------------
  // UTC → KST (이슈 #12 "시간이 KST 기준으로 표시된다")
  // ---------------------------------------------------------------------
  testWidgets('UTC로 내려온 기록이 KST 날짜 칸에 놓인다', (tester) async {
    // 잡아야 할 잘못된 구현: `DateTime.parse`가 돌려준 UTC DateTime의
    // `.day`를 그대로 읽는다. 8일 16:00Z는 KST로 **9일** 01:00이므로 9일
    // 칸이 칠해져야 하는데, 변환을 빼면 8일 칸이 칠해진다.
    final repo = _RecordingRecordsRepository(
      responses: {
        (2026, 8): _monthly(
          year: 2026,
          month: 8,
          records: [
            AttendanceRecordItem(
              sessionId: 1,
              sessionName: '심야 세션',
              date: DateTime.utc(2026, 8, 8, 16),
              status: AttendanceStatus.present,
            ),
          ],
        ),
      },
    );
    await _pumpRecords(tester, repository: repo, now: DateTime(2026, 8, 15));

    expect(_badgeColor(tester, '9'), AppColors.light.attendancePresent);
    expect(_badgeColor(tester, '8'), isNull);
  });

  testWidgets('처리 시각이 KST로 표시된다', (tester) async {
    // 잡아야 할 잘못된 구현: UTC 시각을 그대로 찍는다 — 10:12Z를 "10:12"로
    // 보여준다. KST로는 19:12다.
    final repo = _RecordingRecordsRepository(
      responses: {
        (2026, 8): _monthly(
          year: 2026,
          month: 8,
          records: [
            _record(
              day: 3,
              status: AttendanceStatus.late,
              checkedAt: DateTime.utc(2026, 8, 3, 10, 12),
            ),
          ],
        ),
      },
    );
    await _pumpRecords(tester, repository: repo, now: DateTime(2026, 8, 15));

    await tester.tap(_calendarText('3'));
    await tester.pumpAndSettle();

    expect(find.text('19:12 처리'), findsOneWidget);
    expect(find.text('10:12 처리'), findsNothing);
  });

  testWidgets('"이번 달" 판정은 기기 시계가 아니라 KST를 따른다', (tester) async {
    // 잡아야 할 잘못된 구현: `widget.clock()`을 `toKst`에 통과시키지 않는다.
    // 서버가 준 날짜는 전부 KST로 옮기면서 **어느 달을 열지와 다음 달
    // 화살표를 막을지**만 기기 시계로 정하면 둘이 어긋난다.
    //
    // UTC 기기에서 2026-08-31 20:00Z는 KST로 **9월 1일 05:00**이다. 변환을
    // 빼면 8월이 열리고 `_canGoNext`(8 < 8)도 거짓이라 다음 달 화살표까지
    // 죽어 **현재 달인 9월을 아예 볼 수 없다** — KST 09:00이 되어야 풀린다.
    //
    // 시계를 `DateTime.utc`로 준 이유: 이 테스트가 도는 기계의 시간대와
    // 무관하게 "그 순간"이 고정돼야 한다(`DateTime(...)`은 기계 시간대로
    // 해석되므로 CI(UTC)와 개발 기계(KST)에서 다른 순간을 뜻하게 된다).
    final repo = _RecordingRecordsRepository();
    await _pumpRecords(tester, repository: repo, now: DateTime.utc(2026, 8, 31, 20));

    expect(find.text('2026. 09'), findsOneWidget, reason: 'KST로는 이미 9월이다');
    expect(repo.calls, [(clubId: 7, year: 2026, month: 9)]);

    const colors = AppColors.light;
    expect(
      _arrowColorFilter(tester, '다음 달'),
      ColorFilter.mode(colors.gray1, BlendMode.srcIn),
      reason: '9월이 KST의 이번 달이므로 그 너머로는 갈 수 없다',
    );

    // 8월로 갔다가 9월로 돌아올 수 있어야 한다. `initState`만 고치고
    // `_canGoNext`를 그대로 두면 8월에서 다음 달 화살표가 죽어 여기서 걸린다.
    await tester.tap(_arrow('이전 달'));
    await tester.pumpAndSettle();

    expect(find.text('2026. 08'), findsOneWidget);
    expect(
      _arrowColorFilter(tester, '다음 달'),
      ColorFilter.mode(colors.main, BlendMode.srcIn),
      reason: '8월은 KST의 이번 달(9월)보다 앞서므로 다음 달로 갈 수 있어야 한다',
    );

    await tester.tap(_arrow('다음 달'));
    await tester.pumpAndSettle();
    expect(find.text('2026. 09'), findsOneWidget);
  });

  testWidgets('KST로 다음 달이 되는 경계 기록은 이 달 달력에 얹지 않는다', (tester) async {
    // **여기서 고정하는 것은 "옳은 동작"이 아니라 "지금의 동작"이다.**
    // 지금 구현은 KST 날짜가 표시 중인 달 밖인 기록을 조용히 버린다. 그게
    // 옳으려면 서버가 `records[]`를 KST 기준으로 묶어 줘야 한다 — 그 계약은
    // 아직 확인되지 않았고(리뷰 Important 9, `records_screen.dart`의
    // `_recordsByDay` 주석), 조정자가 백엔드에 확인 중이다. 확인 결과에 따라
    // 이 테스트의 기대값이 바뀔 수 있다.
    //
    // 잡아야 할 잘못된 구현: 필터 줄을 지운다 — 지금까지는 그래도 299개가
    // 전부 통과했다(경계 픽스처가 어디에도 없었다). 필터가 없으면 KST로 9월
    // 1일인 세션이 **8월 달력의 1일 칸**을 결석 색으로 칠해 버린다.
    final repo = _RecordingRecordsRepository(
      responses: {
        (2026, 8): _monthly(
          year: 2026,
          month: 8,
          records: [
            // 8월 응답에 담겨 왔지만 KST로는 9월 1일 07:00이다.
            AttendanceRecordItem(
              sessionId: 1,
              sessionName: '월말 세션',
              date: DateTime.utc(2026, 8, 31, 22),
              status: AttendanceStatus.absent,
            ),
            // 대조군 — UTC로는 7월 31일이지만 KST로는 8월 1일 06:00이라
            // 8월에 남는다. "달 밖이면 버린다"가 UTC 날짜가 아니라 **KST
            // 날짜** 기준임을 함께 못박는다.
            AttendanceRecordItem(
              sessionId: 2,
              sessionName: '월초 세션',
              date: DateTime.utc(2026, 7, 31, 21),
              status: AttendanceStatus.present,
            ),
          ],
        ),
      },
    );
    await _pumpRecords(tester, repository: repo, now: DateTime(2026, 8, 15));

    expect(
      _badgeColor(tester, '1'),
      AppColors.light.attendancePresent,
      reason: 'KST로 8월 1일인 기록만 1일 칸에 있어야 한다 — 필터가 없으면 결석 색이 된다',
    );
    expect(_badgeColor(tester, '31'), isNull);

    await tester.tap(_calendarText('1'));
    await tester.pumpAndSettle();

    expect(find.text('월초 세션'), findsOneWidget);
    expect(
      find.text('월말 세션'),
      findsNothing,
      reason: '지금 구현은 이 세션을 조용히 버린다 — 서버가 KST로 묶어 준다는 가정에 기대고 있다',
    );
  });

  // ---------------------------------------------------------------------
  // 탭 가시성 · 화면 수명
  // ---------------------------------------------------------------------
  testWidgets('숨어 있는 동안에는 조회하지 않고, 보이는 순간 조회한다', (tester) async {
    // 잡아야 할 잘못된 구현: `initState`/`build`에서 가시성과 무관하게 곧장
    // 조회한다. `StatefulShellRoute.indexedStack`은 숨은 브랜치를 dispose하지
    // 않고 `TickerMode(enabled: false)`로 감싼 채 계속 build하므로, 이 가드가
    // 없으면 보이지도 않는 화면이 네트워크를 두드린다.
    final repo = _RecordingRecordsRepository();
    final h = await _pumpRecords(
      tester,
      repository: repo,
      now: DateTime(2026, 8, 15),
      visible: false,
    );

    expect(repo.calls, isEmpty);

    // 브랜치가 선택되는 순간을 재현한다 — 화면은 다시 만들어지지 않고
    // `TickerMode`의 값만 뒤집힌다.
    h.visible.value = true;
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
    final h = await _pumpRecords(tester, repository: repo, now: DateTime(2026, 8, 15));

    await tester.tap(_calendarText('3'));
    await tester.pumpAndSettle();
    expect(find.byType(SessionDetailSheetContent), findsOneWidget);
    expect(h.routes.stack, hasLength(2));

    h.visible.value = false;
    await tester.pumpAndSettle();

    expect(find.byType(SessionDetailSheetContent), findsNothing);
    expect(h.routes.stack, hasLength(1), reason: '보이는 내용만 사라지고 모달 배리어가 남으면 앱이 막힌다');
  });

  testWidgets('시트를 닫을 때 그 위에 쌓인 다른 라우트는 건드리지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: `removeRoute(route)` 대신 `pop()`으로 닫는다.
    // `pop()`은 "스택 맨 위"를 닫을 뿐 정체성을 모르므로, 시트 위에 다른 루트
    // 라우트가 얹혀 있으면 **그것**이 닫히고 시트는 그대로 남는다. 이 결함은
    // 이 프로젝트에서 실제로 출하됐었고(`home_screen.dart`의 리뷰 Important 6),
    // `buildAppSheetRoute`가 존재하는 이유가 정확히 이것인데도 지금까지
    // `pop()`으로 바꿔도 299개가 전부 초록이었다(리뷰 Important 1).
    final repo = _RecordingRecordsRepository(
      responses: {
        (2026, 8): _monthly(
          year: 2026,
          month: 8,
          records: [_record(day: 3, status: AttendanceStatus.present)],
        ),
      },
    );
    final h = await _pumpRecords(tester, repository: repo, now: DateTime(2026, 8, 15));

    await tester.tap(_calendarText('3'));
    await tester.pumpAndSettle();
    expect(find.byType(SessionDetailSheetContent), findsOneWidget);

    unawaited(h.navigator.currentState!.push<void>(_StackedTestRoute()));
    await tester.pumpAndSettle();
    expect(find.text('시트 위의 라우트'), findsOneWidget);
    expect(h.routes.stack, hasLength(3));

    h.visible.value = false;
    await tester.pumpAndSettle();

    expect(
      find.byType(SessionDetailSheetContent),
      findsNothing,
      reason: '닫아야 할 것은 시트다',
    );
    expect(
      find.text('시트 위의 라우트'),
      findsOneWidget,
      reason: 'pop()으로 닫으면 시트가 아니라 이 라우트가 사라진다',
    );
    expect(h.routes.stack, hasLength(2));
  });

  testWidgets('화면이 트리에서 빠지면 열려 있던 시트도 함께 닫힌다', (tester) async {
    // 잡아야 할 잘못된 구현: 시트 정리를 가시성 전환에만 두고 `dispose()`에는
    // 두지 않는다 — 로그아웃 등으로 이 화면이 셸째 사라지면, 루트
    // 내비게이터에 붙은 시트는 그대로 남아 다음 화면 위를 덮는다(리뷰 Minor 4).
    final repo = _RecordingRecordsRepository(
      gated: {(2026, 8)},
      responses: {
        (2026, 8): _monthly(
          year: 2026,
          month: 8,
          records: [_record(day: 3, status: AttendanceStatus.present)],
        ),
      },
    );
    final h = await _pumpRecords(tester, repository: repo, now: DateTime(2026, 8, 15));

    // 조회를 **진행 중인 채로** 시트를 연다 — dispose 이후에 도착하는 완료가
    // 사라진 State를 건드리지 않는지도 함께 태운다.
    repo.release(2026, 8);
    await tester.pumpAndSettle();
    await tester.tap(_calendarText('3'));
    await tester.pumpAndSettle();
    expect(h.routes.stack, hasLength(2));

    h.attached.value = false;
    await tester.pumpAndSettle();

    expect(find.byType(SessionDetailSheetContent), findsNothing);
    expect(h.routes.stack, hasLength(1), reason: '화면이 사라졌는데 시트만 남으면 앱이 막힌다');
  });

  // ---------------------------------------------------------------------
  // 클럽 전환
  // ---------------------------------------------------------------------
  testWidgets('클럽이 바뀌면 새 응답이 오기 전에 옛 클럽의 배지·요약·시트가 사라진다', (tester) async {
    // 잡아야 할 잘못된 구현: 새 조회만 시작하고 `_records`를 비우지 않으며
    // 열린 시트도 닫지 않는다 — 새 클럽 화면에 이전 클럽의 배지와 요약 3장이
    // 그대로 뜨고, 시트는 푸시 시점 스냅샷이라 영원히 옛 클럽을 보여준다
    // (리뷰 Important 3 — 홈 화면의 `_resetClubScopedState`가 같은 문제다).
    final repo = _RecordingRecordsRepository(
      // 새 클럽의 응답은 붙잡아 둔다 — "응답이 오기 전"의 화면을 봐야 한다.
      gatedClubIds: {9},
      responses: {
        (2026, 8): _monthly(
          year: 2026,
          month: 8,
          records: [_record(day: 3, status: AttendanceStatus.present, name: '7번 동아리 세션')],
          late: 41,
        ),
      },
    );
    final h = await _pumpRecords(tester, repository: repo, now: DateTime(2026, 8, 15));

    expect(_badgeColor(tester, '3'), isNotNull);
    expect(_summaryValue('이번 달 지각 횟수', '41'), findsOneWidget);

    await tester.tap(_calendarText('3'));
    await tester.pumpAndSettle();
    expect(find.text('7번 동아리 세션'), findsOneWidget);

    // 사용자가 다른 동아리로 전환했다.
    h.container.read(_clubIdProvider.notifier).state = 9;
    await tester.pumpAndSettle();

    expect(repo.calls.last, (clubId: 9, year: 2026, month: 8));
    expect(
      find.byType(SessionDetailSheetContent),
      findsNothing,
      reason: '옛 클럽의 시트가 새 클럽 화면 위에 남으면 안 된다',
    );
    expect(h.routes.stack, hasLength(1));
    expect(_badgeColor(tester, '3'), isNull, reason: '옛 클럽의 배지가 남으면 안 된다');
    expect(find.text('41'), findsNothing, reason: '옛 클럽의 요약이 남으면 안 된다');
    expect(find.text('-'), findsNWidgets(3));
  });

  // ---------------------------------------------------------------------
  // 요약 카드
  // ---------------------------------------------------------------------
  testWidgets('요약 카드는 서버가 준 status 집계와 attendanceRate를 그대로 보여준다', (tester) async {
    // 잡아야 할 잘못된 구현: 클라이언트가 records[]를 세어 다시 계산한다.
    // 이 픽스처는 그 두 구현이 **다른 숫자**를 내도록 짜여 있다 —
    // records[]로 세면 출석률 67%(2/3)·지각 0회지만, 서버는 94%·지각 41회를
    // 줬다(가입 이전 세션을 분모에서 빼는 등 서버만 아는 규칙 때문이다).
    //
    // 세 카드 전부 **그 카드 안으로 스코프를 좁혀** 검사한다. 예전에는 지각
    // 카드만 `find.text('5')`로 봤는데 달력에 항상 5일 칸이 있어서, 지각
    // 카드를 `r?.etc`(픽스처 0)로 잘못 배선해도 통과했다(리뷰 Important 7).
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
          absent: 43,
          late: 41,
          etc: 42,
          attendanceRate: 94,
        ),
      },
    );
    await _pumpRecords(tester, repository: repo, now: DateTime(2026, 8, 15));

    expect(find.text('%'), findsOneWidget);
    expect(_summaryValue('이번 달 출석률', '94'), findsOneWidget);
    expect(
      _summaryValue('이번 달 지각 횟수', '41'),
      findsOneWidget,
      reason: 'etc(42)나 absent(43)를 지각 카드에 배선하면 여기서 걸린다',
    );
    expect(
      _summaryValue('이번 달 결석 횟수', '43'),
      findsOneWidget,
      reason: 'records[]를 세면 1이 나온다 — 서버가 준 43이어야 한다',
    );
    expect(find.text('67'), findsNothing, reason: '클라이언트가 출석률을 다시 계산한 흔적');
  });

  testWidgets('출석률은 서버가 준 정밀도를 그대로 보여준다', (tester) async {
    // 잡아야 할 잘못된 구현: `toStringAsFixed(0)` — 83.3을 "83"으로 반올림해
    // 서버가 계산한 값과 다른 숫자를 화면에 띄운다. 기존 픽스처가 정수
    // 94.0뿐이라 이 차이가 드러나지 않았다(리뷰 Minor 6).
    final repo = _RecordingRecordsRepository(
      responses: {(2026, 8): _monthly(year: 2026, month: 8, attendanceRate: 83.3)},
    );
    await _pumpRecords(tester, repository: repo, now: DateTime(2026, 8, 15));

    expect(_summaryValue('이번 달 출석률', '83.3'), findsOneWidget);
    expect(find.text('83'), findsNothing);
  });

  test('formatAttendanceRate는 정수에 소수점을 붙이지 않고 소수는 그대로 보존한다', () {
    // 잡아야 할 잘못된 구현: `toStringAsFixed(0)`(83.3 → "83")이나
    // `toString()`(94.0 → "94.0" — Figma 목업은 "94"다).
    expect(formatAttendanceRate(0), '0');
    expect(formatAttendanceRate(94), '94');
    expect(formatAttendanceRate(100), '100');
    expect(formatAttendanceRate(83.3), '83.3');
    expect(formatAttendanceRate(66.67), '66.67');
    expect(formatAttendanceRate(99.9), '99.9');
  });

  testWidgets('과거 달을 보고 있으면 요약 카드 라벨이 그 달을 가리킨다', (tester) async {
    // 잡아야 할 잘못된 구현: Figma 문구 "이번 달 …"을 어느 달에서나 그대로
    // 쓴다 — 7월 숫자를 띄워 놓고 "이번 달"이라고 쓰는 셈이다(리뷰 Minor 7,
    // 조정자 판정). 반대로 이번 달에서까지 "8월 …"로 바꿔 버리는 것도 안
    // 된다 — Figma가 설계한 상태의 문구는 그대로여야 한다.
    final repo = _RecordingRecordsRepository();
    await _pumpRecords(tester, repository: repo, now: DateTime(2026, 8, 15));

    expect(find.text('이번 달 출석률'), findsOneWidget);
    expect(find.text('이번 달 지각 횟수'), findsOneWidget);
    expect(find.text('이번 달 결석 횟수'), findsOneWidget);

    await tester.tap(_arrow('이전 달'));
    await tester.pumpAndSettle();

    expect(find.text('7월 출석률'), findsOneWidget);
    expect(find.text('7월 지각 횟수'), findsOneWidget);
    expect(find.text('7월 결석 횟수'), findsOneWidget);
    expect(find.textContaining('이번 달'), findsNothing);

    // 이번 달로 돌아오면 Figma 문구가 돌아온다.
    await tester.tap(_arrow('다음 달'));
    await tester.pumpAndSettle();

    expect(find.text('이번 달 지각 횟수'), findsOneWidget);
    expect(find.textContaining('8월 '), findsNothing);
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
              checkedAt: DateTime.utc(2026, 8, 3, 10, 7),
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

    // 긴 내용을 위해 `isScrollControlled: true`로 바꾼 뒤에도 **짧은 시트는
    // 내용 높이에 맞아야** 한다 — 세션 둘짜리가 화면을 다 덮으면 회귀다.
    final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(
      tester.getTopLeft(find.byType(AppSheet)).dy,
      greaterThan(screenHeight / 2),
      reason: '짧은 시트가 화면 절반 위로 올라오면 내용 높이에 맞지 않은 것이다',
    );
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
    final h = await _pumpRecords(tester, repository: repo, now: DateTime(2026, 8, 15));

    await tester.tap(_calendarText('7'));
    await tester.pumpAndSettle();

    expect(find.byType(SessionDetailSheetContent), findsNothing);
    expect(
      h.routes.stack,
      hasLength(1),
      reason: '보이는 내용만 비우고 모달 라우트를 남기면 배리어가 화면을 막는다',
    );

    // 대조군 — 같은 하네스에서 기록이 있는 날짜는 실제로 시트를 연다.
    await tester.tap(_calendarText('3'));
    await tester.pumpAndSettle();
    expect(h.routes.stack, hasLength(2));
  });

  testWidgets('시트의 세션은 서버 응답 순서가 아니라 시간순으로 뜬다', (tester) async {
    // 잡아야 할 잘못된 구현: 서버가 준 순서를 그대로 그린다 — 응답 순서가
    // 바뀌면 화면 순서도 따라 바뀐다. 명세서(60행)는 시간순을 요구한다
    // (리뷰 Minor 8).
    final repo = _RecordingRecordsRepository(
      responses: {
        (2026, 8): _monthly(
          year: 2026,
          month: 8,
          records: [
            // 셋 다 KST로 8월 3일이고, 응답 순서는 시간순이 아니다.
            AttendanceRecordItem(
              sessionId: 30,
              sessionName: '저녁 세션',
              date: DateTime.utc(2026, 8, 3, 10), // KST 19:00
              status: AttendanceStatus.present,
            ),
            AttendanceRecordItem(
              sessionId: 10,
              sessionName: '아침 세션',
              date: DateTime.utc(2026, 8, 2, 23), // KST 08:00
              status: AttendanceStatus.present,
            ),
            AttendanceRecordItem(
              sessionId: 20,
              sessionName: '점심 세션',
              date: DateTime.utc(2026, 8, 3, 3), // KST 12:00
              status: AttendanceStatus.present,
            ),
          ],
        ),
      },
    );
    await _pumpRecords(tester, repository: repo, now: DateTime(2026, 8, 15));

    await tester.tap(_calendarText('3'));
    await tester.pumpAndSettle();

    final morning = tester.getTopLeft(find.text('아침 세션')).dy;
    final noon = tester.getTopLeft(find.text('점심 세션')).dy;
    final evening = tester.getTopLeft(find.text('저녁 세션')).dy;
    expect(morning, lessThan(noon));
    expect(noon, lessThan(evening));
  });

  testWidgets('하루에 세션이 많아도 넘치지 않고 스크롤로 마지막 세션까지 볼 수 있다', (tester) async {
    // 잡아야 할 잘못된 구현: `isScrollControlled: false` + 스크롤 없는
    // `Column`. 시트 최대 높이가 화면의 9/16로 묶여 `RenderFlex` 오버플로가
    // 나고, 뒤쪽 세션은 볼 방법이 아예 없다(리뷰 Important 5). 기존
    // 픽스처는 하루 2개뿐이라 이 경계를 넘지 못했다.
    final repo = _RecordingRecordsRepository(
      responses: {
        (2026, 8): _monthly(
          year: 2026,
          month: 8,
          records: [
            for (var i = 1; i <= 12; i++)
              _record(
                day: 3,
                status: AttendanceStatus.present,
                name: '세션 $i',
                checkedAt: DateTime.utc(2026, 8, 3, i),
              ),
          ],
        ),
      },
    );
    await _pumpRecords(tester, repository: repo, now: DateTime(2026, 8, 15));

    await tester.tap(_calendarText('3'));
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason: 'RenderFlex 오버플로 — 뒤쪽 세션이 잘려 나갔다',
    );

    final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(
      tester.getTopLeft(find.text('세션 12')).dy,
      greaterThan(screenHeight),
      reason: '전제 — 12개는 한 화면에 다 들어가지 않는다(들어간다면 이 테스트가 아무것도 증명하지 않는다)',
    );

    await tester.drag(find.text('세션 1'), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('세션 12')).dy,
      lessThan(screenHeight),
      reason: '스크롤로 마지막 세션까지 도달할 수 있어야 한다',
    );
  });

  testWidgets('재조회가 끝나면 열려 있는 시트도 새 기록으로 갱신된다', (tester) async {
    // 잡아야 할 잘못된 구현: 푸시 시점의 리스트를 그대로 시트에 넘긴다.
    // 시트는 **루트** 내비게이터에 붙어 있어 이 화면의 setState로는 다시
    // 그려지지 않으므로, 탭에 돌아와 재조회가 도는 동안 연 시트는 갱신이
    // 끝난 뒤에도 옛 기록을 계속 보여준다(리뷰 Important 4).
    final responses = <(int, int), MonthlyRecords>{
      (2026, 8): _monthly(
        year: 2026,
        month: 8,
        records: [_record(day: 3, status: AttendanceStatus.present, name: '옛 세션')],
      ),
    };
    final repo = _RecordingRecordsRepository(responses: responses, gated: {(2026, 8)});
    final h = await _pumpRecords(tester, repository: repo, now: DateTime(2026, 8, 15));

    repo.release(2026, 8);
    await tester.pumpAndSettle();
    expect(_badgeColor(tester, '3'), isNotNull);

    // 탭을 떠났다 돌아온다 — 그 사이 서버 쪽 값이 바뀌었다.
    h.visible.value = false;
    await tester.pumpAndSettle();
    responses[(2026, 8)] = _monthly(
      year: 2026,
      month: 8,
      records: [_record(day: 3, status: AttendanceStatus.late, name: '새 세션')],
    );
    h.visible.value = true;
    await tester.pump();

    // 재조회가 **도는 중에** 날짜를 탭한다 — 화면은 아직 옛 기록이다.
    await tester.tap(_calendarText('3'));
    await tester.pumpAndSettle();
    expect(find.text('옛 세션'), findsOneWidget);

    repo.release(2026, 8);
    await tester.pumpAndSettle();

    expect(find.text('새 세션'), findsOneWidget, reason: '시트가 재조회 결과를 따라가야 한다');
    expect(find.text('옛 세션'), findsNothing);
  });

  testWidgets('재조회로 그 날의 기록이 사라지면 빈 시트를 남기지 않고 닫는다', (tester) async {
    // 잡아야 할 잘못된 구현: 시트를 새 기록에 맞추기만 하고 빈 목록을 그대로
    // 넘긴다 — 아무것도 없는 시트가 화면을 덮은 채 남는다. 화면 쪽 빈-목록
    // 가드가 여기서 실제로 실행된다(리뷰 Minor 2).
    final responses = <(int, int), MonthlyRecords>{
      (2026, 8): _monthly(
        year: 2026,
        month: 8,
        records: [_record(day: 3, status: AttendanceStatus.present, name: '취소되기 전 세션')],
      ),
    };
    final repo = _RecordingRecordsRepository(responses: responses, gated: {(2026, 8)});
    final h = await _pumpRecords(tester, repository: repo, now: DateTime(2026, 8, 15));

    repo.release(2026, 8);
    await tester.pumpAndSettle();

    h.visible.value = false;
    await tester.pumpAndSettle();
    // 그 세션이 통째로 사라졌다(관리자가 삭제).
    responses[(2026, 8)] = _monthly(year: 2026, month: 8);
    h.visible.value = true;
    await tester.pump();

    await tester.tap(_calendarText('3'));
    await tester.pumpAndSettle();
    expect(find.byType(SessionDetailSheetContent), findsOneWidget);
    expect(h.routes.stack, hasLength(2));

    repo.release(2026, 8);
    await tester.pumpAndSettle();

    expect(find.byType(SessionDetailSheetContent), findsNothing);
    expect(
      h.routes.stack,
      hasLength(1),
      reason: '내용만 비우고 모달 라우트를 남기면 배리어가 화면을 막는다',
    );
  });
}
