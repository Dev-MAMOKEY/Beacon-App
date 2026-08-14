import 'package:flutter/material.dart';

import '../../../components/ui/button.dart';
import '../../../components/ui/popup.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../data/attendance_dto.dart';

/// 출석 완료 표시(명세서 17-6)를 홈 화면 위에 덮는 팝업으로 띄운다.
/// 전용 라우트를 만들지 않는다 — 탭 셸 안이라 라우트를 추가하면 탭
/// 스택이 지저분해진다(브리핑 5-1). [onConfirm]은 팝업이 닫힌 뒤
/// 정확히 한 번 불린다.
///
/// Figma 실측(`339:1705` "출석완료 팝업창", 파일 `O9RRQnJwoqsjU8LrJKeaAX`) —
/// 바텀시트가 아니라 네 모서리가 모두 둥근 화면 중앙 카드였다. 최초
/// 구현이 프로즈 브리핑만 보고 바텀시트로 지었던 것을 이 팝업 프리미티브
/// (`showAppPopup`)로 바꿨다.
Future<void> showAttendanceSuccessSheet(
  BuildContext context, {
  required AttendanceStatus status,
  required DateTime checkedAt,
  required String sessionName,
}) {
  return showAppPopup<void>(
    context: context,
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

  // present의 "출석 완료!"는 Figma(339:1708) 문구 그대로(느낌표 포함)다.
  // late는 Figma에 해당 상태의 팝업이 없어(이 파일이 실측한 프레임은
  // present 하나뿐이다) 명세서 문구를 그대로 유지했다 — 느낌표를 임의로
  // 붙이지 않았다.
  String get _statusText => switch (widget.status) {
    AttendanceStatus.late => '지각 처리되었습니다',
    AttendanceStatus.present => '출석 완료!',
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

    // Figma의 실제 팝업(339:1705)은 제목 텍스트 하나와 버튼 하나뿐이다 —
    // 체크 아이콘·처리 시각·세션 이름이 없다. 하지만 이 세 가지는
    // 명세서 17-6이 "표시 요소"로 명시한 항목이라(프로즈가 아니라 스펙
    // 문서 자체의 요구), 정보 완결성은 스펙을 따르고 시각 스타일(카드
    // 모양·제목 타이포)만 Figma를 따랐다 — 조정자 확인 대기, 리포트 참고.
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
        // Figma 실측 스타일: title4(20px SemiBold, tracking 0.25) — 이전
        // 구현은 title3(24px)를 썼다.
        Text(_statusText, style: typography.title4.copyWith(color: colors.gray3)),
        const SizedBox(height: 8),
        Text(
          '$_formattedCheckedAt · ${widget.sessionName}',
          style: typography.body3.copyWith(color: colors.gray2),
        ),
        const SizedBox(height: 24),
        AppButton(label: '확인', onPressed: widget.onConfirm),
      ],
    );
  }
}
