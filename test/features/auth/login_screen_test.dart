import 'dart:async';

import 'package:beacon_app/core/network/api_exception.dart';
import 'package:beacon_app/core/network/error_code.dart';
import 'package:beacon_app/core/storage/token_store.dart';
import 'package:beacon_app/core/network/dio_provider.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:beacon_app/features/auth/data/auth_dto.dart';
import 'package:beacon_app/features/auth/data/auth_repository.dart';
import 'package:beacon_app/components/ui/button.dart';
import 'package:beacon_app/components/ui/input.dart';
import 'package:beacon_app/features/auth/presentation/login_screen.dart';
import 'package:beacon_app/features/auth/presentation/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _LoginFailsRepository implements AuthRepository {
  @override
  Future<TokenResponse> login({required String stdId, required String password}) async {
    throw const ApiException(
      ErrorCode.invalidCredentials,
      '학번 또는 비밀번호가 올바르지 않습니다.',
    );
  }

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
  Future<MemberProfile> fetchMe() async => const MemberProfile(
        name: '김민준',
        stdId: '20250101',
        clubIds: [1],
        pushEnabled: true,
      );
}

/// 로그인이 성공하는 리포지토리. 성공 경로를 검증하는 테스트가 하나도 없어서
/// `onAuthenticated(tokens)` 호출을 통째로 지워도 115개 테스트가 전부
/// 통과했다 — 로그인 버튼이 세션을 실제로 만들어내는지가 아무 데서도
/// 확인되지 않았다는 뜻이다.
class _LoginSucceedsRepository implements AuthRepository {
  int loginCalls = 0;
  int fetchMeCalls = 0;

  @override
  Future<TokenResponse> login({required String stdId, required String password}) async {
    loginCalls++;
    return const TokenResponse(accessToken: 'login-a', refreshToken: 'login-r');
  }

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
  Future<MemberProfile> fetchMe() async {
    fetchMeCalls++;
    return const MemberProfile(
      name: '김민준',
      stdId: '20250101',
      clubIds: [7],
      pushEnabled: true,
    );
  }
}

/// [gate]가 완료될 때까지 `login()` 안에서 멈춘다 — "요청이 아직 끝나지
/// 않은 동안"을 결정적으로 만들어야 재진입 가드를 검증할 수 있다.
class _GatedLoginRepository implements AuthRepository {
  _GatedLoginRepository(this._gate);

  final Future<void> _gate;
  int loginCalls = 0;

  @override
  Future<TokenResponse> login({required String stdId, required String password}) async {
    loginCalls++;
    await _gate;
    return const TokenResponse(accessToken: 'login-a', refreshToken: 'login-r');
  }

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
  Future<MemberProfile> fetchMe() async => const MemberProfile(
        name: '김민준',
        stdId: '20250101',
        clubIds: [7],
        pushEnabled: true,
      );
}

/// 화면 밖에서 `sessionControllerProvider`의 최종 상태와 저장된 토큰을
/// 확인해야 하는 테스트용 호스트.
({Widget widget, ProviderContainer container, InMemoryTokenStore store}) _hostWithContainer(
  AuthRepository repository,
) {
  final store = InMemoryTokenStore();
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(repository),
      tokenStoreProvider.overrideWithValue(store),
    ],
  );
  return (
    widget: UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildAppTheme(), home: const LoginScreen()),
    ),
    container: container,
    store: store,
  );
}

Future<void> _fillCredentials(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(0), '20250101');
  await tester.pump();
  await tester.enterText(find.byType(TextField).at(1), 'abcd1234');
  await tester.pump();
}

void main() {
  testWidgets('로그인에 성공하면 세션이 만들어지고 토큰이 저장된다', (tester) async {
    final repository = _LoginSucceedsRepository();
    final host = _hostWithContainer(repository);
    addTearDown(host.container.dispose);

    // 실제 앱처럼 최초 세션 판별(저장된 토큰 없음 → SignedOut)을 먼저 끝낸다.
    final initial = await host.container.read(sessionControllerProvider.future);
    expect(initial, isA<SessionSignedOut>());

    await tester.pumpWidget(host.widget);
    await tester.pump();

    await _fillCredentials(tester);
    await tester.tap(find.text('로그인'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repository.loginCalls, 1);
    // 로그인 응답을 받는 것만으로는 부족하다 — 그 토큰이 세션 컨트롤러까지
    // 흘러가 프로필을 읽고 상태를 바꿨는지 확인한다.
    expect(repository.fetchMeCalls, 1);
    expect(
      host.container.read(sessionControllerProvider).value,
      isA<SessionReady>(),
      reason: 'onAuthenticated를 부르지 않으면 화면은 조용히 로그인 화면에 머문다',
    );
    expect(await host.store.readAccessToken(), 'login-a');
    expect(await host.store.readRefreshToken(), 'login-r');
  });

  // `_isSubmitting`이 버튼을 비활성화하는 것만으로는 재진입을 막지 못한다 —
  // disabled는 다음 프레임에서야 반영되므로 같은 프레임 안에서 두 번 탭하면
  // 두 번째 탭도 여전히 살아있는 onPressed를 부른다.
  testWidgets('요청이 끝나기 전에 두 번 탭해도 로그인 요청은 한 번만 나간다', (tester) async {
    final gate = Completer<void>();
    final repository = _GatedLoginRepository(gate.future);
    final host = _hostWithContainer(repository);
    addTearDown(host.container.dispose);

    await tester.pumpWidget(host.widget);
    await tester.pump();

    await _fillCredentials(tester);

    // 두 탭 사이에 pump가 없다 — 첫 탭의 setState가 아직 프레임에 반영되지
    // 않았으므로, 재진입 가드가 없다면 두 번째 탭이 login()을 또 부른다.
    await tester.tap(find.text('로그인'));
    await tester.tap(find.text('로그인'));
    await tester.pump();

    expect(repository.loginCalls, 1);

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(repository.loginCalls, 1);
  });

  testWidgets('로그인 실패 시 필드가 아닌 화면 단위 메시지를 보여준다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_LoginFailsRepository()),
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        ],
        child: MaterialApp(theme: buildAppTheme(), home: const LoginScreen()),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(0), '20250101');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'abcd1234');
    await tester.pump();
    await tester.tap(find.text('로그인'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('학번 또는 비밀번호가 올바르지 않습니다.'), findsOneWidget);

    // 명세서 보안 요구사항: 어느 필드가 틀렸는지 노출하지 않는다. 메시지가
    // 화면 어딘가에 있다는 것만으로는 부족하다 — 그 메시지를 AppInput의
    // errorText(필드 밑줄 에러)로 꽂아 넣는 구현도 이 텍스트를 화면에
    // 보여주긴 하지만 요구사항을 위반한다. 그런 구현이 아님을 직접
    // 확인한다: 학번/비밀번호 두 AppInput 모두 errorText가 비어 있어야
    // 한다(비밀번호는 AppPasswordInput 내부에 중첩된 AppInput이다).
    final inputs = tester.widgetList<AppInput>(find.byType(AppInput));
    expect(inputs, hasLength(2));
    for (final input in inputs) {
      expect(
        input.errorText,
        anyOf(isNull, isEmpty),
        reason: '로그인 실패는 필드별 에러가 아니라 화면 단위 메시지여야 한다',
      );
    }
  });

  testWidgets('두 필드가 비어 있으면 로그인 버튼이 비활성이다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_LoginFailsRepository()),
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        ],
        child: MaterialApp(theme: buildAppTheme(), home: const LoginScreen()),
      ),
    );
    await tester.pump();

    final button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('한쪽 필드만 채워지면 로그인 버튼이 비활성이다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_LoginFailsRepository()),
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        ],
        child: MaterialApp(theme: buildAppTheme(), home: const LoginScreen()),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(0), '20250101');
    await tester.pump();
    expect(
      tester.widget<AppButton>(find.byType(AppButton)).onPressed,
      isNull,
      reason: '학번만 채워지고 비밀번호가 비어 있으면 여전히 비활성이어야 한다',
    );

    await tester.enterText(find.byType(TextField).at(0), '');
    await tester.enterText(find.byType(TextField).at(1), 'abcd1234');
    await tester.pump();
    expect(
      tester.widget<AppButton>(find.byType(AppButton)).onPressed,
      isNull,
      reason: '비밀번호만 채워지고 학번이 비어 있으면 여전히 비활성이어야 한다',
    );
  });
}
