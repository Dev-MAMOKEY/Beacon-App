import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../components/nav/app_bottom_nav.dart';
import '../../../components/nav/app_top_bar.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';

/// `StatefulShellRoute.indexedStack`가 만드는 하단 탭 셸. 탭 4개(홈/기록/
/// 관리자/마이) 각각이 독립된 네비게이션 스택을 갖고, 탭을 전환해도 이전
/// 탭의 스택·스크롤 위치가 그대로 보존된다 — `navigationShell`이 내부적으로
/// `IndexedStack`을 쓰기 때문이다.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell, required this.currentLocation});

  final StatefulNavigationShell navigationShell;

  /// 지금 실제로 매칭된 전체 경로(예: `/profile/password`). 상단 바
  /// 제목을 여기서 뽑는다 — `navigationShell.currentIndex`(브랜치 인덱스)로
  /// 뽑으면 같은 브랜치 안에서 하위 경로로 더 들어가도(`/profile` →
  /// `/profile/password`) 인덱스가 그대로라 제목이 안 바뀐다.
  final String currentLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>()!;
    // ref.read가 아니라 watch다 — Phase 3에서 이 Provider가 실제 role
    // 조회 결과로 교체되면, 이미 셸 안에 있는 사용자도 role이 풀리는
    // 순간 관리자 탭이 바로 나타나야 한다. read로 마운트 시점 값만
    // 찍어두면 다른 내비게이션이 셸을 다시 빌드하기 전까지 탭 3개짜리
    // 바가 그대로 남는다.
    final showAdmin = ref.watch(showAdminTabProvider);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppTopBar(title: _titleFor(currentLocation)),
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

  String _titleFor(String location) => switch (location) {
    AppRoutes.home => '홈',
    AppRoutes.records => '기록',
    AppRoutes.admin => '관리자',
    AppRoutes.profile => '마이페이지',
    AppRoutes.passwordChange => '비밀번호 변경',
    _ => '',
  };
}
