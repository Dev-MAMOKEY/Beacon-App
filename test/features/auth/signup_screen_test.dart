import 'dart:async';

import 'package:beacon_app/components/ui/button.dart';
import 'package:beacon_app/core/network/api_exception.dart';
import 'package:beacon_app/core/network/dio_provider.dart';
import 'package:beacon_app/core/network/error_code.dart';
import 'package:beacon_app/core/storage/token_store.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:beacon_app/features/auth/data/auth_dto.dart';
import 'package:beacon_app/features/auth/data/auth_repository.dart';
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

void main() {
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

    // 이제 막혀 있던 요청들을 순서대로 풀어준다. mounted 가드가 없다면
    // dispose된 State에서 컨트롤러/ref/context에 접근하다 예외를 던지고,
    // flutter_test는 그 예외를 이 테스트의 실패로 보고한다.
    signupGate.complete();
    await tester.pump();
    loginGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('로그인 화면 자리'), findsOneWidget);
  });
}
