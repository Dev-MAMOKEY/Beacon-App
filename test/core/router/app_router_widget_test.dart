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
/// 재현한다. [showAdmin]은 `showAdminTabProvider`를 override한다 — 기본값
/// false는 실제 앱과 동일하고, true는 관리자 탭·라우트 자체의 배선을
/// (가드와 분리해) 검증할 때 쓴다.
Future<GoRouter> _pumpRealRouter(
  WidgetTester tester, {
  List<int>? clubIds,
  bool showAdmin = false,
}) async {
  final store = InMemoryTokenStore();
  if (clubIds != null) await store.save(accessToken: 'a', refreshToken: 'r');

  final container = ProviderContainer(
    overrides: [
      tokenStoreProvider.overrideWithValue(store),
      authRepositoryProvider.overrideWithValue(_ProfileAuthRepository(clubIds ?? const [])),
      showAdminTabProvider.overrideWithValue(showAdmin),
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

  testWidgets('하단 탭 4개의 경로가 각각 올바른 화면을 렌더한다', (tester) async {
    // showAdmin: true로 관리자 라우트 가드를 우회해, 4개 브랜치 전부가
    // 실제로 올바른 화면과 연결돼 있는지를 가드와 분리해서 검증한다.
    // 가드 자체(showAdmin:false일 때 /admin이 막히는지)는 별도 테스트가
    // 다룬다. computeRedirect가 문자열을 반환하는지만 보는 것으로는
    // GoRoute가 트리에서 빠지거나 다른 화면을 가리키는 실수를 잡지 못한다
    // — 실제로 각 경로를 방문해 화면 텍스트를 찾는다.
    final router = await _pumpRealRouter(tester, clubIds: const [7], showAdmin: true);

    router.go(AppRoutes.home);
    await tester.pumpAndSettle();
    expect(find.text('홈 화면은 #11에서 구현합니다'), findsOneWidget);

    router.go(AppRoutes.records);
    await tester.pumpAndSettle();
    expect(find.text('기록 화면은 #12에서 구현합니다'), findsOneWidget);

    router.go(AppRoutes.admin);
    await tester.pumpAndSettle();
    expect(find.text('관리자 화면은 Phase 3에서 구현합니다'), findsOneWidget);

    router.go(AppRoutes.profile);
    await tester.pumpAndSettle();
    expect(find.text('마이페이지는 #13에서 구현합니다'), findsOneWidget);
  });

  testWidgets('탭을 전환했다 돌아오면 이전 탭의 스크롤 위치와 네비게이션 스택이 보존된다', (tester) async {
    final router = await _pumpRealRouter(tester, clubIds: const [7]);

    // 기록 탭에서 목록을 스크롤해 둔다.
    router.go(AppRoutes.records);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    final scrolledOffset = tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;
    expect(scrolledOffset, greaterThan(0));

    // 마이 탭으로 이동한 뒤, 그 안에서 비밀번호 변경 화면까지 한 단계 더
    // 들어간다 — 마이 탭의 네비게이션 스택이 [마이페이지, 비밀번호 변경]
    // 두 단계가 된다.
    await tester.tap(find.text('마이'));
    await tester.pumpAndSettle();
    expect(find.text('마이페이지는 #13에서 구현합니다'), findsOneWidget);

    router.push(AppRoutes.passwordChange);
    await tester.pumpAndSettle();
    expect(find.text('비밀번호 변경은 #13에서 구현합니다'), findsOneWidget);

    // 홈 탭으로 전환했다가...
    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();
    expect(find.text('홈 화면은 #11에서 구현합니다'), findsOneWidget);

    // ...다시 마이 탭으로 돌아오면, 루트(마이페이지)가 아니라 방금
    // 들어갔던 비밀번호 변경 화면이 그대로 남아있어야 한다.
    await tester.tap(find.text('마이'));
    await tester.pumpAndSettle();
    expect(find.text('비밀번호 변경은 #13에서 구현합니다'), findsOneWidget);
    expect(find.text('마이페이지는 #13에서 구현합니다'), findsNothing);

    // ...그리고 기록 탭으로 돌아오면 스크롤 위치도 그대로 보존돼 있어야
    // 한다. `IndexedStack` 대신 탭마다 매번 새로 빌드하면 스크롤 가능한
    // 위젯의 State(따라서 스크롤 위치)가 사라지고 0으로 다시 시작한다.
    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();
    final restoredOffset = tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;
    expect(restoredOffset, scrolledOffset);
  });

  testWidgets('showAdmin: false 상태에서 /admin으로 이동하면 /home으로 차단된다', (tester) async {
    // showAdmin 기본값 false — 실제 앱과 동일한 상태.
    final router = await _pumpRealRouter(tester, clubIds: const [7]);

    router.go(AppRoutes.admin);
    await tester.pumpAndSettle();

    expect(find.text('홈 화면은 #11에서 구현합니다'), findsOneWidget);
    expect(find.text('관리자 화면은 Phase 3에서 구현합니다'), findsNothing);
  });
}
