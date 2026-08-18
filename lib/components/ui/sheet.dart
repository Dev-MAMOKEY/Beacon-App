import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// 바텀시트도 팝업과 같은 이유로 **루트** 내비게이터에 붙어야 한다 —
/// 중첩 내비게이터(하단 탭 셸 안)에 붙으면 스크림이 상단 바·하단 탭 바를
/// 덮지 못하고 탭이 그대로 눌린다(`popup.dart`의 `appPopupNavigatorOf` 주석
/// 참고 — 그 버그가 실제로 있었다).
NavigatorState appSheetNavigatorOf(BuildContext context) =>
    Navigator.of(context, rootNavigator: true);

/// [AppSheet]를 담은 바텀시트 **라우트**를 만든다(push는 하지 않는다).
///
/// [showAppSheet]가 아니라 이 함수가 필요한 이유는 `popup.dart`의
/// [buildAppPopupRoute]와 같다 — 화면이 자기가 띄운 시트를 **정체성으로**
/// 닫아야 하는 경우가 있다. 기록 화면은 탭이 숨겨지거나(`StatefulShellRoute.
/// indexedStack`은 브랜치를 dispose하지 않는다) 화면이 트리에서 빠질 때 자기
/// 시트를 닫아야 하는데, `showModalBottomSheet`는 `Future`만 돌려주고 자기가
/// 만든 `Route`는 감춘다. 그러면 남는 닫기 수단이 `Navigator.pop()`(=스택 맨
/// 위)뿐이라 엉뚱한 라우트를 닫을 수 있다.
ModalBottomSheetRoute<T> buildAppSheetRoute<T>({
  required BuildContext context,
  required NavigatorState navigator,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  final colors = Theme.of(context).extension<AppColors>()!;

  return ModalBottomSheetRoute<T>(
    // 내용이 길어지면(하루에 세션이 여럿인 날) 시트가 남은 높이를 다 쓰고 그
    // 안에서 스크롤해야 한다. `false`면 최대 높이가 화면의 9/16으로 묶여
    // `RenderFlex` 오버플로가 나고 뒤쪽 세션을 볼 방법이 아예 없다(리뷰
    // Important 5). 짧은 내용은 [AppSheet]의 `mainAxisSize: min`이 그대로
    // 내용 높이에 맞춰 주므로 이 값이 바뀌어도 달라지지 않는다.
    isScrollControlled: true,
    // 위로 늘어난 시트가 상태 바 밑으로 파고들지 않게 한다. 짧은 시트는
    // 화면 아래에 붙어 있으므로 영향이 없다.
    useSafeArea: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: colors.white,
    // 스크림도 색이다 — `lib/core/theme/` 밖에서 `Colors.black`을 직접 쓰지
    // 않는다(`AppColors.scrim`). `showModalBottomSheet`의 기본값은 하드코딩된
    // `Colors.black54`라 이 지정이 없으면 팝업과 스크림 농도가 달라진다.
    modalBarrierColor: colors.scrim,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(24),
        topRight: Radius.circular(24),
      ),
    ),
    // 호출자 컨텍스트의 InheritedTheme(테마와 그 확장 포함)을 루트
    // 내비게이터 아래로 옮겨 담는다 — `showModalBottomSheet`가 하는 것과 같다.
    capturedThemes: InheritedTheme.capture(from: context, to: navigator.context),
    builder: (context) => AppSheet(child: Builder(builder: builder)),
  );
}

/// 시트 본문을 감싸는 뼈대 — 상단 드래그 핸들과 안전 영역만 표준화한다.
class AppSheet extends StatelessWidget {
  const AppSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.gray4,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 20),
            // 내용이 남은 높이보다 길면 그 안에서 스크롤한다. 짧으면
            // `Flexible`(loose)이 아무 제약도 걸지 않아 시트가 내용 높이에
            // 딱 맞는다 — 즉 이 래핑은 넘칠 때만 눈에 보인다.
            Flexible(child: SingleChildScrollView(child: child)),
          ],
        ),
      ),
    );
  }
}
