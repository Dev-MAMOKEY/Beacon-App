import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// 화면 중앙에 뜨는 카드형 팝업의 공통 뼈대 — 흰 배경, 네 모서리 모두 32
/// 반경, 32 패딩(Figma `339:1683`·`339:1705` 실측). `lib/components/ui/sheet.dart`
/// (바텀시트, 아래쪽 두 모서리만 둥긂)와는 다른 시각 계열이다 — 이
/// 프로젝트의 "팝업창"은 화면 중앙에 뜨는 카드이지 바텀시트가 아니었다.
/// `showAppPopup`(다이얼로그 라우트)이 이 카드를 감싸 띄운다 — 예전에는
/// 화면에 직접 얹는 `Positioned.fill` 오버레이로도 같은 카드를 재사용한
/// 적이 있었지만(출석코드 입력·블루투스 꺼짐 팝업), 그 방식은 팝업의
/// 스크림이 그 화면 안에서만 그려져 하단 탭 셸(`AppShell`의 상단 바·하단
/// 탭 바)을 덮지 못하고 탭도 그대로 눌리는 버그였다 — 지금은 모든 팝업이
/// 다이얼로그 라우트를 통해서만 뜬다.
class AppPopupCard extends StatelessWidget {
  const AppPopupCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    return Material(
      color: colors.white,
      borderRadius: BorderRadius.circular(32),
      child: Padding(padding: const EdgeInsets.all(32), child: child),
    );
  }
}

/// 이 앱의 팝업이 항상 붙어야 하는 내비게이터 — 루트다. 출석코드 입력·
/// 블루투스 꺼짐 팝업이 인라인 `Positioned.fill` 오버레이였을 때는 그
/// 스크림이 홈 화면(하단 탭 셸의 중첩 네비게이터 안)에서만 그려져
/// `AppShell`의 상단 바·하단 탭 바를 덮지 못하고 탭도 그대로 눌리는
/// 버그였다. 중첩 네비게이터에 붙으면 같은 버그로 돌아간다.
NavigatorState appPopupNavigatorOf(BuildContext context) =>
    Navigator.of(context, rootNavigator: true);

/// [AppPopupCard]를 담은 다이얼로그 **라우트**를 만든다(push는 하지 않는다).
///
/// `showDialog`를 쓰지 않고 라우트를 직접 만들어 돌려주는 이유: 상태 기반
/// 팝업(출석코드 입력·블루투스 꺼짐)은 조건이 거짓이 되면 **자기가 띄운 바로
/// 그 라우트**를 닫아야 하는데, `showDialog`는 `Future`만 돌려주고 자기가
/// 만든 `Route`는 감춘다. 그래서 호출자에게 남는 유일한 닫기 수단이
/// `Navigator.pop()`(=스택 맨 위를 닫는다)이고, 그 위에 다른 루트 라우트가
/// 얹혀 있으면 엉뚱한 것을 닫는다. 라우트 객체를 들고 있으면
/// `Navigator.removeRoute(route)`로 정확히 그것만 닫을 수 있고, 완료
/// 콜백에서도 "지금 추적 중인 그 라우트가 맞는가"를 `identical`로 판정할 수
/// 있다.
///
/// [DialogRoute]는 `showDialog`가 내부적으로 쓰는 바로 그 라우트라
/// 배리어·전환 애니메이션·`SafeArea`·테마 캡처는 그대로 얻는다.
DialogRoute<T> buildAppPopupRoute<T>({
  required BuildContext context,
  required NavigatorState navigator,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
}) {
  return DialogRoute<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    // 스크림도 색이다 — `lib/core/theme/` 밖에서 `Colors.black`을 직접 쓰지
    // 않는다(`AppColors.scrim`).
    barrierColor: Theme.of(context).extension<AppColors>()!.scrim,
    // 호출자 컨텍스트의 InheritedTheme(테마와 그 확장 포함)을 루트
    // 내비게이터 아래로 옮겨 담는다 — `showDialog`가 하는 것과 같다.
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    builder: (context) => Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: AppPopupCard(child: Builder(builder: builder)),
      ),
    ),
  );
}
