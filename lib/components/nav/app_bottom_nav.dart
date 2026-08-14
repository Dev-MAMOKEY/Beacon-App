import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// 하단 탭 바(`363:1811`)의 탭 4개. 각 값의 `branchIndex`는
/// `StatefulShellRoute`의 브랜치 인덱스(`AppTab`)와 반드시 일치해야 한다.
/// (내장 `Enum.index`와 이름이 겹치지 않도록 `branchIndex`로 부른다 —
/// 우연히 선언 순서와 값이 같더라도 의미가 다르다.)
enum _NavTab {
  home(branchIndex: 0, label: '홈'),
  records(branchIndex: 1, label: '기록'),
  admin(branchIndex: 2, label: '관리자'),
  profile(branchIndex: 3, label: '마이');

  const _NavTab({required this.branchIndex, required this.label});

  final int branchIndex;
  final String label;
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

    final visibleTabs = _NavTab.values.where((tab) => showAdmin || tab != _NavTab.admin);

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
                selected: tab.branchIndex == currentIndex,
                onTap: () => onTap(tab.branchIndex),
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

  final _NavTab tab;
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
      label: tab.label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Figma가 내보낸 실제 SVG 아이콘을 아직 구하지 못해(이 태스크
            // 진행 중 접근 가능한 Figma 파일 URL/키를 찾지 못했다) 자리만
            // 예약해 둔다. 손으로 벡터를 그리거나 비슷한 아이콘으로
            // 대체하지 않는다 — 실제 에셋이 확보되면 이 SizedBox를
            // `SvgPicture.asset`으로 교체한다.
            SizedBox(
              width: 24,
              height: 24,
              child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: tint))),
            ),
            const SizedBox(height: 8),
            Text(tab.label, style: typography.body3.copyWith(color: tint)),
          ],
        ),
      ),
    );
  }
}
