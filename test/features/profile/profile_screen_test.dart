import 'dart:async';

import 'package:beacon_app/components/ui/app_switch.dart';
import 'package:beacon_app/core/network/api_exception.dart';
import 'package:beacon_app/core/network/dio_provider.dart';
import 'package:beacon_app/core/network/error_code.dart';
import 'package:beacon_app/core/storage/token_store.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:beacon_app/features/auth/data/auth_dto.dart';
import 'package:beacon_app/features/auth/data/auth_repository.dart';
import 'package:beacon_app/features/auth/presentation/session_controller.dart';
import 'package:beacon_app/features/profile/data/profile_repository.dart';
import 'package:beacon_app/features/profile/presentation/password_change_popup.dart';
import 'package:beacon_app/features/profile/presentation/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 세션이 들고 시작할 프로필. 테스트마다 override한다.
final _seedProfileProvider = Provider<MemberProfile>(
  (ref) => throw UnimplementedError('테스트가 override해야 한다'),
);

class _ReadySessionController extends SessionController {
  @override
  Future<SessionState> build() async => SessionReady(ref.read(_seedProfileProvider));
}

typedef _UpdateCall = ({String name, String? title, bool? pushEnabled});

/// 호출 인자를 전부 기록하고, 성패를 테스트가 정할 수 있는 페이크.
class _RecordingProfileRepository implements ProfileRepository {
  _RecordingProfileRepository({this.updateFailure});

  /// null이 아니면 [updateProfile]이 이 예외로 끝난다. 토글 실패 시나리오가
  /// 요청이 나간 **뒤에** 값을 바꾸므로(겹친 토글 테스트) 가변이다.
  ApiException? updateFailure;

  /// [gateUpdate]가 true면 [releaseUpdate]를 부를 때까지 응답이 오지 않는다 —
  /// 겹친 토글 요청을 재현하는 데 쓴다.
  bool gateUpdate = false;
  final List<Completer<void>> _pendingUpdates = [];

  final List<_UpdateCall> updateCalls = [];
  final List<({String current, String next, String confirm})> changeCalls = [];

  @override
  Future<void> updateProfile({
    required String name,
    String? title,
    bool? pushEnabled,
  }) async {
    updateCalls.add((name: name, title: title, pushEnabled: pushEnabled));
    if (gateUpdate) {
      final completer = Completer<void>();
      _pendingUpdates.add(completer);
      await completer.future;
    }
    final failure = updateFailure;
    if (failure != null) throw failure;
  }

  /// 대기 중인 갱신 하나를 풀어 준다. 대기 중인 것이 없으면 던진다 —
  /// 조용히 no-op이 되면 재현하려던 상황이 만들어지지 않았는데도 초록색이 된다.
  void releaseUpdate() {
    if (_pendingUpdates.isEmpty) throw StateError('대기 중인 updateProfile이 없다');
    _pendingUpdates.removeAt(0).complete();
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmNewPassword,
  }) async {
    changeCalls.add((
      current: currentPassword,
      next: newPassword,
      confirm: confirmNewPassword,
    ));
  }
}

/// 로그아웃이 실제로 `SessionController.signOut()`을 탔는지 보는 관측점.
/// 화면이 토큰 저장소를 직접 지우는 식으로 우회하면 이 카운터가 늘지 않는다.
class _RecordingAuthRepository implements AuthRepository {
  int logoutCalls = 0;

  @override
  Future<void> logout() async => logoutCalls++;

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
  Future<MemberProfile> fetchMe() async => throw UnimplementedError(
    '마이페이지는 프로필을 다시 조회하지 않는다 — 여기 걸리면 refreshProfile()을 부른 것이다',
  );
}

typedef _Harness = ({
  ProviderContainer container,
  _RecordingProfileRepository repository,
  _RecordingAuthRepository auth,
  ValueNotifier<bool> visible,
});

Future<_Harness> _pumpProfile(
  WidgetTester tester, {
  _RecordingProfileRepository? repository,
  String name = '김민준',
  String stdId = '20261953',
  bool pushEnabled = false,
}) async {
  final repo = repository ?? _RecordingProfileRepository();
  final auth = _RecordingAuthRepository();
  final store = InMemoryTokenStore();
  await store.save(accessToken: 'a', refreshToken: 'r');

  final container = ProviderContainer(
    overrides: [
      _seedProfileProvider.overrideWithValue(
        MemberProfile(name: name, stdId: stdId, clubIds: const [7], pushEnabled: pushEnabled),
      ),
      sessionControllerProvider.overrideWith(_ReadySessionController.new),
      profileRepositoryProvider.overrideWithValue(repo),
      authRepositoryProvider.overrideWithValue(auth),
      tokenStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(container.dispose);

  // `StatefulShellRoute.indexedStack`이 숨은 브랜치를 감싸는 방식 그대로 —
  // 탭 전환은 dispose가 아니라 TickerMode를 끄는 것이다.
  final visible = ValueNotifier<bool>(true);
  addTearDown(visible.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAppTheme(),
        // 실제 앱에서는 AppShell의 Scaffold 안에서 렌더된다 —
        // `showAppToast`가 ScaffoldMessenger를 찾을 수 있어야 한다.
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (context, enabled, child) =>
                TickerMode(enabled: enabled, child: child!),
            child: const ProfileScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return (container: container, repository: repo, auth: auth, visible: visible);
}

bool _switchValue(WidgetTester tester) =>
    tester.widget<AppSwitch>(find.byType(AppSwitch)).value;

void main() {
  testWidgets('학번은 표시만 되고 어떤 입력 칸으로도 렌더되지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: 학번을 `TextField`(또는 AppInput)로 그려
    // 수정 가능한 것처럼 보이게 한다. 서버에는 학번을 바꾸는 API가 없다.
    await _pumpProfile(tester);

    expect(find.text('20261953'), findsOneWidget);
    expect(
      find.byType(EditableText),
      findsNothing,
      reason: '마이페이지 본문에는 편집 가능한 칸이 하나도 없다 — 이름조차 팝업에서만 고친다',
    );
  });

  testWidgets('연필을 눌러 이름을 고치면 입력한 이름으로 updateProfile이 불린다', (tester) async {
    // 잡아야 할 잘못된 구현: updateProfile을 아예 안 부른다(로컬 상태만
    // 바꾼다), 또는 입력값 대신 원래 이름을 그대로 보낸다.
    final harness = await _pumpProfile(tester);

    await tester.tap(find.bySemanticsLabel('이름 변경'));
    await tester.pumpAndSettle();
    expect(find.text('이름 변경'), findsWidgets);

    await tester.enterText(find.byType(TextField), '박서준');
    await tester.tap(find.text('수정하기'));
    await tester.pumpAndSettle();

    expect(harness.repository.updateCalls, hasLength(1));
    expect(harness.repository.updateCalls.single.name, '박서준');
    // 이름만 바꾸는 요청이라 알림 값은 건드리지 않는다.
    expect(harness.repository.updateCalls.single.pushEnabled, isNull);
    // 팝업이 닫히고 화면의 이름도 새 값이어야 한다 — 세션에 반영하지 않으면
    // 홈 탭 상단 바가 옛 이름을 계속 보여준다.
    expect(find.text('수정하기'), findsNothing);
    expect(find.text('박서준'), findsOneWidget);
    expect(find.text('김민준'), findsNothing);
  });

  testWidgets('이름 형식이 틀리면 updateProfile을 부르지 않고 Phase 1 문구를 보여준다', (tester) async {
    // 잡아야 할 잘못된 구현: 검증 없이 그대로 서버에 보낸다, 또는
    // `AuthFormValidator.name` 대신 자체 규칙을 새로 쓴다(회원가입과 마이
    // 페이지가 서로 다른 이름 규칙을 갖게 된다).
    final harness = await _pumpProfile(tester);

    await tester.tap(find.bySemanticsLabel('이름 변경'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '김');
    await tester.tap(find.text('수정하기'));
    await tester.pumpAndSettle();

    expect(harness.repository.updateCalls, isEmpty);
    expect(find.text('이름은 한글 또는 영문 2~20자여야 합니다'), findsOneWidget);
  });

  testWidgets('토글을 켜면 pushEnabled: true와 현재 이름이 함께 전송된다', (tester) async {
    // 잡아야 할 잘못된 구현: `{"pushEnabled": true}`만 보낸다 — `name`은
    // 필수라 서버가 400을 내고 토글이 조용히 되돌아간다.
    final harness = await _pumpProfile(tester);
    expect(_switchValue(tester), isFalse);

    await tester.tap(find.byType(AppSwitch));
    await tester.pumpAndSettle();

    expect(harness.repository.updateCalls, hasLength(1));
    expect(harness.repository.updateCalls.single.name, '김민준');
    expect(harness.repository.updateCalls.single.pushEnabled, isTrue);
    expect(_switchValue(tester), isTrue);
  });

  testWidgets('토글 API가 실패하면 토글이 원래 상태로 되돌아가고 토스트가 뜬다', (tester) async {
    // 잡아야 할 잘못된 구현: 낙관적으로 켠 채 그대로 둔다 — 화면은 알림이
    // 켜졌다고 말하는데 서버는 꺼져 있다. 또는 "되돌리기"를 실패 시점에
    // 다시 읽은 값으로 하는 바람에(이미 우리가 써 넣은 값이다) 아무것도
    // 되돌리지 못한다.
    final repository = _RecordingProfileRepository(
      updateFailure: const ApiException(ErrorCode.network, '서버에 연결하지 못했습니다.'),
    );
    await _pumpProfile(tester, repository: repository);
    expect(_switchValue(tester), isFalse);

    await tester.tap(find.byType(AppSwitch));
    await tester.pumpAndSettle();

    expect(_switchValue(tester), isFalse, reason: '실패했으면 켜진 채로 남아서는 안 된다');
    expect(find.text('서버에 연결하지 못했습니다.'), findsOneWidget);
  });

  testWidgets('겹친 토글에서 먼저 보낸 요청의 실패가 최신 상태를 덮어쓰지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: 세대 검사 없이 실패마다 되돌린다 — 켜기(실패
    // 예정)와 끄기가 겹치면, 나중에 도착한 첫 요청의 실패가 "원래 값"인
    // false를... 가 아니라 자기가 기억하는 previous로 되돌리며 최신 결정을
    // 지운다. 여기서는 두 번째(끄기)가 성공했는데도 화면이 켜짐으로
    // 되돌아가는 모습으로 나타난다.
    final repository = _RecordingProfileRepository()..gateUpdate = true;
    await _pumpProfile(tester, repository: repository, pushEnabled: false);

    // 1) 켜기 — 응답을 붙잡아 둔다.
    await tester.tap(find.byType(AppSwitch));
    await tester.pump();
    expect(_switchValue(tester), isTrue);

    // 2) 곧바로 끄기 — 첫 요청이 아직 떠 있으므로 새 요청은 나가지 않고
    // 의도만 갱신된다(직렬화).
    await tester.tap(find.byType(AppSwitch));
    await tester.pump();
    expect(_switchValue(tester), isFalse);
    expect(repository.updateCalls, hasLength(1));

    // 이제 첫 요청만 실패시킨다.
    repository.updateFailure = const ApiException(ErrorCode.network, '서버에 연결하지 못했습니다.');
    repository.releaseUpdate();
    await tester.pumpAndSettle();

    expect(
      _switchValue(tester),
      isFalse,
      reason: '이미 밀려난 옛 요청의 실패가 최신 결정(끄기)을 되돌려서는 안 된다',
    );
    expect(
      find.text('서버에 연결하지 못했습니다.'),
      findsNothing,
      reason: '최종 의도(끄기)는 서버 값과 이미 같으므로 사용자에게 실패할 일이 없었다',
    );
  });

  testWidgets('토글을 겹쳐 눌러도 서버로는 한 번에 하나씩만 나간다', (tester) async {
    // 잡아야 할 잘못된 구현: 누를 때마다 곧바로 PATCH를 띄운다 — 응답을
    // 아무리 잘 걸러도 **서버 도착 순서**를 정할 수 없어, 켜기·끄기가
    // 뒤바뀌어 닿으면 서버는 켜짐, 화면은 꺼짐으로 끝난다(리뷰 Critical 1의
    // 역순 성공). 직렬화만이 이걸 막는다.
    final repository = _RecordingProfileRepository()..gateUpdate = true;
    await _pumpProfile(tester, repository: repository, pushEnabled: false);

    await tester.tap(find.byType(AppSwitch));
    await tester.pump();
    await tester.tap(find.byType(AppSwitch));
    await tester.pump();
    await tester.tap(find.byType(AppSwitch));
    await tester.pump();

    expect(
      repository.updateCalls,
      hasLength(1),
      reason: '첫 요청이 아직 떠 있는 동안에는 두 번째 요청을 보내지 않는다',
    );
    expect(repository.updateCalls.single.pushEnabled, isTrue);
    expect(_switchValue(tester), isTrue, reason: '화면은 낙관적으로 최신 의도를 보여준다');
  });

  testWidgets('겹쳐 누른 토글이 둘 다 실패하면 화면이 서버가 확인해 준 값으로 돌아간다', (tester) async {
    // 잡아야 할 잘못된 구현: 되돌릴 값을 **눌린 시점의 화면 값**에서 잡는다.
    // 그 값은 앞선 토글이 이미 낙관적으로 써 넣은 것이라 확인된 적이 없다.
    // 켜기·끄기를 연달아 누르고 둘 다 실패하면 화면은 켜짐, 서버는 꺼짐으로
    // 갈라진다 — 낙관적 UI가 거짓말을 한다(리뷰 Critical 1).
    final repository = _RecordingProfileRepository()..gateUpdate = true;
    await _pumpProfile(tester, repository: repository, pushEnabled: false);

    // 켜기 → 끄기 → 켜기. 최종 의도는 '켜기'이고 서버가 확인해 준 값은 없다.
    await tester.tap(find.byType(AppSwitch));
    await tester.pump();
    await tester.tap(find.byType(AppSwitch));
    await tester.pump();
    await tester.tap(find.byType(AppSwitch));
    await tester.pump();
    expect(_switchValue(tester), isTrue);

    repository.updateFailure = const ApiException(ErrorCode.network, '서버에 연결하지 못했습니다.');
    repository.releaseUpdate();
    await tester.pumpAndSettle();

    expect(
      _switchValue(tester),
      isFalse,
      reason: '서버가 확인해 준 값은 처음의 false뿐이다 — 낙관적 값으로 되돌리면 안 된다',
    );
    expect(
      find.text('서버에 연결하지 못했습니다.'),
      findsOneWidget,
      reason: '최종 의도(켜기)가 반영되지 못했으므로 사용자에게 알려야 한다',
    );
  });

  testWidgets('로그아웃은 확인 팝업을 먼저 띄우고, 취소하면 signOut을 부르지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: 버튼을 누르는 즉시 로그아웃한다 — 오탭 한
    // 번으로 세션이 날아간다.
    final harness = await _pumpProfile(tester);

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();

    // 확인 팝업이 실제로 떠 있어야 한다(로그아웃 버튼 + 팝업 제목 + 팝업의
    // 실행 버튼이 있어 '로그아웃' 텍스트가 여럿이다).
    expect(find.text('정말 로그아웃할까요?'), findsOneWidget);
    expect(harness.auth.logoutCalls, 0, reason: '팝업만 떴을 뿐 아직 아무것도 결정하지 않았다');

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(find.text('정말 로그아웃할까요?'), findsNothing);
    expect(harness.auth.logoutCalls, 0);
    expect(harness.container.read(sessionControllerProvider).value, isA<SessionReady>());
  });

  testWidgets('확인 팝업에서 로그아웃을 누르면 SessionController.signOut()이 실행된다', (tester) async {
    // 잡아야 할 잘못된 구현: 확인 버튼이 팝업만 닫고 아무것도 하지 않는다,
    // 또는 `TokenStore`를 직접 지워 서버 로그아웃(`POST /auth/logout`)을
    // 건너뛴다 — 그러면 다른 기기의 refresh token이 살아남는다.
    final harness = await _pumpProfile(tester);

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(PopupActionButtons),
        matching: find.text('로그아웃'),
      ),
    );
    // `pumpAndSettle`을 쓸 수 없다 — 로그아웃이 반영되면 이 화면은
    // `SessionReady`가 아니게 되어 무한히 도는 `CircularProgressIndicator`를
    // 그린다(실제 앱에서는 라우터가 곧바로 /login으로 데려간다).
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(harness.auth.logoutCalls, 1);
    expect(harness.container.read(sessionControllerProvider).value, isA<SessionSignedOut>());
  });

  testWidgets('비밀번호 변경 카드를 누르면 비밀번호 변경 팝업이 뜬다', (tester) async {
    // 잡아야 할 잘못된 구현: 셰브론만 장식으로 두고 아무 데도 연결하지
    // 않는다 — Figma에 카드 말고는 비밀번호 변경으로 가는 길이 없다.
    await _pumpProfile(tester);

    await tester.tap(find.text('3개월에 한번씩 비밀번호 변경이 가능해요'));
    await tester.pumpAndSettle();

    expect(find.byType(PasswordChangePopupContent), findsOneWidget);
  });

  testWidgets('비밀번호 변경에 성공하면 팝업이 닫히고 마이페이지에 토스트가 뜬다', (tester) async {
    // 잡아야 할 잘못된 구현: 성공해도 팝업에 그대로 머무른다(사용자는
    // 바뀐 건지 알 수 없다), 또는 팝업만 닫고 아무 안내도 하지 않는다.
    // Figma `405:2244`는 정확히 이 순간의 마이페이지다 — `변경 알림`
    // (`405:2325`) 토스트가 마이페이지 **위에** 떠 있다.
    final harness = await _pumpProfile(tester);

    await tester.tap(find.text('3개월에 한번씩 비밀번호 변경이 가능해요'));
    await tester.pumpAndSettle();
    expect(find.byType(PasswordChangePopupContent), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byKey(passwordChangeCurrentFieldKey),
        matching: find.byType(TextField),
      ),
      'old-pass1',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(passwordChangeNewFieldKey),
        matching: find.byType(TextField),
      ),
      'new-pass1',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(passwordChangeConfirmFieldKey),
        matching: find.byType(TextField),
      ),
      'new-pass1',
    );
    await tester.tap(find.text('변경하기'));
    await tester.pumpAndSettle();

    expect(harness.repository.changeCalls, hasLength(1));
    expect(find.byType(PasswordChangePopupContent), findsNothing);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.text('비밀번호가 변경되었어요'), findsOneWidget);
    // 명세서상 서버는 **다른 기기의** refresh token만 무효화한다 — 이
    // 기기의 세션은 그대로여야 한다(로그아웃시키는 구현을 잡는다).
    expect(harness.container.read(sessionControllerProvider).value, isA<SessionReady>());
  });

  testWidgets('마이 탭이 숨겨지면 떠 있던 팝업도 함께 닫힌다', (tester) async {
    // 잡아야 할 잘못된 구현: 정리를 `dispose()`에만 둔다.
    // `StatefulShellRoute.indexedStack`은 숨은 브랜치를 dispose하지 않으므로
    // 탭을 옮겨도 dispose가 불리지 않고, 루트 내비게이터에 붙은 팝업이
    // 다음 탭 화면 위에 그대로 남아 앱을 막는다.
    final harness = await _pumpProfile(tester);

    await tester.tap(find.text('3개월에 한번씩 비밀번호 변경이 가능해요'));
    await tester.pumpAndSettle();
    expect(find.byType(PasswordChangePopupContent), findsOneWidget);

    harness.visible.value = false;
    await tester.pumpAndSettle();

    expect(find.byType(PasswordChangePopupContent), findsNothing);
  });

  testWidgets('팝업 위에 다른 루트 라우트가 있어도 자기 팝업만 닫는다', (tester) async {
    // 잡아야 할 잘못된 구현: `_rootNavigator.removeRoute(route)` 대신
    // `pop()`을 쓴다. pop은 "스택 맨 위"를 닫을 뿐 정체성을 모르므로,
    // 우리 팝업 위에 다른 루트 라우트가 얹혀 있으면 **엉뚱한 것을 닫고**
    // 우리 팝업은 다음 탭 위에 그대로 남는다. 파일 주석이 바로 이 이유로
    // 라우트 객체를 들고 있다고 적어 두었는데 아무 테스트도 없었다.
    final harness = await _pumpProfile(tester);

    await tester.tap(find.text('3개월에 한번씩 비밀번호 변경이 가능해요'));
    await tester.pumpAndSettle();
    expect(find.byType(PasswordChangePopupContent), findsOneWidget);

    // 팝업 위로 다른 루트 라우트를 하나 얹는다. 불투명 라우트를 쓰면
    // `Overlay`가 그 아래 전부를 `TickerMode(enabled: false)`로 만들어
    // 화면이 스스로 팝업을 닫아버리므로, 반드시 비불투명이어야 한다.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).last);
    unawaited(
      navigator.push<void>(
        DialogRoute<void>(
          context: navigator.context,
          barrierColor: null,
          builder: (context) => const Text('위에 얹힌 라우트'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('위에 얹힌 라우트'), findsOneWidget);

    harness.visible.value = false;
    await tester.pumpAndSettle();

    expect(find.byType(PasswordChangePopupContent), findsNothing, reason: '자기 팝업은 닫아야 한다');
    expect(
      find.text('위에 얹힌 라우트'),
      findsOneWidget,
      reason: '남의 라우트를 닫으면 안 된다 — pop()은 정체성을 모른다',
    );
  });

  testWidgets('숨겨진 마이 탭은 토글 실패 토스트를 띄우지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: 실패하면 `_visible`을 보지 않고 그냥 토스트를
    // 띄운다. `StatefulShellRoute.indexedStack`은 숨은 브랜치를 dispose하지
    // 않아 `mounted`가 계속 참이고, `AppShell`은 `navigationShell` 위에
    // `Scaffold`를 하나만 두므로 그 `SnackBar`는 **사용자가 지금 보고 있는
    // 다른 탭 위에** 뜬다(리뷰 Critical 2). 홈 화면은 같은 경로를 이미
    // 막아 두었다.
    final repository = _RecordingProfileRepository()..gateUpdate = true;
    final harness = await _pumpProfile(
      tester,
      repository: repository,
      pushEnabled: false,
    );

    await tester.tap(find.byType(AppSwitch));
    await tester.pump();
    expect(repository.updateCalls, hasLength(1));

    // 응답이 오기 전에 다른 탭으로 옮긴다.
    harness.visible.value = false;
    await tester.pumpAndSettle();

    repository.updateFailure = const ApiException(ErrorCode.network, '서버에 연결하지 못했습니다.');
    repository.releaseUpdate();
    await tester.pumpAndSettle();

    expect(
      find.text('서버에 연결하지 못했습니다.'),
      findsNothing,
      reason: '숨은 화면이 다른 탭 위로 토스트를 쏘면 안 된다',
    );
    // 되돌리기 자체는 전역 세션 상태라 숨은 동안에도 반영돼야 한다 —
    // 사용자가 마이 탭으로 돌아왔을 때 서버와 같은 값을 봐야 한다.
    final session = harness.container.read(sessionControllerProvider).value;
    expect((session as SessionReady).profile.pushEnabled, isFalse);
  });
}
