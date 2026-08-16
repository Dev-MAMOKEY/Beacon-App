import 'package:beacon_app/core/network/api_exception.dart';
import 'package:beacon_app/core/network/error_code.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:beacon_app/features/auth/presentation/auth_form_validator.dart';
import 'package:beacon_app/features/profile/data/profile_repository.dart';
import 'package:beacon_app/features/profile/presentation/password_change_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingProfileRepository implements ProfileRepository {
  _RecordingProfileRepository({this.failure});

  final ApiException? failure;

  final List<({String current, String next, String confirm})> calls = [];

  @override
  Future<void> updateProfile({
    required String name,
    String? title,
    bool? pushEnabled,
  }) async => throw UnimplementedError('이 스위트는 프로필 수정을 하지 않는다');

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmNewPassword,
  }) async {
    calls.add((
      current: currentPassword,
      next: newPassword,
      confirm: confirmNewPassword,
    ));
    final error = failure;
    if (error != null) throw error;
  }
}

typedef _Harness = ({
  _RecordingProfileRepository repository,
  List<String> events,
});

/// 팝업 콘텐츠만 단독으로 띄운다. 실제 앱에서는 `ProfileScreen`이 이것을
/// 다이얼로그 라우트에 담아 루트 내비게이터에 push하지만(그 배선은
/// `profile_screen_test.dart`가 따로 고정한다), 폼의 동작을 보는 데는
/// 라우트가 필요 없다.
Future<_Harness> _pumpPopup(
  WidgetTester tester, {
  _RecordingProfileRepository? repository,
}) async {
  final repo = repository ?? _RecordingProfileRepository();
  final events = <String>[];

  await tester.pumpWidget(
    ProviderScope(
      overrides: [profileRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: Material(
              child: PasswordChangePopupContent(
                onCancel: () => events.add('cancel'),
                onChanged: () => events.add('changed'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return (repository: repo, events: events);
}

Finder _fieldOf(Key key) => find.byKey(key);

Future<void> _fill(
  WidgetTester tester, {
  required String current,
  required String next,
  required String confirm,
}) async {
  await tester.enterText(
    find.descendant(of: _fieldOf(passwordChangeCurrentFieldKey), matching: find.byType(TextField)),
    current,
  );
  await tester.enterText(
    find.descendant(of: _fieldOf(passwordChangeNewFieldKey), matching: find.byType(TextField)),
    next,
  );
  await tester.enterText(
    find.descendant(of: _fieldOf(passwordChangeConfirmFieldKey), matching: find.byType(TextField)),
    confirm,
  );
  await tester.pump();
}

void main() {
  testWidgets('새 비밀번호 검증은 Phase 1 validator와 같은 경계에서 갈린다 (8자, 양방향)', (tester) async {
    // 잡아야 할 잘못된 구현: 자체 검증 로직을 새로 쓴다 — 경계가
    // `> 8`이 되거나(8자를 거절), 길이만 보고 영문+숫자 규칙을 빼먹는다.
    //
    // 이 테스트가 "8자 이상이면 통과"만 봤다면 `length >= 1`짜리 구현도
    // 통과한다. 경계 **양쪽**을 다 보고, 문구까지 Phase 1의 것과 같은지
    // 확인한다 — 문구가 다르면 규칙을 옮겨 적은 것이지 재사용한 게 아니다.
    const short = 'abc123z'; // 7자, 영문+숫자
    const exact = 'abc1234z'; // 8자, 영문+숫자
    expect(short, hasLength(7));
    expect(exact, hasLength(8));

    final harness = await _pumpPopup(tester);

    await _fill(tester, current: 'old-pass1', next: short, confirm: short);
    await tester.tap(find.text('변경하기'));
    await tester.pumpAndSettle();

    expect(harness.repository.calls, isEmpty, reason: '7자는 서버까지 가지 않는다');
    expect(
      find.descendant(
        of: _fieldOf(passwordChangeNewFieldKey),
        matching: find.text(AuthFormValidator.password(short)!),
      ),
      findsOneWidget,
      reason: 'Phase 1 validator가 내놓는 바로 그 문구여야 한다',
    );

    // 경계의 반대쪽 — 딱 8자는 통과해야 한다.
    await _fill(tester, current: 'old-pass1', next: exact, confirm: exact);
    await tester.tap(find.text('변경하기'));
    await tester.pumpAndSettle();

    expect(harness.repository.calls, hasLength(1));
    expect(harness.repository.calls.single.next, exact);
  });

  testWidgets('영문/숫자 규칙도 Phase 1 validator를 그대로 따른다', (tester) async {
    // 잡아야 할 잘못된 구현: 길이만 검사한다 — 8자짜리 숫자열이 통과한다.
    const digitsOnly = '12345678';
    final harness = await _pumpPopup(tester);

    await _fill(tester, current: 'old-pass1', next: digitsOnly, confirm: digitsOnly);
    await tester.tap(find.text('변경하기'));
    await tester.pumpAndSettle();

    expect(harness.repository.calls, isEmpty);
    expect(
      find.descendant(
        of: _fieldOf(passwordChangeNewFieldKey),
        matching: find.text(AuthFormValidator.password(digitsOnly)!),
      ),
      findsOneWidget,
    );
  });

  testWidgets('확인값이 다르면 확인 칸 아래에 Phase 1 문구가 붙고 서버로 가지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: 일치 검사를 아예 안 하고 서버에 떠넘긴다,
    // 또는 `passwordConfirm` 대신 `==` 하나로 대체해 빈 확인값을 통과시킨다.
    final harness = await _pumpPopup(tester);

    await _fill(tester, current: 'old-pass1', next: 'new-pass1', confirm: 'new-pass2');
    await tester.tap(find.text('변경하기'));
    await tester.pumpAndSettle();

    expect(harness.repository.calls, isEmpty);
    expect(
      find.descendant(
        of: _fieldOf(passwordChangeConfirmFieldKey),
        matching: find.text(AuthFormValidator.passwordConfirm('new-pass1', 'new-pass2')!),
      ),
      findsOneWidget,
    );
  });

  testWidgets('현재 비밀번호가 비어 있으면 그 칸 아래에 안내가 붙는다', (tester) async {
    // 잡아야 할 잘못된 구현: 현재 비밀번호에 `AuthFormValidator.password`를
    // 그대로 적용한다 — 규칙이 생기기 전에 만든 계정(6자짜리 등)의 주인이
    // 정작 비밀번호를 바꿀 수 없게 된다. 비었는지만 본다.
    final harness = await _pumpPopup(tester);

    await _fill(tester, current: '', next: 'new-pass1', confirm: 'new-pass1');
    await tester.tap(find.text('변경하기'));
    await tester.pumpAndSettle();

    expect(harness.repository.calls, isEmpty);
    expect(
      find.descendant(
        of: _fieldOf(passwordChangeCurrentFieldKey),
        matching: find.text('현재 비밀번호를 입력해주세요'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('규칙을 만족하지 않는 현재 비밀번호도 서버까지 그대로 간다', (tester) async {
    // 잡아야 할 잘못된 구현: 현재 비밀번호에도 8자·영문+숫자 규칙을
    // 적용한다. 판정은 서버만 할 수 있다.
    final harness = await _pumpPopup(tester);

    await _fill(tester, current: 'old', next: 'new-pass1', confirm: 'new-pass1');
    await tester.tap(find.text('변경하기'));
    await tester.pumpAndSettle();

    expect(harness.repository.calls, hasLength(1));
    expect(harness.repository.calls.single.current, 'old');
  });

  testWidgets('현재 비밀번호 불일치는 그 칸 아래 인라인으로만 표시된다', (tester) async {
    // 잡아야 할 잘못된 구현 세 가지 — 전부 "메시지가 어딘가 보인다"는
    // 검사는 통과한다:
    //   1) 토스트로 띄운다,
    //   2) 폼 전체 아래에 화면 단위 메시지로 띄운다,
    //   3) 엉뚱하게 새 비밀번호 칸 아래에 붙인다.
    // 그래서 "그 칸의 자손인가"와 "다른 자리에는 없는가"를 함께 본다.
    final repository = _RecordingProfileRepository(
      failure: const ApiException(
        ErrorCode.invalidCredentials,
        '학번 또는 비밀번호가 올바르지 않습니다',
        statusCode: 400,
      ),
    );
    final harness = await _pumpPopup(tester, repository: repository);

    await _fill(tester, current: 'wrong-pass1', next: 'new-pass1', confirm: 'new-pass1');
    await tester.tap(find.text('변경하기'));
    await tester.pumpAndSettle();

    const message = '현재 비밀번호가 올바르지 않습니다';
    expect(
      find.descendant(of: _fieldOf(passwordChangeCurrentFieldKey), matching: find.text(message)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _fieldOf(passwordChangeNewFieldKey), matching: find.text(message)),
      findsNothing,
    );
    expect(find.byType(SnackBar), findsNothing, reason: '토스트가 아니다');
    // 메시지는 정확히 하나 — 인라인과 화면 단위 메시지를 둘 다 띄우지 않는다.
    expect(find.text(message), findsOneWidget);
    // 서버 문구를 그대로 옮기지 않는다 — `INVALID_CREDENTIALS`는 로그인이
    // 쓰는 코드이기도 해서 학번을 언급한다.
    expect(find.text('학번 또는 비밀번호가 올바르지 않습니다'), findsNothing);
    // 팝업은 열린 채로 남아 있어야 한다(고칠 기회를 준다).
    expect(harness.events, isEmpty);
  });

  testWidgets('현재 비밀번호 불일치가 아닌 서버 오류는 팝업 안 폼 메시지로 보인다', (tester) async {
    // 잡아야 할 잘못된 구현: 모든 오류를 현재 비밀번호 칸에 붙인다 —
    // 네트워크가 끊겼는데 "현재 비밀번호가 올바르지 않습니다"라고 말한다.
    final repository = _RecordingProfileRepository(
      failure: const ApiException(ErrorCode.network, '서버에 연결하지 못했습니다.'),
    );
    await _pumpPopup(tester, repository: repository);

    await _fill(tester, current: 'old-pass1', next: 'new-pass1', confirm: 'new-pass1');
    await tester.tap(find.text('변경하기'));
    await tester.pumpAndSettle();

    expect(find.text('서버에 연결하지 못했습니다.'), findsOneWidget);
    expect(
      find.descendant(
        of: _fieldOf(passwordChangeCurrentFieldKey),
        matching: find.text('현재 비밀번호가 올바르지 않습니다'),
      ),
      findsNothing,
    );
  });

  testWidgets('성공하면 onChanged로 알리고, 취소는 onCancel로 알린다', (tester) async {
    // 잡아야 할 잘못된 구현: 팝업이 스스로 `Navigator.pop()`을 부른다 —
    // 그건 "스택 맨 위"를 닫을 뿐 정체성을 모른다. 닫기는 라우트를 소유한
    // `ProfileScreen`의 몫이다.
    final harness = await _pumpPopup(tester);

    await tester.tap(find.text('취소'));
    await tester.pump();
    expect(harness.events, ['cancel']);

    await _fill(tester, current: 'old-pass1', next: 'new-pass1', confirm: 'new-pass1');
    await tester.tap(find.text('변경하기'));
    await tester.pumpAndSettle();

    expect(harness.events, ['cancel', 'changed']);
  });
}
