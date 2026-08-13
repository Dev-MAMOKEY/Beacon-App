import 'dart:async';

import 'package:beacon_app/components/ui/button.dart';
import 'package:beacon_app/components/ui/input.dart';
import 'package:beacon_app/core/network/api_exception.dart';
import 'package:beacon_app/core/network/dio_provider.dart';
import 'package:beacon_app/core/network/error_code.dart';
import 'package:beacon_app/core/storage/token_store.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:beacon_app/features/auth/data/auth_dto.dart';
import 'package:beacon_app/features/auth/data/auth_repository.dart';
import 'package:beacon_app/features/auth/presentation/session_controller.dart';
import 'package:beacon_app/features/auth/presentation/signup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// 회원가입은 항상 성공하지만, 곧바로 시도하는 자동 로그인은 항상 실패하는
/// 리포지토리 — "계정은 만들어졌지만 로그인은 실패했다"는 부분 성공 경로를
/// 재현한다.
class _SignupSucceedsLoginFailsRepository implements AuthRepository {
  int signupCalls = 0;
  int loginCalls = 0;

  @override
  Future<void> signup({
    required String stdId,
    required String password,
    required String name,
  }) async {
    signupCalls++;
  }

  @override
  Future<TokenResponse> login({required String stdId, required String password}) async {
    loginCalls++;
    throw const ApiException(ErrorCode.invalidCredentials, '학번 또는 비밀번호가 올바르지 않습니다.');
  }

  @override
  Future<TokenResponse> refresh(String refreshToken) async =>
      const TokenResponse(accessToken: 'a', refreshToken: 'r');

  @override
  Future<void> logout() async {}

  @override
  Future<MemberProfile> fetchMe() async => const MemberProfile(
        name: '김민준',
        stdId: '20250101',
        clubIds: [1],
        pushEnabled: true,
      );
}

/// 회원가입/로그인 둘 다 [signupGate]/[loginGate]가 완료될 때까지 멈춘다 —
/// "요청이 진행 중인 동안 화면이 사라진다" 시나리오를 결정적으로 재현하기
/// 위한 용도.
class _GatedRepository implements AuthRepository {
  _GatedRepository({required this.signupGate, required this.loginGate});

  final Future<void> signupGate;
  final Future<void> loginGate;

  @override
  Future<void> signup({
    required String stdId,
    required String password,
    required String name,
  }) async {
    await signupGate;
  }

  @override
  Future<TokenResponse> login({required String stdId, required String password}) async {
    await loginGate;
    return const TokenResponse(accessToken: 'a', refreshToken: 'r');
  }

  @override
  Future<TokenResponse> refresh(String refreshToken) async =>
      const TokenResponse(accessToken: 'a', refreshToken: 'r');

  @override
  Future<void> logout() async {}

  @override
  Future<MemberProfile> fetchMe() async => const MemberProfile(
        name: '김민준',
        stdId: '20250101',
        clubIds: [1],
        pushEnabled: true,
      );
}

/// 회원가입도 자동 로그인도 성공하는 리포지토리. 성공 경로를 검증하는
/// 테스트가 하나도 없어서 `onAuthenticated(tokens)` 호출을 통째로 지워도
/// 115개 테스트가 전부 통과했다.
class _SignupSucceedsRepository implements AuthRepository {
  int signupCalls = 0;
  int loginCalls = 0;
  int fetchMeCalls = 0;

  @override
  Future<void> signup({
    required String stdId,
    required String password,
    required String name,
  }) async {
    signupCalls++;
  }

  @override
  Future<TokenResponse> login({required String stdId, required String password}) async {
    loginCalls++;
    return const TokenResponse(accessToken: 'signup-a', refreshToken: 'signup-r');
  }

  @override
  Future<TokenResponse> refresh(String refreshToken) async =>
      const TokenResponse(accessToken: 'a', refreshToken: 'r');

  @override
  Future<void> logout() async {}

  @override
  Future<MemberProfile> fetchMe() async {
    fetchMeCalls++;
    // 명세서: 회원가입 직후 사용자는 아직 동아리가 없으므로 초대코드 화면으로
    // 간다 — NeedsClub이 이 경로의 정상 결과다.
    return const MemberProfile(
      name: '김민준',
      stdId: '20250101',
      clubIds: [],
      pushEnabled: false,
    );
  }
}

/// 회원가입은 즉시 성공하고, 이어지는 자동 로그인만 [loginGate]까지 멈춘다 —
/// "자동 로그인이 진행되는 동안 화면이 사라진다"는 시점을 만들기 위한 용도.
/// 기존 라이프사이클 테스트는 `signup()` 도중에 화면을 없애기 때문에 자동
/// 로그인 이후의 mounted 가드에는 애초에 도달하지 못한다.
class _SignupOkGatedLoginRepository implements AuthRepository {
  _SignupOkGatedLoginRepository(this.loginGate);

  final Future<void> loginGate;
  int loginCalls = 0;
  int fetchMeCalls = 0;

  @override
  Future<void> signup({
    required String stdId,
    required String password,
    required String name,
  }) async {}

  @override
  Future<TokenResponse> login({required String stdId, required String password}) async {
    loginCalls++;
    await loginGate;
    return const TokenResponse(accessToken: 'signup-a', refreshToken: 'signup-r');
  }

  @override
  Future<TokenResponse> refresh(String refreshToken) async =>
      const TokenResponse(accessToken: 'a', refreshToken: 'r');

  @override
  Future<void> logout() async {}

  @override
  Future<MemberProfile> fetchMe() async {
    fetchMeCalls++;
    return const MemberProfile(
      name: '김민준',
      stdId: '20250101',
      clubIds: [],
      pushEnabled: false,
    );
  }
}

GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, _) => const Scaffold(body: Center(child: Text('로그인 화면 자리'))),
      ),
      GoRoute(path: '/signup', builder: (_, _) => const SignupScreen()),
    ],
  );
}

Future<void> _fillValidSignupForm(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(0), '20250101');
  await tester.pump();
  await tester.enterText(find.byType(TextField).at(1), 'Minjun');
  await tester.pump();
  await tester.enterText(find.byType(TextField).at(2), 'abcd1234');
  await tester.pump();
  await tester.enterText(find.byType(TextField).at(3), 'abcd1234');
  await tester.pump();
}

/// 화면 밖에서 `sessionControllerProvider`의 최종 상태와 저장된 토큰을
/// 확인해야 하는 테스트용 호스트.
({Widget widget, ProviderContainer container, InMemoryTokenStore store, GoRouter router})
    _hostWithContainer(AuthRepository repository) {
  final store = InMemoryTokenStore();
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(repository),
      tokenStoreProvider.overrideWithValue(store),
    ],
  );
  final router = _buildRouter();
  return (
    widget: UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
    ),
    container: container,
    store: store,
    router: router,
  );
}

void main() {
  testWidgets('회원가입에 성공하면 자동 로그인까지 이어져 세션이 만들어진다', (tester) async {
    final repository = _SignupSucceedsRepository();
    final host = _hostWithContainer(repository);
    addTearDown(host.container.dispose);

    // 실제 앱처럼 최초 세션 판별(저장된 토큰 없음 → SignedOut)을 먼저 끝낸다.
    expect(
      await host.container.read(sessionControllerProvider.future),
      isA<SessionSignedOut>(),
    );

    await tester.pumpWidget(host.widget);
    await tester.pumpAndSettle();
    host.router.push('/signup');
    await tester.pumpAndSettle();

    await _fillValidSignupForm(tester);
    await tester.tap(find.byType(AppButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repository.signupCalls, 1);
    expect(repository.loginCalls, 1);
    // 로그인 응답을 받는 것만으로는 부족하다 — 그 토큰이 세션 컨트롤러까지
    // 흘러가 프로필을 읽고 상태를 바꿨는지 확인한다.
    expect(repository.fetchMeCalls, 1);
    expect(
      host.container.read(sessionControllerProvider).value,
      isA<SessionNeedsClub>(),
      reason: 'onAuthenticated를 부르지 않으면 회원가입 후 사용자가 아무 데도 가지 못한다',
    );
    expect(await host.store.readAccessToken(), 'signup-a');
    expect(await host.store.readRefreshToken(), 'signup-r');
  });

  // 검증기 자체는 auth_form_validator_test가 단위로 확인하지만, 그것이
  // 제출과 실제로 연결돼 있는지는 어디서도 확인되지 않았다 —
  // `if (!_validate()) return;`을 지워도 115개가 전부 통과했다.
  testWidgets('폼이 유효하지 않으면 요청을 보내지 않고 필드 에러만 보여준다', (tester) async {
    final repository = _SignupSucceedsRepository();
    final host = _hostWithContainer(repository);
    addTearDown(host.container.dispose);

    await tester.pumpWidget(host.widget);
    await tester.pumpAndSettle();
    host.router.push('/signup');
    await tester.pumpAndSettle();

    // 이름만 비운 채로 제출한다.
    await tester.enterText(find.byType(TextField).at(0), '20250101');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(2), 'abcd1234');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(3), 'abcd1234');
    await tester.pump();

    await tester.tap(find.byType(AppButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repository.signupCalls, 0, reason: '유효하지 않은 폼으로 계정을 만들려 해서는 안 된다');
    expect(repository.loginCalls, 0);

    // 힌트 문구가 에러 문구와 같아서(둘 다 '이름을 입력해주세요') 화면에서
    // 텍스트를 찾는 것만으로는 구분되지 않는다 — errorText 프로퍼티를 직접
    // 본다. 순서는 위젯 트리 순서(학번, 이름, 비밀번호, 비밀번호 확인)다.
    final inputs = tester.widgetList<AppInput>(find.byType(AppInput)).toList();
    expect(inputs, hasLength(4));
    expect(inputs[1].errorText, '이름을 입력해주세요');
    expect(inputs[0].errorText, isNull, reason: '유효한 학번에는 에러가 붙지 않아야 한다');
  });

  // 회원가입은 로그인보다 재진입의 대가가 크다 — 계정이 두 개 만들어질 수
  // 있다. `_isSubmitting`이 버튼을 비활성화하는 것은 다음 프레임부터라
  // 함수 진입 시점의 가드가 없으면 같은 프레임의 두 번째 탭이 통과한다.
  testWidgets('요청이 끝나기 전에 두 번 탭해도 회원가입 요청은 한 번만 나간다', (tester) async {
    final loginGate = Completer<void>();
    final repository = _SignupOkGatedLoginRepository(loginGate.future);
    final host = _hostWithContainer(repository);
    addTearDown(host.container.dispose);

    await tester.pumpWidget(host.widget);
    await tester.pumpAndSettle();
    host.router.push('/signup');
    await tester.pumpAndSettle();

    await _fillValidSignupForm(tester);

    await tester.tap(find.byType(AppButton));
    await tester.tap(find.byType(AppButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repository.loginCalls, 1, reason: '두 번째 탭이 통과하면 자동 로그인도 두 번 나간다');

    loginGate.complete();
    await tester.pumpAndSettle();
    expect(repository.loginCalls, 1);
  });

  // 기존 라이프사이클 테스트는 `signup()` 도중에만 화면을 없애기 때문에
  // 자동 로그인 이후의 mounted 가드에는 도달하지 못한다. 여기서는 회원가입을
  // 통과시킨 뒤 자동 로그인이 진행 중일 때 화면을 없앤다.
  testWidgets('자동 로그인이 진행되는 동안 화면이 사라지면 세션을 건드리지 않는다', (tester) async {
    final loginGate = Completer<void>();
    final repository = _SignupOkGatedLoginRepository(loginGate.future);
    final host = _hostWithContainer(repository);
    addTearDown(host.container.dispose);

    expect(
      await host.container.read(sessionControllerProvider.future),
      isA<SessionSignedOut>(),
    );

    await tester.pumpWidget(host.widget);
    await tester.pumpAndSettle();
    host.router.push('/signup');
    await tester.pumpAndSettle();

    await _fillValidSignupForm(tester);
    await tester.tap(find.byType(AppButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(repository.loginCalls, 1, reason: '회원가입은 이미 통과하고 자동 로그인이 진행 중이어야 한다');

    // 자동 로그인이 아직 끝나지 않은 상태에서 사용자가 뒤로 간다.
    host.router.pop();
    await tester.pumpAndSettle();

    loginGate.complete();
    await tester.pumpAndSettle();

    // mounted 가드가 없으면 사라진 화면의 ref로 onAuthenticated를 부른다 —
    // 예외가 나거나(테스트 실패로 보고된다) 세션이 조용히 바뀐다.
    expect(repository.fetchMeCalls, 0);
    expect(
      host.container.read(sessionControllerProvider).value,
      isA<SessionSignedOut>(),
      reason: '이미 사라진 화면을 대신해 세션을 바꾸면 안 된다',
    );
    expect(await host.store.readAccessToken(), isNull);
  });

  testWidgets(
    '회원가입은 성공했지만 자동 로그인이 실패하면 계정 생성을 알리고 로그인 화면으로 보낸다',
    (tester) async {
      final repository = _SignupSucceedsLoginFailsRepository();
      final router = _buildRouter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(repository),
            tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          ],
          child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.push('/signup');
      await tester.pumpAndSettle();

      await _fillValidSignupForm(tester);
      await tester.tap(find.byType(AppButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(repository.signupCalls, 1);
      expect(repository.loginCalls, 1);

      // 로그인 실패의 원본 메시지("학번 또는 비밀번호가...")가 아니라, 계정은
      // 이미 만들어졌다는 것을 분명히 하는 안내가 떠야 한다.
      expect(find.text('계정이 생성되었습니다. 로그인 화면에서 로그인해주세요.'), findsOneWidget);
      expect(find.text('학번 또는 비밀번호가 올바르지 않습니다.'), findsNothing);

      // 회원가입 화면에 남겨두지 않고 로그인 화면으로 돌려보낸다.
      await tester.pumpAndSettle();
      expect(find.text('로그인 화면 자리'), findsOneWidget);
    },
  );

  testWidgets('제출 요청이 진행 중일 때 화면이 사라져도 예외 없이 끝난다', (tester) async {
    final signupGate = Completer<void>();
    final loginGate = Completer<void>();
    final repository = _GatedRepository(
      signupGate: signupGate.future,
      loginGate: loginGate.future,
    );
    final router = _buildRouter();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        ],
        child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    router.push('/signup');
    await tester.pumpAndSettle();

    await _fillValidSignupForm(tester);
    await tester.tap(find.byType(AppButton));
    await tester.pump();

    // signup()이 아직 게이트에 걸려 끝나지 않은 상태에서 사용자가 뒤로
    // 간다 — SignupScreen이 dispose된다.
    router.pop();
    await tester.pumpAndSettle();

    // 이제 막혀 있던 요청들을 순서대로 풀어준다. 이 테스트가 실제로
    // 지나는 가드는 `_trySignup`의 `if (!mounted) return false;`와 그 뒤
    // `_submit`의 `if (!signedUp || !mounted) return;`, 그리고 finally의
    // `if (mounted) setState`다 — signup()이 끝난 시점에 이미 화면이 없으니
    // 자동 로그인은 시작조차 하지 않는다(loginGate는 여기서 아무 역할도
    // 하지 않는다). 자동 로그인 **이후**의 mounted 가드는 별도 테스트인
    // '자동 로그인이 진행되는 동안 화면이 사라지면 세션을 건드리지 않는다'가
    // 담당한다.
    signupGate.complete();
    await tester.pump();
    loginGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('로그인 화면 자리'), findsOneWidget);
  });
}
