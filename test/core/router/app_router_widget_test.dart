import 'package:beacon_app/core/network/dio_provider.dart';
import 'package:beacon_app/core/router/app_router.dart';
import 'package:beacon_app/core/storage/token_store.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:beacon_app/features/auth/data/auth_dto.dart';
import 'package:beacon_app/features/auth/data/auth_repository.dart';
import 'package:beacon_app/features/club/presentation/invite_code_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// `app_router_test.dart`는 `computeRedirect`가 문자열 `"/invite"`를
/// 돌려주는지만 확인하는 순수 함수 테스트다 — 그 문자열이 실제로 어떤
/// 화면과 연결돼 있는지는 전혀 검증하지 않는다. `GoRoute`가 라우트 배열에서
/// 통째로 빠지거나 다른 화면을 가리키게 바뀌어도 그 테스트들은 계속
/// 초록색이다. 이 테스트는 실제 `appRouterProvider`(진짜 GoRouter)를
/// 마운트하고, 로그인은 됐지만 동아리가 없는 사용자를 재현해 정말로
/// `InviteCodeScreen`이 렌더링되는지 확인한다.
class _NeedsClubAuthRepository implements AuthRepository {
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
  Future<MemberProfile> fetchMe() async => const MemberProfile(
        name: '김민준',
        stdId: '20250101',
        clubIds: [],
        pushEnabled: true,
      );
}

void main() {
  testWidgets(
    '실제 appRouterProvider는 clubIds가 비어 있으면 /invite로 이동해 InviteCodeScreen을 렌더링한다',
    (tester) async {
      final store = InMemoryTokenStore();
      await store.save(accessToken: 'a', refreshToken: 'r');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStoreProvider.overrideWithValue(store),
            authRepositoryProvider.overrideWithValue(_NeedsClubAuthRepository()),
          ],
          child: Consumer(
            builder: (context, ref, _) => MaterialApp.router(
              theme: buildAppTheme(),
              routerConfig: ref.watch(appRouterProvider),
            ),
          ),
        ),
      );

      // 세션 판별(비동기 refresh + fetchMe)이 끝나도록 한 박자 흘려보낸다.
      await tester.pump();
      await tester.pump();

      // computeRedirect의 최소 스플래시 노출 시간(1.5초) 판정은 시뮬레이션
      // 시계가 아니라 진짜 DateTime.now()를 쓴다 — tester.pump(duration)은
      // Timer만 진행시킬 뿐 실제 시간은 흐르지 않으므로, runAsync로 진짜
      // 1.6초를 흘려보내야 그 판정을 통과할 수 있다. 그런 다음
      // pump(duration)으로 _SessionListenable의
      // `Timer(minSplashDuration, notifyListeners)`를 실제로 발화시켜
      // go_router가 redirect를 다시 평가하게 만든다.
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 1600)));
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();

      // `/invite` GoRoute가 라우트 트리에서 빠지거나 다른 화면을 가리키면
      // 여기서 InviteCodeScreen을 찾지 못해 이 expect가 실패한다 — 실제로
      // GoRoute를 지워서 확인했다: go_router가 예외를 던지지는 않고,
      // computeRedirect가 여전히 가리키는 "/invite" 경로에 매칭되는 화면이
      // 없으니 InviteCodeScreen이 그냥 렌더링되지 않는다(찾은 위젯 수 0).
      expect(find.byType(InviteCodeScreen), findsOneWidget);
    },
  );
}
