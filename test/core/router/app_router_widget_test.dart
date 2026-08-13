import 'package:beacon_app/core/network/dio_provider.dart';
import 'package:beacon_app/core/router/app_router.dart';
import 'package:beacon_app/core/storage/token_store.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:beacon_app/features/auth/data/auth_dto.dart';
import 'package:beacon_app/features/auth/data/auth_repository.dart';
import 'package:beacon_app/features/auth/presentation/login_screen.dart';
import 'package:beacon_app/features/auth/presentation/signup_screen.dart';
import 'package:beacon_app/features/club/presentation/invite_code_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// `app_router_test.dart`는 `computeRedirect`가 문자열 `"/invite"`를
/// 돌려주는지만 확인하는 순수 함수 테스트다 — 그 문자열이 실제로 어떤
/// 화면과 연결돼 있는지는 전혀 검증하지 않는다. `GoRoute`가 라우트 배열에서
/// 통째로 빠지거나 다른 화면을 가리키게 바뀌어도 그 테스트들은 계속
/// 초록색이다. 이 파일은 실제 `appRouterProvider`(진짜 GoRouter)를 마운트해
/// 각 경로가 정말 그 화면을 렌더링하는지 확인한다.
///
/// 예전에는 `/invite` 하나만 이렇게 검증했다 — `/home`, `/login`, `/signup`
/// 은 `GoRoute`를 지워도 115개 테스트가 전부 통과했다.
class _ProfileAuthRepository implements AuthRepository {
  _ProfileAuthRepository(this.clubIds);

  final List<int> clubIds;

  @override
  Future<TokenResponse> login({required String stdId, required String password}) async =>
      const TokenResponse(accessToken: 'a', refreshToken: 'r');

  @override
  Future<void> signup({
    required String stdId,
    required String password,
    required String name,
  }) async {}

  @override
  Future<TokenResponse> refresh(String refreshToken) async =>
      const TokenResponse(accessToken: 'a', refreshToken: 'r');

  @override
  Future<void> logout() async {}

  @override
  Future<MemberProfile> fetchMe() async => MemberProfile(
        name: '김민준',
        stdId: '20250101',
        clubIds: clubIds,
        pushEnabled: true,
      );
}

/// 실제 `appRouterProvider`를 마운트하고 최초 리다이렉트가 끝날 때까지
/// 진행시킨다. [clubIds]가 null이면 저장된 토큰이 없는 상태(=SignedOut)를
/// 재현한다.
Future<GoRouter> _pumpRealRouter(WidgetTester tester, {List<int>? clubIds}) async {
  final store = InMemoryTokenStore();
  if (clubIds != null) await store.save(accessToken: 'a', refreshToken: 'r');

  final container = ProviderContainer(
    overrides: [
      tokenStoreProvider.overrideWithValue(store),
      authRepositoryProvider.overrideWithValue(_ProfileAuthRepository(clubIds ?? const [])),
    ],
  );
  addTearDown(container.dispose);

  final router = container.read(appRouterProvider);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
    ),
  );

  // 세션 판별(비동기 refresh + fetchMe)이 끝나도록 한 박자 흘려보낸다.
  await tester.pump();
  await tester.pump();

  // computeRedirect의 최소 스플래시 노출 시간(1.5초) 판정은 시뮬레이션
  // 시계가 아니라 진짜 DateTime.now()를 쓴다 — tester.pump(duration)은
  // Timer만 진행시킬 뿐 실제 시간은 흐르지 않으므로, runAsync로 진짜 1.6초를
  // 흘려보내야 그 판정을 통과할 수 있다. 그런 다음 pump(duration)으로
  // _SessionListenable의 `Timer(minSplashDuration, notifyListeners)`를 실제로
  // 발화시켜 go_router가 redirect를 다시 평가하게 만든다.
  await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 1600)));
  await tester.pump(const Duration(milliseconds: 1600));
  await tester.pumpAndSettle();

  return router;
}

void main() {
  testWidgets(
    '실제 appRouterProvider는 clubIds가 비어 있으면 /invite로 이동해 InviteCodeScreen을 렌더링한다',
    (tester) async {
      await _pumpRealRouter(tester, clubIds: const []);

      // `/invite` GoRoute가 라우트 트리에서 빠지거나 다른 화면을 가리키면
      // 여기서 InviteCodeScreen을 찾지 못해 이 expect가 실패한다 — 실제로
      // GoRoute를 지워서 확인했다: go_router가 예외를 던지지는 않고,
      // computeRedirect가 여전히 가리키는 "/invite" 경로에 매칭되는 화면이
      // 없으니 InviteCodeScreen이 그냥 렌더링되지 않는다(찾은 위젯 수 0).
      expect(find.byType(InviteCodeScreen), findsOneWidget);
    },
  );

  testWidgets('동아리가 있으면 /home으로 이동해 홈 화면을 렌더링한다', (tester) async {
    await _pumpRealRouter(tester, clubIds: const [7]);

    // #11에서 실제 홈 화면으로 교체되는 자리표시자. `/home` GoRoute가 없으면
    // 아무것도 렌더링되지 않아 이 expect가 실패한다.
    expect(find.text('홈 화면은 #11에서 구현합니다'), findsOneWidget);
  });

  testWidgets('저장된 토큰이 없으면 /login으로 이동해 LoginScreen을 렌더링한다', (tester) async {
    await _pumpRealRouter(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('로그인 화면에서 회원가입을 누르면 /signup의 SignupScreen이 렌더링된다', (tester) async {
    await _pumpRealRouter(tester);
    expect(find.byType(LoginScreen), findsOneWidget);

    // 화면이 실제로 쓰는 경로(context.push(AppRoutes.signup))를 그대로 탄다.
    await tester.tap(find.text('회원가입'));
    await tester.pumpAndSettle();

    expect(find.byType(SignupScreen), findsOneWidget);
  });
}
