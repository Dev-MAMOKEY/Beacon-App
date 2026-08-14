import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../components/nav/app_bottom_nav.dart';
import '../../../components/nav/app_top_bar.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';

/// `StatefulShellRoute.indexedStack`가 만드는 하단 탭 셸. 탭 4개(홈/기록/
/// 관리자/마이) 각각이 독립된 네비게이션 스택을 갖고, 탭을 전환해도 이전
/// 탭의 스택·스크롤 위치가 그대로 보존된다 — `navigationShell`이 내부적으로
/// `IndexedStack`을 쓰기 때문이다.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell, required this.showAdmin});

  final StatefulNavigationShell navigationShell;

  /// 관리자 탭 노출 여부. 지금은 항상 false로 들어온다 — 이유는
  /// `app_router.dart`의 `_showAdmin` 문서와 이슈 #34를 참고.
  final bool showAdmin;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final tab = AppTab.values[navigationShell.currentIndex];

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppTopBar(title: _titleFor(tab)),
      body: navigationShell,
      bottomNavigationBar: AppBottomNav(
        currentIndex: navigationShell.currentIndex,
        showAdmin: showAdmin,
        onTap: (index) => navigationShell.goBranch(
          index,
          // 이미 선택된 탭을 다시 누르면 그 탭의 스택을 첫 화면으로
          // 되돌린다 — go_router 표준 관례.
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }

  String _titleFor(AppTab tab) => switch (tab) {
    AppTab.home => '홈',
    AppTab.records => '기록',
    AppTab.admin => '관리자',
    AppTab.profile => '마이페이지',
  };
}
