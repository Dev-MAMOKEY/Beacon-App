import 'package:flutter/material.dart';

import '../../../components/ui/button.dart';
import '../../../components/ui/sheet.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../data/attendance_dto.dart';

/// 출석 완료 표시(명세서 17-6)를 홈 화면 위에 덮는 바텀시트로 띄운다.
/// 전용 라우트를 만들지 않는다 — 탭 셸 안이라 라우트를 추가하면 탭
/// 스택이 지저분해진다(브리핑 5-1). [onConfirm]은 시트가 닫힌 뒤
/// 정확히 한 번 불린다.
Future<void> showAttendanceSuccessSheet(
  BuildContext context, {
  required AttendanceStatus status,
  required DateTime checkedAt,
  required String sessionName,
}) {
  return showAppSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (context) => AttendanceSuccessSheetContent(
      status: status,
      checkedAt: checkedAt,
      sessionName: sessionName,
      onConfirm: () => Navigator.of(context).pop(),
    ),
  );
}

/// 지각 판정은 서버가 `lateThresholdMinutes`로 정한다 — 여기서는 서버가
/// 돌려준 [status] 값을 그대로 문구로 옮길 뿐, 클라이언트에서 다시
/// 계산하지 않는다.
@visibleForTesting
class AttendanceSuccessSheetContent extends StatefulWidget {
  const AttendanceSuccessSheetContent({
    super.key,
    required this.status,
    required this.checkedAt,
    required this.sessionName,
    required this.onConfirm,
  });

  final AttendanceStatus status;
  final DateTime checkedAt;
  final String sessionName;
  final VoidCallback onConfirm;

  @override
  State<AttendanceSuccessSheetContent> createState() =>
      _AttendanceSuccessSheetContentState();
}

class _AttendanceSuccessSheetContentState extends State<AttendanceSuccessSheetContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _iconController;

  @override
  void initState() {
    super.initState();
    _iconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..forward();
  }

  @override
  void dispose() {
    _iconController.dispose();
    super.dispose();
  }

  String get _statusText => switch (widget.status) {
    AttendanceStatus.late => '지각 처리되었습니다',
    AttendanceStatus.present => '출석 완료',
    // 성공 응답으로는 나타나지 않는 값이지만, 방어적으로 문구를 채워둔다.
    AttendanceStatus.absent => '결석 처리되었습니다',
    AttendanceStatus.etc => '출석 처리되었습니다',
  };

  String get _formattedCheckedAt {
    final local = widget.checkedAt.toLocal();
    final isAm = local.hour < 12;
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return '${isAm ? '오전' : '오후'} $hour12:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScaleTransition(
          scale: CurvedAnimation(parent: _iconController, curve: Curves.elasticOut),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(shape: BoxShape.circle, color: colors.green),
            child: Icon(Icons.check, color: colors.white, size: 40),
          ),
        ),
        const SizedBox(height: 20),
        Text(_statusText, style: typography.title3.copyWith(color: colors.gray3)),
        const SizedBox(height: 8),
        Text(
          '$_formattedCheckedAt · ${widget.sessionName}',
          style: typography.body3.copyWith(color: colors.gray2),
        ),
        const SizedBox(height: 32),
        AppButton(label: '확인', onPressed: widget.onConfirm),
      ],
    );
  }
}
