import 'package:beacon_app/components/ui/button.dart';
import 'package:beacon_app/core/network/api_exception.dart';
import 'package:beacon_app/core/network/dio_provider.dart';
import 'package:beacon_app/core/network/error_code.dart';
import 'package:beacon_app/core/storage/token_store.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:beacon_app/features/auth/data/auth_dto.dart';
import 'package:beacon_app/features/auth/data/auth_repository.dart';
import 'package:beacon_app/features/auth/presentation/session_controller.dart';
import 'package:beacon_app/features/auth/presentation/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 스플래시의 재시도 UI(메시지 + 재시도 버튼)는 어디서도 검증되지 않았다 —
/// 그 두 위젯을 통째로 지워도 115개 테스트가 전부 통과했다. 그 상태에서
/// 오프라인 사용자는 메시지도 버튼도 없는 스플래시에 영구히 갇힌다.
///
/// 첫 번째 호출만 네트워크 오류로 실패하고 그 뒤로는 성공한다 — "재시도가
/// 실제로 다시 판별을 돌린다"를 확인하기 위한 용도.
class _FlakyAuthRepository implements AuthRepository {
  static const int refreshFailures = 1;

  int refreshCalls = 0;

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
  Future<TokenResponse> refresh(String refreshToken) async {
    refreshCalls++;
    if (refreshCalls <= refreshFailures) {
      throw const ApiException(ErrorCode.network, '서버에 연결하지 못했습니다.');
    }
    return const TokenResponse(accessToken: 'a2', refreshToken: 'r2');
  }

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

Future<({ProviderContainer container, InMemoryTokenStore store})> _pumpSplash(
  WidgetTester tester,
  AuthRepository repository, {
  bool withStoredTokens = true,
}) async {
  final store = InMemoryTokenStore();
  if (withStoredTokens) await store.save(accessToken: 'a', refreshToken: 'r');

  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(repository),
      tokenStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildAppTheme(), home: const SplashScreen()),
    ),
  );
  await tester.pumpAndSettle();

  return (container: container, store: store);
}

void main() {
  testWidgets('세션 판별에 실패하면 사유와 재시도 버튼을 보여준다', (tester) async {
    await _pumpSplash(tester, _FlakyAuthRepository());

    expect(find.text('서버에 연결하지 못했습니다.'), findsOneWidget);
    expect(find.text('재시도'), findsOneWidget);
  });

  testWidgets('재시도를 누르면 세션을 다시 판별하고 성공하면 재시도 UI가 사라진다', (tester) async {
    final repository = _FlakyAuthRepository();
    final host = await _pumpSplash(tester, repository);

    expect(repository.refreshCalls, 1);
    expect(host.container.read(sessionControllerProvider).value, isA<SessionUnavailable>());

    await tester.tap(find.text('재시도'));
    await tester.pumpAndSettle();

    expect(repository.refreshCalls, 2, reason: '재시도 버튼은 실제로 판별을 다시 돌려야 한다');
    expect(host.container.read(sessionControllerProvider).value, isA<SessionReady>());
    expect(find.text('서버에 연결하지 못했습니다.'), findsNothing);
    expect(find.text('재시도'), findsNothing);
  });

  testWidgets('정상적으로 판별되면 재시도 UI를 보여주지 않는다', (tester) async {
    // 저장된 토큰이 없으면 곧바로 SignedOut — 실패가 아니므로 재시도 UI가
    // 뜨면 안 된다.
    await _pumpSplash(tester, _FlakyAuthRepository(), withStoredTokens: false);

    expect(find.text('재시도'), findsNothing);
    expect(find.byType(AppButton), findsNothing);
    // 서비스명은 어떤 상태에서든 항상 보인다.
    expect(find.text('마모키'), findsOneWidget);
  });
}
