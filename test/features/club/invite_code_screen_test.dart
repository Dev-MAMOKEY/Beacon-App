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
import 'package:beacon_app/core/theme/app_colors.dart';
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

/// 6칸 그리드에 한 글자씩 넣는다. Figma가 단일 입력 칸이 아니라 그리드라
/// (`289:3271`) 예전처럼 `enterText(find.byType(TextField), ...)` 한 번으로는
/// 입력할 수 없다(#61).
Future<void> _enterCode(WidgetTester tester, String code) async {
  final fields = find.byType(TextField);
  for (var i = 0; i < code.length && i < fields.evaluate().length; i++) {
    await tester.enterText(fields.at(i), code[i]);
    await tester.pump();
  }
}

String _codeText(WidgetTester tester) => tester
    .widgetList<TextField>(find.byType(TextField))
    .map((field) => field.controller!.text)
    .join();

void main() {
  // 예전에는 고정 Column + Spacer라 작은 화면에서 키보드가 올라오면
  // RenderFlex 오버플로가 났다. flutter_test는 오버플로를 예외로 보고하므로,
  // 좁은 뷰포트에 세우는 것만으로 회귀를 잡을 수 있다.
  testWidgets('키보드가 올라온 작은 화면에서도 오버플로 없이 스크롤된다', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;
    // 키보드가 차지하는 높이를 흉내낸다 — SafeArea가 이만큼을 덜어낸다.
    tester.view.viewInsets = FakeViewPadding(bottom: 260);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_FakeClubRepository()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('승인요청'), findsOneWidget);
  });

  testWidgets('Figma 실측 — 제목·부제·6칸 그리드·안내 카드가 모두 있다', (tester) async {
    // 잡아야 할 잘못된 구현: Phase 1의 단일 입력 칸 + 한 덩어리 제목.
    // 이 화면의 레이아웃은 지금까지 어떤 테스트도 고정하지 않아, 무엇으로
    // 바꿔도 스위트가 초록이었다(#61).
    //
    // 실측 출처: `289:3261` "초대코드 입력" —
    // 제목 `289:3264`(title2/main), 부제 `289:3266`(body2/gray2),
    // 그리드 `289:3271`(6칸), 안내 카드 `318:1459`, 버튼 `289:3287`.
    await tester.pumpWidget(_host(_FakeClubRepository()));
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text('초대코드'));
    expect(title.style!.fontSize, 28, reason: 'title2(28)이다');
    expect(title.style!.color, AppColors.light.main, reason: 'gray3가 아니라 main이다');

    final subtitle = tester.widget<Text>(find.text('관리자에게 받은 6자리 초대코드를 입력해주세요'));
    expect(subtitle.style!.fontSize, 16);
    expect(subtitle.style!.color, AppColors.light.gray2);

    expect(
      find.byType(TextField),
      findsNWidgets(6),
      reason: '단일 입력 칸이 아니라 6칸 그리드다',
    );

    expect(find.text('REQUIREMENT'), findsOneWidget, reason: '안내 카드가 있어야 한다');
    expect(find.text('승인요청'), findsOneWidget, reason: '"확인"이 아니다');
  });

  testWidgets('6자리 미만이면 승인요청 버튼이 비활성이다', (tester) async {
    await tester.pumpWidget(_host(_FakeClubRepository()));
    await tester.pump();

    await _enterCode(tester, 'ABC12');

    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNull);
  });

  testWidgets('입력을 대문자로 변환하고 6자리면 버튼이 활성화된다', (tester) async {
    await tester.pumpWidget(_host(_FakeClubRepository()));
    await tester.pump();

    await _enterCode(tester, 'abc123');

    expect(_codeText(tester), 'ABC123');
    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNotNull);
  });

  testWidgets('영문/숫자가 아닌 문자(공백, 이모지)는 입력되지 않는다', (tester) async {
    await tester.pumpWidget(_host(_FakeClubRepository()));
    await tester.pump();

    // 공백 6개 — String.length로는 6자리를 채우지만 실제로 서버에 보낼 만한
    // 코드가 아니다. FilteringTextInputFormatter가 없다면 공백이 그대로
    // 필드에 남아 6자리를 채운 것처럼 보이고 버튼도 활성화된다(이 테스트가
    // 직접 보는 것은 여기까지다 — 그 뒤 실제로 서버에 전송되는지는 별개로
    // club_repository_test.dart가 확인한다).
    await _enterCode(tester, '      ');
    expect(_codeText(tester), isEmpty, reason: '공백은 애초에 입력되지 않아야 한다');
    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNull);

    // 이모지 3개 — 사용자 체감 글자 수는 3이지만 UTF-16 code unit 길이는
    // 6이다(각 이모지가 서로게이트 쌍 2유닛). 필터링이 없으면 String.length
    // == 6이 돼 버튼이 활성화된다.
    await _enterCode(tester, '😀😀😀');
    expect(_codeText(tester), isEmpty, reason: '이모지도 애초에 입력되지 않아야 한다');
    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNull);
  });

  // 삭제된 테스트: "중간 글자를 수정해도 캐럿이 끝으로 튀지 않는다".
  //
  // 한 칸에 한 글자만 들어가는 그리드(Figma `289:3271`)로 바뀌면서 "문자열
  // 중간에 캐럿을 두고 타이핑한다"는 상황 자체가 사라졌다. `_UpperCaseText
  // Formatter`의 선택 영역 보존 로직은 여전히 옳지만, 이 화면에서 그것을
  // 관측할 방법이 없다 — 남겨 두면 통과하지만 아무것도 증명하지 않는
  // 테스트가 된다(#61).

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

      await _enterCode(tester, 'abc123');
      await tester.pump();
      await tester.tap(find.text('승인요청'));
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

    await _enterCode(tester, 'ABC123');
    await tester.tap(find.text('승인요청'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('유효하지 않은 초대코드입니다. 관리자에게 다시 확인해주세요'),
      findsOneWidget,
    );
    expect(_codeText(tester), isEmpty);
  });

  testWidgets('에러가 뜬 뒤 글자를 입력하면 에러 메시지가 사라진다', (tester) async {
    await tester.pumpWidget(_host(_FakeClubRepository(shouldFail: true)));
    await tester.pump();

    await _enterCode(tester, 'ABC123');
    await tester.tap(find.text('승인요청'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('유효하지 않은 초대코드입니다. 관리자에게 다시 확인해주세요'), findsOneWidget);

    // 입력은 실패 처리 과정에서 이미 비워졌다 — 한 글자만 새로 입력한다.
    await _enterCode(tester, 'Z');

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

      await _enterCode(tester, 'ABC123');
      await tester.tap(find.text('승인요청'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 1차 시도(네트워크 오류): 코드 자체가 틀린 게 아니므로 입력이 남아
      // 있어야 한다 — 지우면 사용자가 맞는 코드를 처음부터 다시 타이핑해야
      // 한다. 세션도 아직 바뀌지 않아야 한다(refreshProfile을 부르지 않음).
      expect(_codeText(tester), 'ABC123');
      expect(harness.container.read(sessionControllerProvider).value, isA<SessionSignedOut>());

      // 같은 코드로 재시도 — 이번엔 ALREADY_CLUB_MEMBER: 1차 시도가 사실
      // 서버에는 이미 반영돼 있었다는 뜻이다. 성공과 동등하게 처리해야 한다.
      await tester.tap(find.text('승인요청'));
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

    await _enterCode(tester, 'ABC123');

    // pump() 없이 연속으로 두 번 탭한다 — 첫 탭이 만든 setState는 아직
    // 다음 프레임에 반영되지 않았으므로, 재진입 가드가 없다면 두 번째
    // 탭도 여전히 `_submit`을 그대로 호출한다.
    await tester.tap(find.text('승인요청'));
    await tester.tap(find.text('승인요청'));
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

    await _enterCode(tester, 'ABC123');
    await tester.tap(find.text('승인요청'));
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
