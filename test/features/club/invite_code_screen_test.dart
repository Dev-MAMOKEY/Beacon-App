import 'dart:async';

import 'package:beacon_app/components/ui/button.dart';
import 'package:beacon_app/core/network/api_exception.dart';
import 'package:beacon_app/core/network/error_code.dart';
import 'package:beacon_app/core/storage/token_store.dart';
import 'package:beacon_app/core/network/dio_provider.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:beacon_app/features/auth/data/auth_dto.dart';
import 'package:beacon_app/features/auth/data/auth_repository.dart';
import 'package:beacon_app/features/auth/presentation/session_controller.dart';
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

/// 첫 시도는 네트워크 오류로 실패하고, 두 번째 시도부터는 ALREADY_CLUB_MEMBER를
/// 던진다 — "서버는 가입을 커밋했는데 응답이 유실돼 클라이언트가 실패로 보고,
/// 사용자가 같은 코드로 재시도한다"는 시나리오를 재현한다.
class _NetworkThenAlreadyMemberRepository implements ClubRepository {
  int calls = 0;

  @override
  Future<void> joinByInviteCode(String code) async {
    calls++;
    if (calls == 1) {
      throw const ApiException(ErrorCode.network, '서버에 연결하지 못했습니다.');
    }
    throw const ApiException(ErrorCode.alreadyClubMember, '이미 가입된 동아리입니다.');
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

/// 가입 성공(혹은 ALREADY_CLUB_MEMBER) 시 `_submit`이 `refreshProfile()`을
/// 부르고, 그것이 `authRepositoryProvider` → `apiClientProvider` →
/// `dioProvider` → `AppConfig`로 내려간다. 테스트에서는 dotenv가 로드되지
/// 않아 StateError가 나므로 이 provider도 반드시 override 해야 한다.
///
/// `fetchMeCalls`는 refreshProfile()이 실제로 fetchMe를 불렀는지 세기 위한
/// 것이다 — "가입 요청은 보냈지만 사용자를 전혀 진전시키지 않는" 구현을
/// 잡아내려면 요청을 보냈다는 사실만으로는 부족하고, 그 뒤에 프로필을 다시
/// 읽었는지까지 봐야 한다.
class _FakeAuthRepository implements AuthRepository {
  int fetchMeCalls = 0;

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

/// [_host]와 달리 [ProviderContainer]를 직접 만들어 돌려준다 — 화면 밖에서
/// `sessionControllerProvider`의 최종 상태(SessionReady가 됐는지 등)를
/// 확인해야 하는 테스트용이다.
({Widget widget, ProviderContainer container}) _hostWithContainer(
  ClubRepository clubRepository, {
  required _FakeAuthRepository authRepository,
}) {
  final container = ProviderContainer(
    overrides: [
      clubRepositoryProvider.overrideWithValue(clubRepository),
      authRepositoryProvider.overrideWithValue(authRepository),
      tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
    ],
  );
  return (
    widget: UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildAppTheme(), home: const InviteCodeScreen()),
    ),
    container: container,
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

  testWidgets('영문/숫자가 아닌 문자(공백, 이모지)는 입력되지 않는다', (tester) async {
    await tester.pumpWidget(_host(_FakeClubRepository()));
    await tester.pump();

    // 공백 6개 — String.length로는 6자리를 채우지만 실제로 서버에 보낼 만한
    // 코드가 아니다. FilteringTextInputFormatter가 없다면 버튼이 활성화되고
    // 공백이 그대로 전송된다.
    await tester.enterText(find.byType(TextField), '      ');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
      reason: '공백은 애초에 입력되지 않아야 한다',
    );
    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNull);

    // 이모지 3개 — 사용자 체감 글자 수는 3이지만 UTF-16 code unit 길이는
    // 6이다(각 이모지가 서로게이트 쌍 2유닛). 필터링이 없으면 String.length
    // == 6이 돼 버튼이 활성화된다.
    await tester.enterText(find.byType(TextField), '😀😀😀');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
      reason: '이모지도 애초에 입력되지 않아야 한다',
    );
    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNull);
  });

  testWidgets('중간 글자를 수정해도 캐럿이 끝으로 튀지 않는다', (tester) async {
    await tester.pumpWidget(_host(_FakeClubRepository()));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'ab12');
    await tester.pump();

    await tester.showKeyboard(find.byType(TextField));
    // 커서가 'a' 바로 뒤(오프셋 1)에 있는 상태에서 소문자 'z'를 끼워 넣는
    // 것을 시뮬레이션한다 — 실기기에서 캐럿을 문자열 중간에 두고 타이핑하는
    // 것과 같다. TextEditingValue를 통째로 새로 만들어 selection을 항상
    // 끝으로 보내는 구현이라면, 여기서 만든 새 커서는 오프셋 5(문자열 끝)로
    // 튀어야 정상(=버그)이다.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'azb12',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();

    final controller = tester.widget<TextField>(find.byType(TextField)).controller!;
    expect(controller.text, 'AZB12');
    expect(
      controller.selection,
      const TextSelection.collapsed(offset: 2),
      reason: '캐럿은 방금 입력한 글자 바로 뒤(오프셋 2)에 남아 있어야 한다 — 끝으로 튀면 안 된다',
    );
  });

  testWidgets(
    '가입에 성공하면 대문자 코드를 전송하고, 프로필을 다시 읽어 세션이 SessionReady가 된다',
    (tester) async {
      final clubRepository = _FakeClubRepository();
      final authRepository = _FakeAuthRepository();
      final harness = _hostWithContainer(clubRepository, authRepository: authRepository);
      addTearDown(harness.container.dispose);

      await tester.pumpWidget(harness.widget);
      // 세션의 최초 판별(토큰 없음 → SessionSignedOut)이 먼저 끝나게 한다.
      // 그래야 아래에서 확인하는 상태 변화가 오롯이 가입 성공에 따른
      // refreshProfile() 호출 때문이라고 말할 수 있다 — 최초 판별과
      // refreshProfile()이 우연히 겹치는 경합에 테스트 결과가 좌우되지
      // 않는다.
      await harness.container.read(sessionControllerProvider.future);
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'abc123');
      await tester.pump();
      await tester.tap(find.text('확인'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(clubRepository.joined, ['ABC123']);
      // 가입 요청만 보내고 사용자를 실제로 진전시키지 않는 구현(예:
      // refreshProfile() 호출이 빠진 구현)을 잡아낸다 — 이 화면이 존재하는
      // 이유 자체가 "가입 성공 시 세션을 갱신해 홈으로 보낸다"이므로, 서버에
      // 요청을 보냈다는 사실만으로는 부족하다.
      expect(authRepository.fetchMeCalls, 1);
      expect(harness.container.read(sessionControllerProvider).value, isA<SessionReady>());
    },
  );

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

  testWidgets('에러가 뜬 뒤 글자를 입력하면 에러 메시지가 사라진다', (tester) async {
    await tester.pumpWidget(_host(_FakeClubRepository(shouldFail: true)));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'ABC123');
    await tester.pump();
    await tester.tap(find.text('확인'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('유효하지 않은 초대코드입니다. 관리자에게 다시 확인해주세요'), findsOneWidget);

    // 입력은 실패 처리 과정에서 이미 비워졌다 — 한 글자만 새로 입력한다.
    await tester.enterText(find.byType(TextField), 'Z');
    await tester.pump();

    expect(find.text('유효하지 않은 초대코드입니다. 관리자에게 다시 확인해주세요'), findsNothing);
  });

  testWidgets(
    '네트워크 오류에서는 입력이 남고, 같은 코드로 재시도해 ALREADY_CLUB_MEMBER를 받으면 결국 SessionReady로 끝난다',
    (tester) async {
      final clubRepository = _NetworkThenAlreadyMemberRepository();
      final authRepository = _FakeAuthRepository();
      final harness = _hostWithContainer(clubRepository, authRepository: authRepository);
      addTearDown(harness.container.dispose);

      await tester.pumpWidget(harness.widget);
      await harness.container.read(sessionControllerProvider.future);
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'ABC123');
      await tester.pump();
      await tester.tap(find.text('확인'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 1차 시도(네트워크 오류): 코드 자체가 틀린 게 아니므로 입력이 남아
      // 있어야 한다 — 지우면 사용자가 맞는 코드를 처음부터 다시 타이핑해야
      // 한다. 세션도 아직 바뀌지 않아야 한다(refreshProfile을 부르지 않음).
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'ABC123',
      );
      expect(harness.container.read(sessionControllerProvider).value, isA<SessionSignedOut>());

      // 같은 코드로 재시도 — 이번엔 ALREADY_CLUB_MEMBER: 1차 시도가 사실
      // 서버에는 이미 반영돼 있었다는 뜻이다. 성공과 동등하게 처리해야 한다.
      await tester.tap(find.text('확인'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(clubRepository.calls, 2);
      expect(harness.container.read(sessionControllerProvider).value, isA<SessionReady>());
    },
  );

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
