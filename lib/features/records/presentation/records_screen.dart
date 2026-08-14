import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../components/ui/card.dart';
import '../../../components/ui/sheet.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
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
  Route<void>? _sheetRoute;

  /// `dispose()` 시점에는 이 화면의 엘리먼트가 트리에서 빠지는 중이라
  /// `Navigator.of(context)`를 신뢰할 수 없다 — 미리 잡아 둔다.
  late final NavigatorState _rootNavigator;

  @override
  void initState() {
    super.initState();
    final now = widget.clock();
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
      _closeSheet();
    }
  }

  @override
  void dispose() {
    // 이 시점 이후에 도착하는 모든 조회 완료를 무효화한다.
    _loadGeneration++;
    _closeSheet();
    super.dispose();
  }

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
      if (!_isCurrentLoad(generation)) return;
      setState(() => _records = null);
      return;
    }
    // 늦게 도착한 옛 달의 응답이 현재 달을 덮어쓰지 않게 한다.
    if (!_isCurrentLoad(generation)) return;
    setState(() => _records = records);
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

  /// 이번 달(=[RecordsScreen.clock]의 달)보다 앞선 달을 보고 있을 때만 다음
  /// 달로 갈 수 있다. 미래 월은 조회 대상이 아니다.
  bool get _canGoNext {
    final now = widget.clock();
    return _year * 12 + _month < now.year * 12 + now.month;
  }

  Map<int, List<AttendanceRecordItem>> get _recordsByDay {
    final byDay = <int, List<AttendanceRecordItem>>{};
    for (final record in _records?.records ?? const <AttendanceRecordItem>[]) {
      // 서버가 준 날짜가 지금 보고 있는 달이 아니면 캘린더에 얹지 않는다 —
      // 그러지 않으면 다른 달의 1일이 이 달의 1일 칸을 칠한다.
      if (record.date.year != _year || record.date.month != _month) continue;
      (byDay[record.date.day] ??= []).add(record);
    }
    return byDay;
  }

  void _openSheet(int day) {
    final records = _recordsByDay[day];
    // 기록이 없으면 아예 열지 않는다. `RecordsCalendar`가 이미 탭을 막지만,
    // 그 가드 하나에만 기대지 않는다.
    if (records == null || records.isEmpty) return;

    final route = buildAppSheetRoute<void>(
      context: context,
      navigator: _rootNavigator,
      builder: (context) => SessionDetailSheetContent(
        date: DateTime(_year, _month, day),
        records: records,
      ),
    );
    _sheetRoute = route;
    unawaited(
      _rootNavigator.push<void>(route).then((_) {
        // 이미 다른 시트로 바뀐 뒤에 도착한 옛 시트의 완료가 현재 추적을
        // 지우지 않도록 정체성으로 판정한다(`home_screen.dart`와 같은 이유).
        if (identical(_sheetRoute, route)) _sheetRoute = null;
      }),
    );
  }

  void _closeSheet() {
    final route = _sheetRoute;
    _sheetRoute = null;
    if (route != null && route.isActive) _rootNavigator.removeRoute(route);
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
      _loadedClubId = session.clubId;
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
              _SummaryCards(records: _records),
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
  const _SummaryCards({required this.records});

  final MonthlyRecords? records;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final r = records;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RateCard(rate: r?.attendanceRate),
        const SizedBox(height: 10),
        _CountCard(
          iconAsset: 'assets/icons/time-line.svg',
          iconColor: colors.yellow,
          // Figma `353:2311` 문구 그대로. 지난 달을 보고 있어도 "이번 달"로
          // 남는다 — 디자인에 다른 상태가 없다(보고서에 적어 조정자 판정을
          // 받는다).
          label: '이번 달 지각 횟수',
          value: r?.late,
        ),
        const SizedBox(height: 10),
        _CountCard(
          iconAsset: 'assets/icons/error-warning-line.svg',
          iconColor: colors.red,
          label: '이번 달 결석 횟수',
          value: r?.absent,
        ),
      ],
    );
  }
}

/// Figma `353:2299` "출석률". 홈 화면의 같은 이름 카드와 달리 진행 막대가
/// 없고, 라벨이 "이번 달 출석률"이며, 아이콘이 왼쪽 열 위에 온다.
class _RateCard extends StatelessWidget {
  const _RateCard({required this.rate});

  /// 서버가 준 `attendanceRate`를 **그대로** 쓴다. `records[]`를 세어 다시
  /// 계산하지 않는다 — 출석률 공식은 가입 이전 세션을 분모에서 빼는 등
  /// 서버만 아는 규칙을 포함한다(명세서).
  final double? rate;

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
            label: '이번 달 출석률',
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                rate == null ? '-' : rate!.toStringAsFixed(0),
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
