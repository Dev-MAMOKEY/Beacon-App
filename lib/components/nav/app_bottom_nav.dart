import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/router/app_router.dart' show AppTab;
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// `AppTab`(라우터가 정의한 브랜치 순서)을 그대로 쓴다 — 예전에는 같은
/// 4방향 순서를 인코딩하는 `_NavTab` enum을 따로 두고 문서 주석으로만
/// 동기화를 맞췄는데, 그건 둘 중 하나만 순서를 바꿔도 컴파일 에러 없이
/// "마이"를 누르면 관리자 화면이 열리는 종류의 조용한 버그를 만든다.
extension on AppTab {
  String get _label => switch (this) {
    AppTab.home => '홈',
    AppTab.records => '기록',
    AppTab.admin => '관리자',
    AppTab.profile => '마이',
  };

  String get _iconAsset => switch (this) {
    AppTab.home => 'assets/icons/nav_home.svg',
    AppTab.records => 'assets/icons/nav_records.svg',
    AppTab.admin => 'assets/icons/nav_admin.svg',
    AppTab.profile => 'assets/icons/nav_profile.svg',
  };
}

/// 하단 탭 바. Figma(`363:1811`) 값: 배경 `white`, 상단 모서리 반경 `20`,
/// `padding: top 14, bottom 30, horizontal 44`, 아이콘 24×24, 아이콘-라벨
/// 간격 `8`, 라벨 `body3`, 선택 `main` / 미선택 `gray1`.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.showAdmin,
  });

  /// 현재 선택된 탭의 브랜치 인덱스(`AppTab.index`와 동일한 체계).
  final int currentIndex;

  /// 탭이 눌렸을 때 그 탭의 브랜치 인덱스를 돌려준다.
  final ValueChanged<int> onTap;

  /// false면 관리자 탭 자체를 렌더하지 않는다 — role을 아직 조회하지
  /// 않는 이번 단계에서는 항상 false로 들어온다(이슈 #34).
  final bool showAdmin;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    final visibleTabs = AppTab.values.where((tab) => showAdmin || tab != AppTab.admin);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(top: 14, bottom: 30, left: 44, right: 44),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final tab in visibleTabs)
              _NavItem(
                tab: tab,
                selected: tab.index == currentIndex,
                onTap: () => onTap(tab.index),
                colors: colors,
                typography: typography,
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.selected,
    required this.onTap,
    required this.colors,
    required this.typography,
  });

  final AppTab tab;
  final bool selected;
  final VoidCallback onTap;
  final AppColors colors;
  final AppTypography typography;

  @override
  Widget build(BuildContext context) {
    final tint = selected ? colors.main : colors.gray1;

    return Semantics(
      button: true,
      selected: selected,
      label: tab._label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              tab._iconAsset,
              width: 24,
              height: 24,
              colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
            ),
            const SizedBox(height: 8),
            Text(tab._label, style: typography.body3.copyWith(color: tint)),
          ],
        ),
      ),
    );
  }
}
