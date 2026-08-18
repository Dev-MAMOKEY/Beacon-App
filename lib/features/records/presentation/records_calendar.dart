import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../attendance/data/attendance_dto.dart';
import '../data/records_dto.dart';

/// 그 달 1일이 들어갈 칸의 인덱스(0 = 일요일 칸). **일요일 시작**이다.
///
/// Dart의 `DateTime.weekday`는 월=1 … 일=7이라 `% 7`이 그대로 일요일 시작
/// 오프셋이 된다(일: 7 % 7 = 0, 월: 1, … 토: 6).
int firstDayOffset(int year, int month) => DateTime(year, month, 1).weekday % 7;

/// 그 달의 마지막 날. `DateTime(year, month + 1, 0)`은 다음 달 0일 = 이 달의
/// 마지막 날로 정규화된다(month == 12여도 연도 넘김까지 알아서 처리한다).
int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// 하루에 세션이 여러 개면 배지 색은 하나뿐이라 그중 하나를 골라야 한다.
///
/// **Figma에도 명세서에도 이 경우의 규칙이 없다.** 눈에 띄어야 하는 쪽이
/// 이기도록 결석 > 지각 > 기타 > 출석 순으로 정했다 — 같은 날 결석 하나와
/// 출석 하나가 있는데 "출석"으로 칠해 버리면 사용자가 결석을 영영 못 본다.
/// 개별 세션의 실제 상태는 날짜를 탭했을 때 뜨는 시트가 전부 보여준다.
AttendanceStatus mostSevereStatus(Iterable<AttendanceStatus> statuses) {
  const priority = <AttendanceStatus, int>{
    AttendanceStatus.absent: 3,
    AttendanceStatus.late: 2,
    AttendanceStatus.etc: 1,
    AttendanceStatus.present: 0,
  };
  return statuses.reduce((a, b) => priority[a]! >= priority[b]! ? a : b);
}

/// 출석 상태 → 배지 배경색. Figma "날짜" 컴포넌트(`289:2875`)의 variant와
/// 1:1로 대응한다. 소진 switch라 상태가 하나 늘면 컴파일 타임에 잡힌다.
Color attendanceBadgeColor(AppColors colors, AttendanceStatus status) => switch (status) {
  AttendanceStatus.present => colors.attendancePresent,
  AttendanceStatus.late => colors.attendanceLate,
  AttendanceStatus.absent => colors.attendanceAbsent,
  AttendanceStatus.etc => colors.attendanceEtc,
};

/// Figma "날짜" 컴포넌트(`289:2875`) — 반경 16, 16px SemiBold 검정 글자.
/// [background]가 null이면 variant "기본"(`289:2882`)으로, 배경 없이 글자만
/// 그린다. 캘린더에서는 "그 날짜에 기록이 없음"이 그 상태다.
///
/// [padding]의 기본값 10은 컴포넌트를 **혼자** 뒀을 때의 고유 크기(48×39)를
/// 만드는 Figma의 `p-[10px]`다. 캘린더 그리드 안에서는 셀이 늘어나
/// (`justify-self-stretch` + `self-stretch`) 패딩이 크기를 결정하지 않으므로
/// 그리드 셀은 [EdgeInsets.zero]를 넘긴다.
class AttendanceDateBadge extends StatelessWidget {
  const AttendanceDateBadge({
    super.key,
    required this.label,
    this.background,
    this.padding = const EdgeInsets.all(10),
  });

  final String label;
  final Color? background;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        // Figma는 이 글자를 검정으로 그렸다 — gray3가 아니다(`289:2877`의
        // fill은 #000000). `AppColors.label`이 그 검정이다.
        child: Text(label, style: typography.title6.copyWith(color: colors.label)),
      ),
    );
  }
}

/// 기록 화면의 달력 카드(Figma `384:1815`).
///
/// 이 위젯은 상태를 갖지 않는다 — 어떤 달을 보여줄지도, 그 달의 기록도
/// 전부 밖(`RecordsScreen`)에서 받는다. 월 이동 버튼은 콜백만 쏜다.
class RecordsCalendar extends StatelessWidget {
  const RecordsCalendar({
    super.key,
    required this.year,
    required this.month,
    required this.recordsByDay,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onDayTap,
  });

  final int year;
  final int month;

  /// 일(1~31) → 그 날의 기록들. 비어 있는 날짜는 키 자체가 없다.
  final Map<int, List<AttendanceRecordItem>> recordsByDay;

  final VoidCallback onPreviousMonth;

  /// null이면 다음 달 화살표가 비활성이다 — 이번 달에서는 미래로 갈 수 없다.
  final VoidCallback? onNextMonth;

  final ValueChanged<int> onDayTap;

  /// Figma `384:1832` 실측 — 날짜 그리드는 높이 200에 5행, 행 간격 8이라
  /// 한 행이 (200 - 4 × 8) / 5 = 33.6이다. 6주짜리 달은 이 높이를 유지한 채
  /// 행이 하나 늘어난다(Figma의 10월 목업이 우연히 5행이었을 뿐이다).
  static const double _rowHeight = 33.6;

  /// Figma `384:1824`/`384:1832` 실측 — 열 간격·행 간격 모두 8.
  static const double _gap = 8;

  /// 요일 머리글은 `self-start`라 늘어나지 않고 고유 높이(39)를 유지한다
  /// (Figma "날짜" 컴포넌트의 고유 크기 48×39).
  static const double _weekdayRowHeight = 39;

  static const List<String> _weekdayLabels = ['일', '월', '화', '수', '목', '금', '토'];

  @override
  Widget build(BuildContext context) {
    final offset = firstDayOffset(year, month);
    final dayCount = daysInMonth(year, month);
    final rowCount = ((offset + dayCount) / 7).ceil();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).extension<AppColors>()!.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          _MonthSelector(
            year: year,
            month: month,
            onPrevious: onPreviousMonth,
            onNext: onNextMonth,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: _weekdayRowHeight,
            child: _GridRow(
              gap: _gap,
              children: [
                for (final label in _weekdayLabels)
                  AttendanceDateBadge(label: label, padding: EdgeInsets.zero),
              ],
            ),
          ),
          const SizedBox(height: _gap),
          for (var row = 0; row < rowCount; row++) ...[
            if (row > 0) const SizedBox(height: _gap),
            SizedBox(
              height: _rowHeight,
              child: _GridRow(
                gap: _gap,
                children: [
                  for (var column = 0; column < 7; column++)
                    _buildCell(context, row * 7 + column - offset + 1, dayCount),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCell(BuildContext context, int day, int dayCount) {
    if (day < 1 || day > dayCount) return const SizedBox.shrink();

    final colors = Theme.of(context).extension<AppColors>()!;
    final records = recordsByDay[day];
    final background = records == null || records.isEmpty
        ? null
        : attendanceBadgeColor(colors, mostSevereStatus(records.map((r) => r.status)));

    return GestureDetector(
      // 기록이 없는 날짜는 탭해도 아무 일도 없어야 한다 — 콜백 자체를 주지
      // 않는다. `onDayTap`을 항상 연결해 두고 화면 쪽에서 "기록 없으면
      // return"으로 막으면, 그 가드를 지워도 빈 시트가 뜰 뿐 테스트가
      // 눈치채지 못하는 구현이 되기 쉽다.
      onTap: background == null ? null : () => onDayTap(day),
      // 배경이 없는(투명한) 셀도 탭 판정을 받아야 "기록 없는 날짜를 탭해도
      // 아무 일 없다"를 실제로 탭해서 확인할 수 있다.
      behavior: HitTestBehavior.opaque,
      child: AttendanceDateBadge(
        label: '$day',
        background: background,
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// 7칸 균등 분할 + 칸 사이 간격. Figma의 `grid-cols-[repeat(7,minmax(0,1fr))]`
/// `gap-x-[8px]`에 해당한다.
class _GridRow extends StatelessWidget {
  const _GridRow({required this.children, required this.gap});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

/// Figma `384:1816` "Month Selector" — 좌우 화살표와 "2026. 10" 제목.
class _MonthSelector extends StatelessWidget {
  const _MonthSelector({
    required this.year,
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  final int year;
  final int month;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _ArrowButton(
          onPressed: onPrevious,
          semanticLabel: '이전 달',
        ),
        Text(
          // Figma(`384:1820`)에 있는 값은 "2026. 10" 하나뿐이라 한 자리 달의
          // 표기는 디자인에 없다. 이 앱이 이미 쓰는 관례(홈 화면의
          // "YYYY년 MM월 DD일")를 따라 2자리로 채운다.
          '$year. ${month.toString().padLeft(2, '0')}',
          style: typography.title4.copyWith(color: colors.gray3),
        ),
        _ArrowButton(
          onPressed: onNext,
          semanticLabel: '다음 달',
          // Figma에서 오른쪽 화살표는 같은 `arrow-left-s-line`을 좌우로
          // 뒤집은 것이다(`-scale-y-100` + `rotate-180` = 수평 반전).
          flipped: true,
        ),
      ],
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.onPressed,
    required this.semanticLabel,
    this.flipped = false,
  });

  final VoidCallback? onPressed;
  final String semanticLabel;
  final bool flipped;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    // Figma에는 비활성 상태의 화살표가 없다 — 이번 달에서 다음 달로 갈 수
    // 없다는 요구는 디자인이 아니라 명세에서 온다. 다른 화면에서 비활성
    // 요소에 쓰는 gray1을 그대로 쓴다.
    final color = onPressed == null ? colors.gray1 : colors.main;

    final icon = SvgPicture.asset(
      'assets/icons/arrow-left-s-line.svg',
      width: 24,
      height: 24,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );

    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: flipped
            ? Transform.flip(flipX: true, child: icon)
            : icon,
      ),
    );
  }
}
