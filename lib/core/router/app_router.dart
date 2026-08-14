import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/session_controller.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/club/presentation/invite_code_screen.dart';
import '../../features/shell/presentation/app_shell.dart';
import '../theme/app_colors.dart';

abstract final class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String invite = '/invite';
  static const String home = '/home';
  static const String records = '/records';
  static const String admin = '/admin';
  static const String profile = '/profile';
  static const String passwordChange = '/profile/password';
}

/// 하단 탭 셸의 브랜치 순서. `StatefulShellRoute`의 브랜치 인덱스와
/// 1:1로 대응한다 — 순서를 바꾸면 양쪽을 함께 바꿔야 한다.
enum AppTab { home, records, admin, profile }

/// 관리자 탭은 `role == ADMIN`일 때만 노출해야 하지만, `GET /members/me`
/// (`MemberProfile`)에는 role이 없다 — role은 `GET /clubs/{clubId}/members`의
/// `ClubMemberResponse.role`에만 있다. 그 목록 조회를 이 태스크에서 새로
/// 끌어오는 대신, 관리자 화면이 실제로 존재하는 Phase 3까지 이 Provider는
/// 항상 false를 돌려준다 — 관리자 탭은 숨겨지고 `/admin` 진입도 차단된다.
/// Phase 3는 이 Provider를 실제 role 조회 결과로 override하기만 하면 된다.
/// (이슈 #34 결정 사항)
final showAdminTabProvider = Provider<bool>((ref) => false);

/// `SessionReady` 상태에서 허용하는 위치 집합 — 하단 탭 셸에 실제로
/// 등록된 5개 경로(탭 4개 + `/profile/password`)와 정확히 일치해야 한다.
/// `app_router_widget_test.dart`가 실제 라우트 트리를 순회해 이 집합과
/// 비교한다 — 탭을 추가하고 이 집합 갱신을 잊으면 그 테스트가 실패한다.
/// `@visibleForTesting`으로 공개하는 이유도 그 비교를 가능하게 하기
/// 위해서다(라이브러리 단위 private라 테스트 파일에서는 애초에 접근할
/// 수 없다).
@visibleForTesting
const Set<String> readyAllowedLocations = {
  AppRoutes.home,
  AppRoutes.records,
  AppRoutes.admin,
  AppRoutes.profile,
  AppRoutes.passwordChange,
};

/// 명세서: "약 1.5초간 스플래시를 보여준 후 자동으로 다음 화면으로
/// 전환합니다." 판별이 이보다 빨리 끝나도(토큰이 아예 없는 경우 등) 이
/// 시간만큼은 스플래시에 머무른다. 실패(SessionUnavailable)는 재시도 UI를
/// 바로 보여줘야 하므로 이 지연을 적용하지 않는다.
const Duration minSplashDuration = Duration(milliseconds: 1500);

/// `SessionReady`의 목적지를 고른다. 관리자 탭은 `showAdmin`이 false인
/// 동안 `/admin` 자체를 허용 집합에서 빠진 것처럼 취급한다 — 가드를
/// `computeRedirect` 밖(예: GoRouter의 `redirect:` 클로저)에 따로 두면
/// `computeRedirect`를 직접 부르는 단위 테스트가 그 가드를 전혀 보지
/// 못한다. 가드 줄을 통째로 지워도 그 단위 테스트들은 계속 초록색일
/// 것이고, 실제로 그런 일이 있었다.
String _readyTarget({required String matchedLocation, required bool showAdmin}) {
  if (matchedLocation == AppRoutes.admin && !showAdmin) {
    return AppRoutes.home;
  }
  return readyAllowedLocations.contains(matchedLocation) ? matchedLocation : AppRoutes.home;
}

/// GoRouterState/BuildContext 없이 단위 테스트할 수 있도록 뽑아낸 순수
/// redirect 결정 함수.
@visibleForTesting
String? computeRedirect({
  required AsyncValue<SessionState> session,
  required String matchedLocation,
  required DateTime launchedAt,
  required DateTime now,
  required bool showAdmin,
}) {
  // AsyncError는 이전 값이 남아있어도(hasValue == true) 판별이 실패했다는
  // 뜻이다 — requireValue로 낡은 값을 읽어 그쪽으로 리다이렉트하면 안 된다.
  // build()가 예외를 던지지 않도록 만들었으니 정상 경로에서는 발생하지
  // 않아야 하지만, 방어적으로 스플래시에 묶어둔다.
  if (session.hasError) {
    return matchedLocation == AppRoutes.splash ? null : AppRoutes.splash;
  }

  // 판별 중(최초 진입이든 재판별이든)에는 스플래시에 머무른다.
  if (session.isLoading || !session.hasValue) {
    return matchedLocation == AppRoutes.splash ? null : AppRoutes.splash;
  }

  final value = session.requireValue;

  // 성공적으로 판별됐더라도, 실패가 아닌 한 최소 노출 시간이 지나기 전에는
  // 스플래시를 벗어나지 않는다.
  if (value is! SessionUnavailable && now.difference(launchedAt) < minSplashDuration) {
    return matchedLocation == AppRoutes.splash ? null : AppRoutes.splash;
  }

  // 로그인 상태에서 회원가입 화면은 허용하지 않는다.
  if (value is SessionSignedOut && matchedLocation == AppRoutes.signup) {
    return null;
  }

  // 봉인된(sealed) SessionState 위의 exhaustive switch — 상태가 하나
  // 늘어나면 이 switch가 컴파일 타임에 누락을 알려준다. if-체인 +
  // "나머지는 SessionUnavailable" 주석으로 바꾸면 그 보장이 조용히
  // 사라지고, 다섯 번째 상태가 추가돼도 컴파일은 되면서 스플래시로 조용히
  // 새는 버그가 생긴다.
  final target = switch (value) {
    SessionSignedOut() => AppRoutes.login,
    SessionNeedsClub() => AppRoutes.invite,
    SessionReady() => _readyTarget(matchedLocation: matchedLocation, showAdmin: showAdmin),
    SessionUnavailable() => AppRoutes.splash,
  };

  return matchedLocation == target ? null : target;
}

/// go_router가 Riverpod 상태 변화를 구독하게 하는 어댑터. 앱이 생성된
/// 시각(대략 launch 시각)을 들고 있다가, 최소 스플래시 노출 시간이 지나는
/// 순간에도 redirect가 다시 평가되도록 한 번 notifyListeners()한다 —
/// go_router의 redirect는 리스너블이 알리거나 네비게이션이 시도될 때만
/// 재평가되고 타이머로 저절로 재평가되지 않기 때문이다.
class _SessionListenable extends ChangeNotifier {
  _SessionListenable(this._ref) : launchedAt = DateTime.now() {
    _ref.listen(sessionControllerProvider, (_, _) => notifyListeners());
    _minDurationTimer = Timer(minSplashDuration, notifyListeners);
  }

  final Ref _ref;
  final DateTime launchedAt;
  late final Timer _minDurationTimer;

  @override
  void dispose() {
    _minDurationTimer.cancel();
    super.dispose();
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final listenable = _SessionListenable(ref);
  ref.onDispose(listenable.dispose);

  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: listenable,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.signup,
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: AppRoutes.invite,
        builder: (context, state) => const InviteCodeScreen(),
      ),
      // redirect가 이 경로들을 가리키므로 라우트 자체를 지금 등록해야
      // 한다. 등록하지 않아도 go_router가 예외를 던지지는 않는다 —
      // redirect는 그대로 그 경로를 가리키고, 거기 매칭되는 라우트가
      // 없으니 그 화면이 그냥 렌더링되지 않는다(app_router_widget_test에서
      // 실제로 GoRoute를 지워 확인했다: 찾은 위젯 수 0). 조용히 실패하기
      // 때문에 오히려 라우트 등록을 테스트로 고정해 둘 필요가 있다.
      // 각 자리표시자는 해당 태스크에서 실제 화면으로 교체된다.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          // state.matchedLocation이 아니라 state.uri다 — go_router가
          // context.push()/router.push()로 넣은 임시(Imperative) 매치는
          // ShellRouteMatch.matchedLocation(셸 자신의 선언적 매치 위치,
          // 예: '/profile')을 갱신하지 않고 uri/fullPath/pathParameters만
          // 갱신한다. matchedLocation을 쓰면 /profile/password로 push한
          // 뒤에도 이 값이 '/profile'에 멈춰 있다 — 직접 go_router 소스
          // (match.dart의 ShellRouteMatch.buildState)로 확인했다.
          return AppShell(navigationShell: navigationShell, currentLocation: state.uri.toString());
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const _Placeholder(message: '홈 화면은 #11에서 구현합니다'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.records,
                builder: (context, state) => const _RecordsPlaceholder(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.admin,
                builder: (context, state) =>
                    const _Placeholder(message: '관리자 화면은 Phase 3에서 구현합니다'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                builder: (context, state) => const _Placeholder(message: '마이페이지는 #13에서 구현합니다'),
                routes: [
                  GoRoute(
                    // 부모 경로(`/profile`)에 상대적이라 최종 경로는
                    // AppRoutes.passwordChange('/profile/password')와
                    // 일치한다.
                    path: 'password',
                    builder: (context, state) =>
                        const _Placeholder(message: '비밀번호 변경은 #13에서 구현합니다'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
    redirect: (context, state) {
      return computeRedirect(
        session: ref.read(sessionControllerProvider),
        matchedLocation: state.matchedLocation,
        launchedAt: listenable.launchedAt,
        now: DateTime.now(),
        showAdmin: ref.read(showAdminTabProvider),
      );
    },
  );
  ref.onDispose(router.dispose);

  return router;
});

/// 자리표시자 4종(홈/관리자/마이/비밀번호 변경)이 메시지만 다르고 구조가
/// 완전히 같아 하나로 합쳤다. `_RecordsPlaceholder`만 별도로 남아 있다 —
/// 탭 전환 시 스크롤 위치가 보존되는지 테스트가 확인하려면 스크롤 가능한
/// 콘텐츠가 필요하기 때문이다(app_router_widget_test.dart).
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return ColoredBox(
      color: colors.bg,
      child: Center(child: Text(message)),
    );
  }
}

/// #12에서 실제 기록 캘린더 화면으로 교체된다. 스크롤 가능한 목록을 두는
/// 이유는 탭 전환 시 스크롤 위치가 보존되는지를 테스트가 확인해야 하기
/// 때문이다(app_router_widget_test.dart) — `IndexedStack` 대신 탭마다 매번
/// 새로 빌드하면 여기 스크롤 위치가 0으로 리셋된다. 실제 기록 화면이
/// 들어오면 자연히 대체된다.
class _RecordsPlaceholder extends StatelessWidget {
  const _RecordsPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return ColoredBox(
      color: colors.bg,
      child: ListView(
        children: [
          const SizedBox(height: 40),
          const Center(child: Text('기록 화면은 #12에서 구현합니다')),
          for (var i = 0; i < 30; i++)
            SizedBox(height: 80, child: Center(child: Text('placeholder-$i'))),
        ],
      ),
    );
  }
}
