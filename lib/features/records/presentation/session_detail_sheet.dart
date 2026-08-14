import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../attendance/data/attendance_dto.dart';
import '../data/records_dto.dart';
import 'records_calendar.dart';

/// 상태 → 배지에 쓰는 한국어 라벨. Figma "날짜" 컴포넌트(`289:2875`)의
/// variant 이름(속성 1=출석/지각/결석)을 그대로 옮긴다. `etc`만 그 컴포넌트에
/// 대응하는 variant가 없어(네 번째 "기본"은 배경 없는 상태다) 명세서의
/// 이름 "기타"를 쓴다.
String attendanceStatusLabel(AttendanceStatus status) => switch (status) {
  AttendanceStatus.present => '출석',
  AttendanceStatus.late => '지각',
  AttendanceStatus.absent => '결석',
  AttendanceStatus.etc => '기타',
};

/// 날짜 셀을 탭했을 때 뜨는 바텀시트의 내용.
///
/// **이 시트에는 Figma 디자인이 없다.** 파일 `O9RRQnJwoqsjU8LrJKeaAX`의
/// "UI 디자인" 페이지 최상위 프레임을 전부 훑어 확인했다 — 모바일 쪽 시트는
/// 하나도 없고, `368:3709`("시트1")·`368:3797`("시트2")는 폭이 1075~1083인
/// 웹 대시보드 표 행이다. 그래서 이 화면은 기존 토큰과 이미 있는 프리미티브
/// (`AppSheet`, `AttendanceDateBadge`)만으로 조립했다 — 새 색·새 폰트 크기를
/// 만들지 않았다. 디자인이 나오면 이 위젯만 교체하면 된다.
class SessionDetailSheetContent extends StatelessWidget {
  const SessionDetailSheetContent({super.key, required this.date, required this.records});

  final DateTime date;

  /// 그 날짜의 세션 기록. 하루에 세션이 여러 개일 수 있다(그래서 목록이다).
  /// 비어 있는 채로 이 위젯이 만들어지는 일은 없어야 한다 — 기록이 없는
  /// 날짜는 애초에 탭이 안 먹는다(`RecordsCalendar`).
  final List<AttendanceRecordItem> records;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          // 홈 화면(`_formatTodayLabel`)이 Figma 실측으로 확정한 형식과 같다.
          '${date.year}년 ${date.month.toString().padLeft(2, '0')}월 '
          '${date.day.toString().padLeft(2, '0')}일',
          style: typography.title4.copyWith(color: colors.gray3),
        ),
        const SizedBox(height: 20),
        for (var i = 0; i < records.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          _SessionRow(record: records[i]),
        ],
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.record});

  final AttendanceRecordItem record;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;
    final checkedAt = record.checkedAt;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                record.sessionName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typography.body2.copyWith(color: colors.gray3),
              ),
              if (checkedAt != null) ...[
                const SizedBox(height: 6),
                Text(
                  // 서버가 준 처리 시각을 그대로 보여준다 — 지각 여부를 비롯한
                  // 판정은 서버가 이미 status에 담아 보냈다.
                  '${checkedAt.hour.toString().padLeft(2, '0')}:'
                  '${checkedAt.minute.toString().padLeft(2, '0')} 처리',
                  style: typography.body3.copyWith(color: colors.gray2),
                ),
              ],
              if (record.adminNote case final note? when note.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(note, style: typography.body3.copyWith(color: colors.gray2)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        AttendanceDateBadge(
          label: attendanceStatusLabel(record.status),
          background: attendanceBadgeColor(colors, record.status),
        ),
      ],
    );
  }
}
