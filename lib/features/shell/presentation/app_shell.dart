import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../components/nav/app_bottom_nav.dart';
import '../../../components/nav/app_top_bar.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/presentation/session_controller.dart';

/// `StatefulShellRoute.indexedStack`가 만드는 하단 탭 셸. 탭 4개(홈/기록/
/// 관리자/마이) 각각이 독립된 네비게이션 스택을 갖고, 탭을 전환해도 이전
/// 탭의 스택·스크롤 위치가 그대로 보존된다 — `navigationShell`이 내부적으로
/// `IndexedStack`을 쓰기 때문이다.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell, required this.currentLocation});

  final StatefulNavigationShell navigationShell;

  /// 지금 실제로 매칭된 전체 경로(예: `/records`). 상단 바 제목을 여기서
  /// 뽑는다 — `navigationShell.currentIndex`(브랜치 인덱스)로 뽑으면 같은
  /// 브랜치 안에서 하위 경로로 더 들어가도 인덱스가 그대로라 제목이 안
  /// 바뀐다. #13에서 `/profile/password`가 팝업으로 바뀌면서 오늘은 그런
  /// 하위 경로가 하나도 없지만, 첫 하위 경로가 생기는 순간 다시 문제가
  /// 되므로 전체 경로 기준을 유지한다.
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
    // 홈 탭의 상단 바 제목은 Figma 실측(339:1498/326:1569 "상단 메뉴")상
    // 고정 문구 "홈"이 아니라 로그인한 멤버의 이름이다. SessionReady가
    // 아닌 순간(이론상 셸 진입 전에는 있을 수 없지만 방어적으로)에는
    // 기존 고정 문구로 대체한다.
    final session = ref.watch(sessionControllerProvider).value;
    final memberName = session is SessionReady ? session.profile.name : null;

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppTopBar(title: shellTitleFor(currentLocation, memberName: memberName)),
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

}

/// 상단 바 제목을 경로에서 뽑는다. **브랜치 루트(첫 경로 세그먼트)로 매칭한다** —
/// 정확히 일치로 두면 `/profile/detail` 같은 하위 경로에서 제목이 빈 문자열이 된다.
///
/// 이 규칙이 [AppShell.currentLocation]에 무엇이 들어오든 결과를 같게 만든다.
/// 셸 빌더가 넘길 수 있는 값의 후보는 셋인데 — `state.uri.toString()`(쿼리까지
/// 포함), `state.uri.path`(쿼리 제거), `state.matchedLocation`(매칭된 라우트까지)
/// — 정확히-일치 switch에서는 이 셋이 서로 다른 제목을 내놓는다. 실제로 리뷰에서
/// `.uri.path`를 `.matchedLocation`으로 바꿔도 스위트 전체가 초록인 것이
/// 확인됐다(리뷰 Important 5). 하위 라우트가 하나도 없어서 세 값이 오늘은 항상
/// 같기 때문이고, 첫 하위 라우트가 생기는 순간 조용히 갈라진다.
///
/// 그 선택을 위젯 테스트로 고정하는 길은 막혀 있다 — 임시 자식 라우트를 끼워
/// 넣어도 `computeRedirect`가 `readyAllowedLocations`에 없는 경로를 `/home`으로
/// 돌려보내 그 화면에 도달할 수 없다(직접 프로브로 확인했다). 그래서 선택을
/// 고정하는 대신 **선택이 무의미해지도록** 매칭 규칙을 바꿨다.
///
/// 접두사 규칙을 쓰는 [isAdminRoute]와도 같은 방향이다.
@visibleForTesting
String shellTitleFor(String location, {required String? memberName}) {
  final path = Uri.parse(location).path;
  final segment = path.split('/').where((s) => s.isNotEmpty).firstOrNull;
  return switch (segment == null ? '/' : '/$segment') {
    AppRoutes.home => memberName ?? '홈',
    AppRoutes.records => '기록',
    AppRoutes.admin => '관리자',
    AppRoutes.profile => '마이페이지',
    _ => '',
  };
}
