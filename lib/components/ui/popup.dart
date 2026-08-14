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

/// [AppPopupCard]를 다이얼로그 라우트로 띄운다. 확인을 누르면 스스로
/// 닫히는 일회성 팝업(출석 완료 등)과, 조건이 참인 동안 떠 있다가 조건이
/// 거짓이 되면 호출자가 직접 `Navigator.pop`으로 닫는 상태 기반 팝업
/// (출석코드 입력·블루투스 꺼짐, `home_screen.dart`) 둘 다 이 함수 하나로
/// 띄운다.
Future<T?> showAppPopup<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    // `showDialog`의 기본값이 이미 true라 동작 자체는 바뀌지 않지만,
    // 명시로 남긴다 — 출석코드 입력·블루투스 꺼짐 팝업이 인라인
    // `Positioned.fill` 오버레이였을 때는 홈 화면(하단 탭 셸의 중첩
    // 네비게이터 안)의 스크림만 그려져 상단 바·하단 탭 바를 덮지 못하고
    // 탭도 그대로 눌리는 버그였다. 이 값이 false로 바뀌면(또는 암묵적
    // 기본값이 나중에 바뀌면) 이 다이얼로그는 `context`가 속한 가장
    // 가까운(중첩) 네비게이터에 묶여 다시 같은 버그로 돌아간다 — 반드시
    // 루트 네비게이터(=`AppShell` 바깥, go_router의 최상위 라우트)에
    // 붙어야 상단 바·하단 탭 바 위로 뜬다.
    useRootNavigator: true,
    builder: (context) => Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: AppPopupCard(child: Builder(builder: builder)),
      ),
    ),
  );
}
