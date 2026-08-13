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

void main() {
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
