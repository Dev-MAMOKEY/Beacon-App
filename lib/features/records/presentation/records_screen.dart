import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../components/ui/card.dart';
import '../../../components/ui/owned_routes.dart';
import '../../../components/ui/sheet.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/time/kst.dart';
import '../../auth/presentation/session_controller.dart';
import '../data/records_dto.dart';
import '../data/records_repository.dart';
import 'records_calendar.dart';
import 'session_detail_sheet.dart';

/// 기록 화면(이슈 #12, Figma `353:2245` "기록 화면 (캘린더)").
///
/// 위에서부터 달력 카드(`384:1815`)와 요약 카드 3종(`353:2298` "출석 상태")
/// 이다. 상단 바·하단 탭 바는 `AppShell`이 그린다.
class RecordsScreen extends ConsumerStatefulWidget {
  const RecordsScreen({super.key, this.clock = DateTime.now});

  /// "이번 달"의 정본. 다음 달 화살표를 비활성으로 만드는 기준이자 처음
  /// 보여줄 달이다. 테스트가 특정 달(1일의 요일이 다른 달들)을 고정할 수
  /// 있도록 주입 가능하게 뒀다 — 실사용에서는 항상 [DateTime.now]다.
  @visibleForTesting
  final DateTime Function() clock;

  @override
  ConsumerState<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends ConsumerState<RecordsScreen> {
  late int _year;
  late int _month;

  /// 지금 화면에 반영된 조회 결과. null이면 아직 못 받았거나 실패했다.
  MonthlyRecords? _records;

  /// 진행 중인 조회의 세대.
  ///
  /// 월을 빠르게 여러 번 넘기면 요청이 겹친다. 8월 조회가 느리게 시작하고
  /// 7월 조회가 먼저 끝나면, **나중에** 도착한 8월 응답이 아니라 7월 응답이
  /// 화면에 남을 수 있다 — 정확히 홈 화면이 클럽 전환에서 냈던 결함이다.
  /// 모든 완료 지점이 자기가 시작된 세대를 확인하고, 아니면 결과를 버린다.
  int _loadGeneration = 0;

  int? _loadedClubId;

  /// 기록 탭이 지금 실제로 사용자에게 보이는지.
  ///
  /// `StatefulShellRoute.indexedStack`은 선택되지 않은 브랜치를 dispose하지
  /// 않고 `Offstage` + `TickerMode(enabled: false)`로 감싼 채 계속 build한다.
  /// 그래서 (1) 이 가드가 없으면 앱을 켜자마자 숨은 기록 탭이 곧장 조회를
  /// 날리고, (2) 열려 있는 시트가 다른 탭 위에 그대로 남는다. 홈 화면이
  /// 같은 신호(`TickerMode.valuesOf`)를 쓰는 근거는 `home_screen.dart`의
  /// `_visible` 주석에 자세히 적혀 있다.
  bool _visible = true;

  /// 이 화면이 루트 내비게이터에 push한 시트 라우트. 탭이 숨겨지거나 화면이
  /// 트리에서 빠지면 닫는다 — `Navigator.pop()`은 "스택 맨 위"를 닫을 뿐
  /// 정체성을 모르므로 라우트 객체를 직접 들고 있는다.
  late final OwnedRoutes _owned = OwnedRoutes(_rootNavigator);

  /// 열려 있는 시트가 보고 있는 날(1~31). 시트가 없으면 null이다.
  int? _sheetDay;

  /// 시트가 지금 보여야 할 기록들.
  ///
  /// 시트는 **루트** 내비게이터에 붙어 있어 이 화면의 `setState`로는 다시
  /// 그려지지 않는다. 푸시 시점의 리스트를 그대로 넘기면 그 순간의 스냅샷이
  /// 되어, 재조회가 끝나 화면이 갱신된 뒤에도 시트만 옛 기록을 계속
  /// 보여준다(리뷰 Important 4). 홈 화면의 `_codeEntryState` +
  /// `ListenableBuilder`와 같은 방식으로 시트를 구독자로 만든다.
  final ValueNotifier<List<AttendanceRecordItem>> _sheetRecords =
      ValueNotifier<List<AttendanceRecordItem>>(const []);

  /// `dispose()` 시점에는 이 화면의 엘리먼트가 트리에서 빠지는 중이라
  /// `Navigator.of(context)`를 신뢰할 수 없다 — 미리 잡아 둔다.
  late final NavigatorState _rootNavigator;

  @override
  void initState() {
    super.initState();
    final now = _nowKst;
    _year = now.year;
    _month = now.month;
    _rootNavigator = appSheetNavigatorOf(context);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible == _visible) return;
    _visible = visible;
    if (visible) {
      // 다시 보이는 순간 지금 보고 있는 달을 새로 조회한다 — 홈에서 출석
      // 체크를 하고 넘어오면 이 화면의 숫자가 이미 옛것이다.
      final clubId = _loadedClubId;
      if (clubId != null) _load(clubId, _year, _month);
    } else {
      _detachSheet();
    }
    _owned.visible = visible;
  }

  @override
  void dispose() {
    // 이 시점 이후에 도착하는 모든 조회 완료를 무효화한다. 엄밀히 말하면
    // 없어도 결과가 같다 — [_isCurrentLoad]의 `mounted` 검사가 dispose 이후를
    // 이미 전부 막고, 이 증가와 unmount 사이에는 비동기 틈이 없어서 세대만
    // 보는 코드가 끼어들 자리가 없다(그래서 이 줄만 지워도 어떤 테스트도
    // 깨지지 않는다). "이 State가 시작한 비동기는 여기서 끝난다"는 규약을
    // 한 군데서 읽히게 두는 값이라 남긴다 — `home_screen.dart`의 dispose도
    // 같은 모양이다.
    _loadGeneration++;
    // 여기서는 프레임 뒤로 미룰 수 없다 — 이 State는 곧 사라지고, 미뤄 둔
    // 콜백이 돌 때쯤이면 시트를 닫을 주체가 아무도 없다.
    _closeSheet();
    _sheetRecords.dispose();
    super.dispose();
  }

  /// KST 기준 "지금". 기기 시간대가 아니다 — 서버가 준 날짜는 전부 [toKst]를
  /// 거치는데 **어느 달을 열지와 다음 달 화살표를 막을지**만 기기 시계로
  /// 정하면 둘이 어긋난다. UTC 기기에서 `2026-08-31 20:00Z`(= KST 9월 1일
  /// 05:00)에 이 탭을 열면 8월이 열리고 `_canGoNext`도 거짓이라 **현재 달인
  /// 9월을 아예 볼 수 없다**(KST 09:00이 되어야 풀린다). 반대로 UTC+13 기기는
  /// 한국에서 시작하지도 않은 달로 넘어갈 수 있다.
  DateTime get _nowKst => toKst(widget.clock());

  /// [generation]이 아직 최신 조회 세대인지.
  bool _isCurrentLoad(int generation) => mounted && generation == _loadGeneration;

  Future<void> _load(int clubId, int year, int month) async {
    final generation = ++_loadGeneration;
    final MonthlyRecords records;
    try {
      records = await ref
          .read(recordsRepositoryProvider)
          .fetch(clubId: clubId, year: year, month: month);
    } catch (_) {
      // 조회 실패는 "아직 값 없음"과 같은 화면(배지 없는 달력 + 자리표시자
      // 대시)으로 수렴시킨다. 이 화면에는 오류 상태 디자인이 없다.
      //
      // 실패 경로에도 세대 검사가 필요하다 — 이미 버려진 달의 **실패**
      // 응답이 지금 보고 있는 달의 요약을 지워서는 안 된다.
      if (!_isCurrentLoad(generation)) return;
      setState(() => _records = null);
      _syncSheet();
      return;
    }
    // 늦게 도착한 옛 달의 응답이 현재 달을 덮어쓰지 않게 한다.
    if (!_isCurrentLoad(generation)) return;
    setState(() => _records = records);
    _syncSheet();
  }

  void _goToMonth(int year, int month) {
    final clubId = _loadedClubId;
    setState(() {
      _year = year;
      _month = month;
      // 새 달의 응답이 오기 전까지 옛 달의 요약·배지를 그대로 두면 날짜와
      // 숫자가 어긋나 보인다.
      _records = null;
    });
    if (clubId != null) _load(clubId, year, month);
  }

  void _goToPreviousMonth() {
    final previous = DateTime(_year, _month - 1);
    _goToMonth(previous.year, previous.month);
  }

  void _goToNextMonth() {
    final next = DateTime(_year, _month + 1);
    _goToMonth(next.year, next.month);
  }

  /// 이번 달(=[_nowKst]의 달)보다 앞선 달을 보고 있을 때만 다음 달로 갈 수
  /// 있다. 미래 월은 조회 대상이 아니다.
  bool get _canGoNext {
    final now = _nowKst;
    return _year * 12 + _month < now.year * 12 + now.month;
  }

  /// 지금 보고 있는 달이 KST 기준 "이번 달"인지.
  bool get _isCurrentMonth {
    final now = _nowKst;
    return _year == now.year && _month == now.month;
  }

  /// 일(1~31) → 그 날의 기록들. 각 날의 목록은 **시간순**이다(명세서 60행).
  Map<int, List<AttendanceRecordItem>> get _recordsByDay {
    final byDay = <int, List<AttendanceRecordItem>>{};
    for (final record in _records?.records ?? const <AttendanceRecordItem>[]) {
      // 서버가 준 UTC 시각을 KST 벽시계로 옮긴 뒤에 날짜 칸을 정한다 —
      // 그대로 읽으면 KST로 9일 새벽인 세션이 8일 칸에 붙는다(이슈 #12).
      final date = toKst(record.date);
      // 지금 보고 있는 달이 아니면 캘린더에 얹지 않는다 — 그러지 않으면
      // 다른 달의 1일이 이 달의 1일 칸을 칠한다.
      //
      // **알려진 결함 — 서버가 고쳐야 한다.** 2026-08-16 백엔드 확인 결과
      // 서버는 `records[]`를 **UTC 기준**으로 묶는다. KST는 UTC+9이므로 어떤
      // UTC 월의 마지막 9시간(말일 15:00~23:59 UTC = KST 다음 달 1일
      // 00:00~08:59)에 열린 세션은:
      //   - 그 달 응답에 담겨 여기서 "다음 달"로 판정돼 버려지고,
      //   - 다음 달 응답에는 (서버가 UTC로 거르므로) 애초에 없다.
      // 결국 **어느 달에서도 보이지 않는다.** 그런데 서버의
      // late/absent/attendanceRate는 그 세션을 이전 달에 세므로 캘린더와 요약
      // 카드가 말없이 어긋난다. 해당 범위는 매월 1일 KST 오전 0~9시 세션뿐이다.
      //
      // 클라이언트에서 앞뒤 달을 함께 조회해 완화할 수는 있지만 요약 카드는
      // 여전히 UTC 월 집계라 불일치가 남는다 — 서버가 KST로 거르는 것이
      // 달력과 요약을 한 번에 맞추는 유일한 수정이라 그렇게 요청해 두었다.
      // 그때까지 현재 동작은 `records_screen_test.dart`의 월 경계 테스트가
      // 고정한다(이 줄을 지우면 그 테스트가 깨진다).
      if (date.year != _year || date.month != _month) continue;
      (byDay[date.day] ??= []).add(record);
    }
    for (final records in byDay.values) {
      records.sort((a, b) {
        final byTime = a.date.compareTo(b.date);
        // Dart의 `List.sort`는 안정 정렬이 아니다 — 같은 시각의 세션 둘이
        // 리빌드마다 다른 순서로 뜨지 않도록 sessionId로 결정론을 준다.
        return byTime != 0 ? byTime : a.sessionId.compareTo(b.sessionId);
      });
    }
    return byDay;
  }

  void _openSheet(int day) {
    final records = _recordsByDay[day];
    // 기록이 없으면 아예 열지 않는다. `RecordsCalendar`가 이미 탭을 막지만,
    // 그 가드 하나에만 기대지 않는다. 이 가드는 [_syncSheet]도 함께 쓴다 —
    // 재조회로 그 날의 기록이 사라지면 빈 시트가 남아서는 안 된다.
    if (records == null || records.isEmpty) return;

    _sheetDay = day;
    _sheetRecords.value = records;

    final route = buildAppSheetRoute<void>(
      context: context,
      navigator: _rootNavigator,
      builder: (context) => ListenableBuilder(
        listenable: _sheetRecords,
        builder: (context, _) => SessionDetailSheetContent(
          date: DateTime(_year, _month, day),
          records: _sheetRecords.value,
        ),
      ),
    );
    final pushed = _owned.push(route);
    if (pushed == null) {
      // 숨겨진 동안에는 소유자가 push를 거부한다 — 추적 상태도 되돌린다.
      _sheetDay = null;
      return;
    }
    unawaited(
      pushed.popped.then((_) {
        // 이미 다른 시트로 바뀐 뒤에 도착한 옛 시트의 완료가 현재 추적을
        // 지우지 않도록 정체성으로 판정한다(`home_screen.dart`와 같은 이유).
        if (_sheetDay == day && !_owned.owns(pushed)) _sheetDay = null;
      }),
    );
  }

  /// 열려 있는 시트를 방금 도착한 `_records`에 맞춘다. 조회 완료 지점에서만
  /// 부른다 — 빌드 단계에서는 내비게이션(닫기)을 할 수 없다.
  void _syncSheet() {
    final day = _sheetDay;
    if (day == null) return;
    final records = _recordsByDay[day];
    // 새 데이터에 그 날의 기록이 하나도 없으면 닫는다 — 이 화면에 "빈 시트"
    // 라는 상태는 없다.
    if (records == null || records.isEmpty) {
      _closeSheet();
      return;
    }
    _sheetRecords.value = records;
  }

  /// 시트 추적 상태만 비우고 라우트를 돌려준다. 실제 제거([_removeSheetRoute])
  /// 와 분리돼 있는 이유는 빌드 단계에서는 내비게이션을 할 수 없기 때문이다
  /// (`home_screen.dart`의 `_takeOwnedPopups`와 같은 이유).
  List<Route<void>> _takeSheet() {
    _sheetDay = null;
    return _owned.take();
  }

  void _removeSheetRoute(List<Route<void>> routes) => _owned.removeAll(routes);

  /// 지금 당장 닫는다. `dispose()`처럼 프레임 뒤로 미룰 수 없는 자리와,
  /// 빌드 단계가 아닌 비동기 완료 지점에서만 쓴다.
  void _closeSheet() => _removeSheetRoute(_takeSheet());

  /// 추적만 지금 끊고 실제 제거는 이 프레임이 끝난 뒤로 미룬다. `build()`와
  /// `didChangeDependencies()`는 빌드 단계라 내비게이션을 할 수 없다 —
  /// `home_screen.dart`의 `_onBecameHidden`/`_resetClubScopedState`가 같은
  /// 이유로 `addPostFrameCallback`을 쓴다. 오늘 동기 호출이 터지지 않는 것은
  /// 우연이지 계약이 아니다.
  void _detachSheet() {
    final routes = _takeSheet();
    if (routes.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _removeSheetRoute(routes));
  }

  /// 클럽이 바뀌었다 — 이전 클럽에서 받은 것을 전부 버린다.
  ///
  /// 세대 검사만으로는 **이미 도착해 화면에 반영된** 옛 클럽의 배지와 요약
  /// 카드가 새 응답이 올 때까지 그대로 남는다. 열려 있는 시트는 더 나빠서,
  /// 새 클럽 화면 위에서 옛 클럽의 세션을 계속 보여준다(리뷰 Important 3 —
  /// `home_screen.dart`의 `_resetClubScopedState`가 같은 문제를 처리한다).
  ///
  /// `build()` 중에 불리므로 필드만 바꾸고(어차피 이어지는 build가 새 값을
  /// 읽는다) 내비게이션은 프레임 뒤로 미룬다.
  void _resetClubScopedState() {
    _records = null;
    _detachSheet();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final session = ref.watch(sessionControllerProvider).value;

    if (session is! SessionReady) {
      return ColoredBox(
        color: colors.bg,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    // 숨어 있는 동안에는 조회하지 않는다 — `IndexedStack`은 숨은 브랜치도
    // 계속 build하므로 이 가드가 없으면 앱을 켜자마자 조회가 나간다.
    if (_visible && _loadedClubId != session.clubId) {
      // 처음 붙는 것과 클럽이 **바뀌는** 것은 다르다 — 바뀔 때만 옛 클럽의
      // 잔재를 지운다.
      final changedClub = _loadedClubId != null;
      _loadedClubId = session.clubId;
      if (changedClub) _resetClubScopedState();
      _load(session.clubId, _year, _month);
    }

    return ColoredBox(
      color: colors.bg,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          // Figma `353:2245` 실측 — 상단 바와 달력 사이 14, 달력 섹션 자체의
          // pt 7, 좌우 24.
          padding: const EdgeInsets.fromLTRB(24, 21, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RecordsCalendar(
                year: _year,
                month: _month,
                recordsByDay: _recordsByDay,
                onPreviousMonth: _goToPreviousMonth,
                onNextMonth: _canGoNext ? _goToNextMonth : null,
                onDayTap: _openSheet,
              ),
              // 달력 섹션과 출석 상태 섹션 사이 14(Figma).
              const SizedBox(height: 14),
              _SummaryCards(
                records: _records,
                month: _month,
                isCurrentMonth: _isCurrentMonth,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Figma `353:2298` "출석 상태" — 전체 폭 카드 3장이 10 간격으로 쌓인다.
/// 홈 화면의 요약 카드(`_SummaryCards`)와 라벨·배치가 다르다(홈은 지각·결석이
/// 한 줄에 둘, 출석률 카드에 진행 막대가 있다) — 같은 위젯을 재사용하지
/// 않는 이유다.
class _SummaryCards extends StatelessWidget {
  const _SummaryCards({
    required this.records,
    required this.month,
    required this.isCurrentMonth,
  });

  final MonthlyRecords? records;

  /// 지금 보고 있는 달(1~12). [isCurrentMonth]가 거짓일 때 라벨에 쓴다.
  final int month;

  /// 지금 보고 있는 달이 KST 기준 "이번 달"인지.
  final bool isCurrentMonth;

  /// 카드 라벨의 기간 부분.
  ///
  /// Figma(`353:2303`/`353:2311`/`353:2317`)의 문구는 "이번 달 …"이고 그
  /// 목업은 이번 달을 보고 있는 상태다 — **그 상태의 문구는 그대로 둔다.**
  /// 과거 달을 보고 있는 상태는 디자인에 아예 없는데, 9월 숫자를 띄워 놓고
  /// "이번 달"이라고 쓰는 것은 사실과 다르므로 그때만 그 달을 가리킨다
  /// (조정자 판정).
  String get _period => isCurrentMonth ? '이번 달' : '$month월';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final r = records;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RateCard(rate: r?.attendanceRate, label: '$_period 출석률'),
        const SizedBox(height: 10),
        _CountCard(
          iconAsset: 'assets/icons/time-line.svg',
          iconColor: colors.yellow,
          label: '$_period 지각 횟수',
          value: r?.late,
        ),
        const SizedBox(height: 10),
        _CountCard(
          iconAsset: 'assets/icons/error-warning-line.svg',
          iconColor: colors.red,
          label: '$_period 결석 횟수',
          value: r?.absent,
        ),
      ],
    );
  }
}

/// 서버가 준 출석률을 **정밀도를 버리지 않고** 문자열로 만든다.
///
/// `toStringAsFixed(0)`은 83.3을 "83"으로 반올림해 서버가 계산한 값과 다른
/// 숫자를 화면에 띄운다 — 출석률 공식은 서버만 아는 규칙이라 클라이언트가
/// 값을 바꿀 자리가 아니다(조정자 판정: 서버 정밀도를 보존한다). 정수로
/// 떨어지는 값에 ".0"이 붙지 않게 하는 것만 따로 처리한다 — Figma 목업의
/// "94"가 그 경우다.
@visibleForTesting
String formatAttendanceRate(double rate) =>
    rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : '$rate';

/// Figma `353:2299` "출석률". 홈 화면의 같은 이름 카드와 달리 진행 막대가
/// 없고, 라벨이 "이번 달 출석률"이며, 아이콘이 왼쪽 열 위에 온다.
class _RateCard extends StatelessWidget {
  const _RateCard({required this.rate, required this.label});

  /// 서버가 준 `attendanceRate`를 **그대로** 쓴다. `records[]`를 세어 다시
  /// 계산하지 않는다 — 출석률 공식은 가입 이전 세션을 분모에서 빼는 등
  /// 서버만 아는 규칙을 포함한다(명세서).
  final double? rate;

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return AppCard(
      borderRadius: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _CardLabel(
            iconAsset: 'assets/icons/calendar-check-line.svg',
            iconColor: colors.main,
            label: label,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                rate == null ? '-' : formatAttendanceRate(rate!),
                style: typography.number1.copyWith(color: colors.gray3),
              ),
              const SizedBox(width: 4),
              // Figma는 "%"를 23px SemiBold로 그렸다 — 토큰에 없는 크기라
              // 가장 가까운 기존 토큰(title3, 24px)으로 대체했다(홈 화면과
              // 같은 판단).
              Text('%', style: typography.title3.copyWith(color: colors.gray3)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Figma `353:2307`/`353:2313` — 지각·결석 횟수 카드.
class _CountCard extends StatelessWidget {
  const _CountCard({
    required this.iconAsset,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final String iconAsset;
  final Color iconColor;
  final String label;

  /// 응답의 `status` 집계를 그대로 쓴다 — `records[]`를 세지 않는다.
  final int? value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return AppCard(
      borderRadius: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _CardLabel(iconAsset: iconAsset, iconColor: iconColor, label: label),
          Text(
            value == null ? '-' : '$value',
            style: typography.number1.copyWith(color: colors.gray3),
          ),
        ],
      ),
    );
  }
}

/// 카드 왼쪽 열 — 아이콘 위, 설명 아래(간격 10, Figma 실측).
class _CardLabel extends StatelessWidget {
  const _CardLabel({required this.iconAsset, required this.iconColor, required this.label});

  final String iconAsset;
  final Color iconColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Figma에서 출석률 카드의 아이콘만 20×20으로 잡혀 있지만(`353:2302`),
        // 그건 여백 없이 20 격자에 꽉 채워 그린 별도 export다 — 잉크 크기는
        // 24 격자에 2px 여백을 두고 그린 이 에셋을 24로 그릴 때와 똑같이
        // 20이다. 그래서 세 카드 모두 24로 그린다.
        SvgPicture.asset(
          iconAsset,
          width: 24,
          height: 24,
          colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
        ),
        const SizedBox(height: 10),
        Text(label, style: typography.body2.copyWith(color: colors.gray2)),
      ],
    );
  }
}
