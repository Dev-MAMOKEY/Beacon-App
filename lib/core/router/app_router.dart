import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/session_controller.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../theme/app_colors.dart';

abstract final class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String invite = '/invite';
  static const String home = '/home';
}

/// go_router가 Riverpod 상태 변화를 구독하게 하는 어댑터.
class _SessionListenable extends ChangeNotifier {
  _SessionListenable(this._ref) {
    _ref.listen(sessionControllerProvider, (_, _) => notifyListeners());
  }

  final Ref _ref;
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final listenable = _SessionListenable(ref);
  ref.onDispose(listenable.dispose);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: listenable,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      // redirect가 이 경로를 가리키므로 라우트 자체는 지금 등록해야 한다.
      // 등록하지 않으면 go_router가 redirect 시점에 예외를 던진다.
      // 내용은 #11에서 실제 홈 화면으로 교체한다.
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const _HomePlaceholder(),
      ),
      // 로그인/회원가입/초대코드는 #8, #9에서 등록한다.
    ],
    redirect: (context, state) {
      final session = ref.read(sessionControllerProvider);

      // 판별 중에는 스플래시에 머무른다.
      if (session.isLoading || !session.hasValue) {
        return state.matchedLocation == AppRoutes.splash ? null : AppRoutes.splash;
      }

      final target = switch (session.requireValue) {
        SessionUnknown() => AppRoutes.splash,
        SessionSignedOut() => AppRoutes.login,
        SessionNeedsClub() => AppRoutes.invite,
        SessionReady() => AppRoutes.home,
      };

      // 로그인 상태에서 회원가입 화면은 허용하지 않는다.
      if (session.requireValue is SessionSignedOut &&
          state.matchedLocation == AppRoutes.signup) {
        return null;
      }

      return state.matchedLocation == target ? null : target;
    },
  );
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
