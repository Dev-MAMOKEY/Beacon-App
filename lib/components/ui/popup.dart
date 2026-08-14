import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// 화면 중앙에 뜨는 카드형 팝업의 공통 뼈대 — 흰 배경, 네 모서리 모두 32
/// 반경, 32 패딩(Figma `339:1683`·`339:1705` 실측). `lib/components/ui/sheet.dart`
/// (바텀시트, 아래쪽 두 모서리만 둥긂)와는 다른 시각 계열이다 — 이
/// 프로젝트의 "팝업창"은 화면 중앙에 뜨는 카드이지 바텀시트가 아니었다.
/// 다이얼로그 라우트(`showAppPopup`)와 화면에 직접 얹는 오버레이(Stack)
/// 양쪽에서 이 카드를 재사용한다.
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

/// [AppPopupCard]를 다이얼로그 라우트로 띄운다 — 확인을 누르면 스스로
/// 닫히는 일회성 팝업(출석 완료 등)에 쓴다. 조건이 참인 동안 계속 떠 있어야
/// 하는 팝업(출석코드 입력)은 라우트가 아니라 화면 트리에 직접 얹는
/// [AppPopupCard]를 쓴다 — 조건이 거짓이 되는 순간 별도의 팝 처리 없이
/// 그냥 사라져야 하기 때문이다.
Future<T?> showAppPopup<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (context) => Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: AppPopupCard(child: Builder(builder: builder)),
      ),
    ),
  );
}
