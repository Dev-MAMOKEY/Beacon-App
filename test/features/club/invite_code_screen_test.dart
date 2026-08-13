import 'dart:async';

import 'package:beacon_app/components/ui/button.dart';
import 'package:beacon_app/core/network/api_exception.dart';
import 'package:beacon_app/core/network/error_code.dart';
import 'package:beacon_app/core/storage/token_store.dart';
import 'package:beacon_app/core/network/dio_provider.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:beacon_app/features/auth/data/auth_dto.dart';
import 'package:beacon_app/features/auth/data/auth_repository.dart';
import 'package:beacon_app/features/club/data/club_repository.dart';
import 'package:beacon_app/features/club/presentation/invite_code_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeClubRepository implements ClubRepository {
  _FakeClubRepository({this.shouldFail = false});

  final bool shouldFail;
  final List<String> joined = [];

  @override
  Future<void> joinByInviteCode(String code) async {
    if (shouldFail) {
      throw const ApiException(
        ErrorCode.invalidInviteCode,
        '유효하지 않은 초대코드입니다.',
      );
    }
    joined.add(code);
  }
}

/// [gate]가 완료될 때까지 joinByInviteCode 안에서 멈춘다. "요청이 아직
/// 끝나지 않은 동안" 이라는 시점을 테스트가 결정적으로 만들어낼 수 있게
/// 한다 — 재진입 방지 가드와 mounted 가드는 둘 다 이 시점을 겨냥한 것이라
/// 실제로 그 시점을 만드는 페이크 없이는 검증할 수 없다.
class _GatedClubRepository implements ClubRepository {
  _GatedClubRepository(this._gate);

  final Future<void> _gate;
  int calls = 0;

  @override
  Future<void> joinByInviteCode(String code) async {
    calls++;
    await _gate;
  }
}

/// 가입 성공 시 `_submit` 이 `refreshProfile()` 을 부르고, 그것이
/// `authRepositoryProvider` → `apiClientProvider` → `dioProvider` → `AppConfig` 로
/// 내려간다. 테스트에서는 dotenv가 로드되지 않아 StateError가 나므로
/// 이 provider도 반드시 override 해야 한다.
class _FakeAuthRepository implements AuthRepository {
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
        clubIds: [7],
        pushEnabled: true,
      );
}

Widget _host(ClubRepository repository) {
  return ProviderScope(
    overrides: [
      clubRepositoryProvider.overrideWithValue(repository),
      authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
      tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
    ],
    child: MaterialApp(theme: buildAppTheme(), home: const InviteCodeScreen()),
  );
}

void main() {
  testWidgets('6자리 미만이면 확인 버튼이 비활성이다', (tester) async {
    await tester.pumpWidget(_host(_FakeClubRepository()));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'ABC12');
    await tester.pump();

    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNull);
  });

  testWidgets('입력을 대문자로 변환하고 6자리면 버튼이 활성화된다', (tester) async {
    await tester.pumpWidget(_host(_FakeClubRepository()));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'abc123');
    await tester.pump();

    expect(find.text('ABC123'), findsOneWidget);
    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNotNull);
  });

  testWidgets('가입에 성공하면 대문자 코드를 전송한다', (tester) async {
    final repository = _FakeClubRepository();
    await tester.pumpWidget(_host(repository));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'abc123');
    await tester.pump();
    await tester.tap(find.text('확인'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repository.joined, ['ABC123']);
  });

  testWidgets('유효하지 않은 코드면 메시지를 띄우고 입력을 비운다', (tester) async {
    await tester.pumpWidget(_host(_FakeClubRepository(shouldFail: true)));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'ABC123');
    await tester.pump();
    await tester.tap(find.text('확인'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('유효하지 않은 초대코드입니다. 관리자에게 다시 확인해주세요'),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });

  // 아래 두 테스트는 브리프에는 없던 것을 추가했다. `_isSubmitting`이
  // 버튼을 비활성화하는 것만으로는 재진입을 막지 못한다 — disabled는 다음
  // 프레임(pump)에야 반영되는데, pump 없이 연속으로 탭하면 둘 다 같은
  // 빌드에서 잡힌 옛 onPressed 콜백을 그대로 호출한다. `_submit` 맨 위의
  // `if (_isSubmitting) return;` 가드가 없다면 이 테스트는 실패해야 한다.
  testWidgets('제출이 끝나기 전에 다시 탭해도 가입 요청은 한 번만 나간다', (tester) async {
    final gate = Completer<void>();
    final repository = _GatedClubRepository(gate.future);
    await tester.pumpWidget(_host(repository));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'ABC123');
    await tester.pump();

    // pump() 없이 연속으로 두 번 탭한다 — 첫 탭이 만든 setState는 아직
    // 다음 프레임에 반영되지 않았으므로, 재진입 가드가 없다면 두 번째
    // 탭도 여전히 `_submit`을 그대로 호출한다.
    await tester.tap(find.text('확인'));
    await tester.tap(find.text('확인'));
    await tester.pump();

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repository.calls, 1);
  });

  testWidgets('가입 요청이 진행 중일 때 화면이 사라져도 예외 없이 끝난다', (tester) async {
    final gate = Completer<void>();
    final repository = _GatedClubRepository(gate.future);
    await tester.pumpWidget(_host(repository));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'ABC123');
    await tester.pump();
    await tester.tap(find.text('확인'));
    await tester.pump();

    // joinByInviteCode가 아직 게이트에 걸려 끝나지 않은 상태에서 화면
    // 자체가 트리에서 사라진다 — InviteCodeScreen의 State가 dispose된다.
    await tester.pumpWidget(const SizedBox());

    // 이제 막혀 있던 요청을 풀어준다. mounted 가드가 없다면 dispose된
    // State에서 ref/setState에 접근하다 예외를 던지고, flutter_test는 그
    // 예외를 이 테스트의 실패로 보고한다.
    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  });
}
