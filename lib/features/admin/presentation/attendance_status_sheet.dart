import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/time/kst.dart';
import '../../attendance/data/attendance_dto.dart';
import '../../records/presentation/records_calendar.dart' show attendanceBadgeColor;
import '../../records/presentation/session_detail_sheet.dart' show attendanceStatusLabel;
import '../data/attendance_admin_dto.dart';

/// 관리자 출석 현황.
///
/// **웹 디자인(`356:1800`)을 모바일로 옮긴 것이다.** 웹은 7열 표
/// (이름·학번·출석상태·체크인 시간·처리 여부·사유·상태 변경)인데 390px에는
/// 들어가지 않는다. 정보를 버리지 않고 재배치했다:
///
/// | 웹 열 | 모바일 |
/// |---|---|
/// | 이름·학번 | 행 왼쪽 위아래 |
/// | 출석상태 | 상태 배지(기록 화면과 같은 색·라벨) |
/// | 체크인 시간 | 행 오른쪽 |
/// | 처리 여부 | "수동" 라벨(자동은 표시하지 않는다 — 기본값이다) |
/// | 사유 | 상태 변경 팝업 안 |
/// | 상태 변경 | 행 전체를 탭 |
///
/// 상단 요약 4종은 웹과 같다. 서버가 집계를 주지 않아 목록에서 센다.
class AttendanceStatusSheetContent extends StatelessWidget {
  const AttendanceStatusSheetContent({
    super.key,
    required this.sessionName,
    required this.records,
    required this.onTapRecord,
    this.isLoading = false,
    this.loadFailed = false,
  });

  final String sessionName;
  final List<AdminAttendanceRecord> records;
  final ValueChanged<AdminAttendanceRecord> onTapRecord;
  final bool isLoading;
  final bool loadFailed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(sessionName, style: typography.title4.copyWith(color: colors.gray3)),
        const SizedBox(height: 4),
        Text('출석 현황', style: typography.body3.copyWith(color: colors.gray2)),
        const SizedBox(height: 20),
        if (isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (loadFailed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                '출석 현황을 불러오지 못했습니다',
                style: typography.body2.copyWith(color: colors.gray2),
              ),
            ),
          )
        else ...[
          _SummaryRow(summary: AttendanceSummary.of(records)),
          const SizedBox(height: 20),
          if (records.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  '아직 출석 기록이 없습니다',
                  style: typography.body2.copyWith(color: colors.gray2),
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: records.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: colors.gray4),
                itemBuilder: (context, index) => _AttendanceRow(
                  record: records[index],
                  onTap: () => onTapRecord(records[index]),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// 웹 상단의 요약 카드 4종(`356:1800`)을 모바일 폭에 맞춰 한 줄로.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.summary});

  final AttendanceSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    return Row(
      children: [
        for (final status in AttendanceStatus.values) ...[
          if (status != AttendanceStatus.present) const SizedBox(width: 8),
          Expanded(
            child: _SummaryCell(
              label: attendanceStatusLabel(status),
              count: summary.countOf(status),
              // 기록 화면과 같은 상태 색을 쓴다 — 같은 개념을 두 화면이 다른
              // 색으로 보여주면 사용자가 다른 것으로 읽는다.
              accent: attendanceBadgeColor(colors, status),
            ),
          ),
        ],
      ],
    );
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({required this.label, required this.count, required this.accent});

  final String label;
  final int count;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(label, style: typography.body4.copyWith(color: colors.gray2)),
          const SizedBox(height: 6),
          Text('$count', style: typography.title4.copyWith(color: accent)),
        ],
      ),
    );
  }
}

class _AttendanceRow extends StatelessWidget {
  const _AttendanceRow({required this.record, required this.onTap});

  final AdminAttendanceRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.memberName,
                    style: typography.body2.copyWith(color: colors.gray3),
                  ),
                  const SizedBox(height: 2),
                  Text(record.stdId, style: typography.body4.copyWith(color: colors.gray2)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    // "자동"은 표시하지 않는다 — 기본값이라 모든 행에 붙으면
                    // 정작 눈에 띄어야 할 "수동"이 묻힌다.
                    if (record.isManual) ...[
                      Text('수동', style: typography.body4.copyWith(color: colors.gray2)),
                      const SizedBox(width: 6),
                    ],
                    _StatusBadge(status: record.attendanceStatus),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  // 결석은 체크인 자체가 없다 — 0시로 표시하지 않는다.
                  record.checkedAt == null ? '-' : formatCheckInTime(record.checkedAt!),
                  style: typography.body4.copyWith(color: colors.gray2),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final AttendanceStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: attendanceBadgeColor(colors, status),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        attendanceStatusLabel(status),
        style: typography.body4.copyWith(color: colors.gray3),
      ),
    );
  }
}

/// 체크인 시각을 "6:20" 형태로 — 웹 표(`356:1800`)의 "체크인 시간" 열이
/// 그 형식이다(오전/오후 없는 **12시간제**).
///
/// KST로 읽는다 — 기기 시계를 그대로 쓰면 해외에 있는 관리자에게 체크인
/// 시각이 어긋나 보인다(#43이 홈 화면에서 고친 것과 같은 결함).
String formatCheckInTime(DateTime value) {
  final kst = toKst(value);
  // 정오·자정을 12시로 읽는다 — `% 12`만 쓰면 둘 다 0시가 된다.
  final hour = kst.hour % 12 == 0 ? 12 : kst.hour % 12;
  final minute = kst.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
