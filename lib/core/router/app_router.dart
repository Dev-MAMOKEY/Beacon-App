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
///
/// **경고**: 이 집합은 정확한 문자열 일치만 본다. 매개변수가 있는 경로
/// (예: `/records/:id`)는 이 형태로 넣을 수 없다 — 템플릿 문자열이
/// `/records/42` 같은 실제 경로와 절대 같아지지 않아 조용히 `/home`으로
/// 튕긴다. 첫 매개변수 경로를 추가하는 사람은 이 집합을 패턴 매칭으로
/// 바꿔야 한다.
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

/// `/admin` 자신뿐 아니라 그 아래 모든 경로를 관리자 전용으로 본다.
/// 지금은 `/admin` 하나뿐이라 정확히 일치하는 것과 차이가 없지만, Phase 3가
/// `/admin/settings` 같은 자식을 추가하고 `readyAllowedLocations`에 넣는
/// 순간 정확히-일치 검사는 그 자식들을 통과시켜 버린다 — 접두사 규칙으로
/// 미리 막아 둔다.
///
/// `@visibleForTesting`으로 공개하는 이유: `readyAllowedLocations`에
/// `/admin`의 자식이 아직 하나도 없어서, `computeRedirect`를 블랙박스로만
/// 테스트하면 접두사 규칙과 정확히-일치 규칙이 오늘 시점에는 결과가
/// 똑같다(둘 다 "집합에 없으니 /home") — 그래서 이 함수 자체를 직접
/// 테스트해야 두 구현을 구분할 수 있다.
@visibleForTesting
bool isAdminRoute(String location) =>
    location == AppRoutes.admin || location.startsWith('${AppRoutes.admin}/');

/// `SessionReady`의 목적지를 고른다. 관리자 탭은 `showAdmin`이 false인
/// 동안 `/admin`(과 그 하위 경로) 자체를 허용 집합에서 빠진 것처럼
/// 취급한다 — 가드를 `computeRedirect` 밖(예: GoRouter의 `redirect:`
/// 클로저)에 따로 두면 `computeRedirect`를 직접 부르는 단위 테스트가 그
/// 가드를 전혀 보지 못한다. 가드 줄을 통째로 지워도 그 단위 테스트들은
/// 계속 초록색일 것이고, 실제로 그런 일이 있었다.
String _readyTarget({required String matchedLocation, required bool showAdmin}) {
  if (isAdminRoute(matchedLocation) && !showAdmin) {
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
  //
  // 이 hold는 원래 요청됐던 위치(matchedLocation)를 그냥 버린다 —
  // 콜드 스타트가 `/records`였어도 결국 `/home`으로 끝나고,
  // SignedOut 상태로 `/signup`에서 시작해도(딥링크 등으로) 이 시점의
  // matchedLocation은 잊혀서 `/signup` 예외를 못 받는다. 지금은 무해하다
  // — AndroidManifest에 `MAIN`/`LAUNCHER` 외의 intent-filter(`VIEW`,
  // `BROWSABLE`, scheme)가 없고 `restorationScopeId`도 어디에도 없어서,
  // `/` 이외의 위치에서 콜드 스타트가 시작될 경로 자체가 오늘은 없다.
  // 딥링크나 상태 복원 중 하나라도 생기면, 그걸 추가하는 사람이 목적지를
  // 이 hold를 관통해 보존하도록 고쳐야 한다 — 안 그러면 딥링크가 항상
  // `/home`에 착지한다(조용히 새는 게 아니라 바로 눈에 띈다).
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
///
/// `showAdminTabProvider`도 함께 구독한다 — 그러지 않으면 Phase 3에서 이
/// Provider가 실제 role 조회로 바뀐 뒤, `/admin`에 이미 들어가 있는
/// 사용자의 role이 회수돼도 아무 redirect도 재평가되지 않는다. `AppShell`은
/// `ref.watch`라 탭은 바로 사라지지만, 화면은 그대로 남고 선택된 탭 없이
/// 관리자 화면만 계속 보이게 된다 — 그 상태에서 뭔가 다른 내비게이션을
/// 시도해야 비로소 튕겨난다.
class _SessionListenable extends ChangeNotifier {
  _SessionListenable(this._ref) : launchedAt = DateTime.now() {
    _ref.listen(sessionControllerProvider, (_, _) => notifyListeners());
    _ref.listen(showAdminTabProvider, (_, _) => notifyListeners());
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
          // state.matchedLocation이 아니라 state.uri.path다.
          // matchedLocation을 안 쓰는 이유: go_router가 context.push()/
          // router.push()로 넣은 임시(Imperative) 매치는
          // ShellRouteMatch.matchedLocation(셸 자신의 선언적 매치 위치,
          // 예: '/profile')을 갱신하지 않고 uri/fullPath/pathParameters만
          // 갱신한다. matchedLocation을 쓰면 /profile/password로 push한
          // 뒤에도 이 값이 '/profile'에 멈춰 있다 — 직접 go_router 소스
          // (match.dart의 ShellRouteMatch.buildState)로 확인했다.
          // state.uri.toString() 대신 .path인 이유: toString()은 쿼리
          // 문자열도 그대로 붙여 돌려준다(`/profile/password?source=…`)
          // — _titleFor의 정확 일치 switch가 그 값을 인식하지 못해
          // 제목이 비어버린다. .path는 쿼리·프래그먼트를 뺀 경로만 준다.
          return AppShell(navigationShell: navigationShell, currentLocation: state.uri.path);
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
