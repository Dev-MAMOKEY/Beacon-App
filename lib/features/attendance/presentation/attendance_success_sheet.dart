import 'package:flutter/material.dart';

import '../../../components/ui/button.dart';
import '../../../components/ui/popup.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../data/attendance_dto.dart';

/// 출석 완료 표시를 홈 화면 위에 덮는 팝업(다이얼로그 라우트)으로 만든다.
/// go_router에 전용 라우트를 만들지는 않는다 — 탭 셸 안이라 라우트를
/// 추가하면 탭 스택이 지저분해진다(브리핑 5-1).
///
/// Figma `339:1705`("출석완료 팝업창", 파일 `O9RRQnJwoqsjU8LrJKeaAX`)를
/// 그대로 따른다 — 제목 텍스트 하나와 버튼 하나뿐이다. 체크 아이콘·처리
/// 시각·세션 이름은 없다.
///
/// 기능명세서 17-6은 이 세 가지를 "표시 요소"로 명시하지만, 조정자가 이
/// 화면에 한해 Figma를 명세서보다 우선하기로 결정했다 — 오버사이트가
/// 아니라 의도적 예외다(이슈 #11 `## 범위 → ### 제외` 참고). 처리 시각과
/// 세션 이름이 필요하면 기록 화면(#12)에서 어떤 세션으로 출석 처리됐는지
/// 확인할 수 있다.
///
/// `show...` 헬퍼가 아니라 라우트를 돌려주는 이유: 이 팝업도 홈 화면이
/// 라우트 객체로 **소유**해야 한다. 홈이 트리에서 빠지거나(로그아웃 등) 홈
/// 탭이 숨겨지면 이 팝업도 함께 닫아야 하는데, `Future`만 들고 있으면 닫을
/// 방법이 `Navigator.pop()`(=스택 맨 위)뿐이라 정체성이 없다(리뷰
/// Important 6).
Route<void> buildAttendanceSuccessRoute(
  BuildContext context, {
  required NavigatorState navigator,
  required AttendanceStatus status,
}) {
  return buildAppPopupRoute<void>(
    context: context,
    navigator: navigator,
    builder: (context) => AttendanceSuccessSheetContent(
      status: status,
      // 이 팝업은 push된 직후 항상 스택 맨 위다(코드 입력 팝업은 그 전에
      // 닫힌다) — 사용자가 누르는 확인은 되감기 애니메이션이 보여야 하므로
      // 즉시 제거(removeRoute)가 아니라 pop을 쓴다.
      onConfirm: () => Navigator.of(context).pop(),
    ),
  );
}

/// 지각 판정은 서버가 `lateThresholdMinutes`로 정한다 — 여기서는 서버가
/// 돌려준 [status] 값을 그대로 문구로 옮길 뿐, 클라이언트에서 다시
/// 계산하지 않는다.
@visibleForTesting
class AttendanceSuccessSheetContent extends StatelessWidget {
  const AttendanceSuccessSheetContent({super.key, required this.status, required this.onConfirm});

  final AttendanceStatus status;
  final VoidCallback onConfirm;

  // present의 "출석 완료!"는 Figma(339:1708) 문구 그대로(느낌표 포함)다.
  // late는 Figma에 해당 상태의 팝업이 없어(이 파일이 실측한 프레임은
  // present 하나뿐이다) 명세서 문구를 그대로 유지했다 — 느낌표를 임의로
  // 붙이지 않았다.
  String get _statusText => switch (status) {
    AttendanceStatus.late => '지각 처리되었습니다',
    AttendanceStatus.present => '출석 완료!',
    // 성공 응답으로는 나타나지 않는 값이지만, 방어적으로 문구를 채워둔다.
    AttendanceStatus.absent => '결석 처리되었습니다',
    AttendanceStatus.etc => '출석 처리되었습니다',
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_statusText, style: typography.title4.copyWith(color: colors.gray3)),
        const SizedBox(height: 24),
        AppButton(label: '확인', onPressed: onConfirm),
      ],
    );
  }
}
