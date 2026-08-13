import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/session_controller.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../theme/app_colors.dart';

abstract final class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String invite = '/invite';
  static const String home = '/home';
}

/// 명세서: "약 1.5초간 스플래시를 보여준 후 자동으로 다음 화면으로
/// 전환합니다." 판별이 이보다 빨리 끝나도(토큰이 아예 없는 경우 등) 이
/// 시간만큼은 스플래시에 머무른다. 실패(SessionUnavailable)는 재시도 UI를
/// 바로 보여줘야 하므로 이 지연을 적용하지 않는다.
const Duration minSplashDuration = Duration(milliseconds: 1500);

/// GoRouterState/BuildContext 없이 단위 테스트할 수 있도록 뽑아낸 순수
/// redirect 결정 함수.
@visibleForTesting
String? computeRedirect({
  required AsyncValue<SessionState> session,
  required String matchedLocation,
  required DateTime launchedAt,
  required DateTime now,
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

  final target = switch (value) {
    SessionSignedOut() => AppRoutes.login,
    SessionNeedsClub() => AppRoutes.invite,
    SessionReady() => AppRoutes.home,
    // 실패는 스플래시 자신에 머무르며 재시도 UI를 보여준다.
    SessionUnavailable() => AppRoutes.splash,
  };

  // 성공적으로 판별됐더라도, 실패가 아닌 한 최소 노출 시간이 지나기 전에는
  // 스플래시를 벗어나지 않는다.
  if (value is! SessionUnavailable && now.difference(launchedAt) < minSplashDuration) {
    return matchedLocation == AppRoutes.splash ? null : AppRoutes.splash;
  }

  // 로그인 상태에서 회원가입 화면은 허용하지 않는다.
  if (value is SessionSignedOut && matchedLocation == AppRoutes.signup) {
    return null;
  }

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
      // redirect가 이 경로를 가리키므로 라우트 자체는 지금 등록해야 한다.
      // 등록하지 않으면 go_router가 redirect 시점에 예외를 던진다.
      // 내용은 #11에서 실제 홈 화면으로 교체한다.
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const _HomePlaceholder(),
      ),
      // 초대코드 화면은 #9에서 등록한다.
    ],
    redirect: (context, state) {
      return computeRedirect(
        session: ref.read(sessionControllerProvider),
        matchedLocation: state.matchedLocation,
        launchedAt: listenable.launchedAt,
        now: DateTime.now(),
      );
    },
  );
  ref.onDispose(router.dispose);

  return router;
});

/// #11에서 실제 홈 화면으로 교체된다.
class _HomePlaceholder extends StatelessWidget {
  const _HomePlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return ColoredBox(
      color: colors.bg,
      child: const Center(child: Text('홈 화면은 #11에서 구현합니다')),
    );
  }
}
