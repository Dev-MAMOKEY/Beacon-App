import 'package:beacon_app/components/ui/app_switch.dart';
import 'package:beacon_app/core/theme/app_colors.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(body: Center(child: child)),
  );
}

Color _trackColorOf(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find.descendant(of: find.byType(AppSwitch), matching: find.byType(AnimatedContainer)),
  );
  return (container.decoration! as BoxDecoration).color!;
}

void main() {
  // 색만 보면 손잡이가 반대편에 박혀 있는 구현이 통과하고, 정렬만 보면
  // 색이 뒤바뀐 구현이 통과한다 — 둘 다 본다. 정렬은 위젯 속성이 아니라
  // 실제로 그려진 사각형의 좌표로 잰다(정렬을 다른 방식으로 구현해도
  // 유효하고, "target은 맞는데 화면엔 반영 안 됨"까지 잡는다).
  testWidgets('켜짐은 트랙이 main이고 손잡이가 오른쪽 끝에 붙는다', (tester) async {
    // 잡아야 할 잘못된 구현: on/off의 색이나 정렬을 뒤바꿔 배선한다
    // (Figma `353:1938`=on은 main+오른쪽, `353:1940`=off는 gray2+왼쪽).
    await tester.pumpWidget(
      _host(AppSwitch(value: true, semanticLabel: '알림 허용', onChanged: (_) {})),
    );
    await tester.pumpAndSettle();

    expect(_trackColorOf(tester), AppColors.light.main);

    final track = tester.getRect(find.byType(AppSwitch));
    final thumb = tester.getRect(find.byKey(AppSwitch.thumbKey));
    // Figma 실측 — 트랙 58×28, 안쪽 여백 2, 손잡이 24.
    expect(track.size, const Size(58, 28));
    expect(thumb.size, const Size(24, 24));
    expect(track.right - thumb.right, moreOrLessEquals(2, epsilon: 0.01));
    expect(thumb.left - track.left, moreOrLessEquals(32, epsilon: 0.01));
  });

  testWidgets('꺼짐은 트랙이 gray2이고 손잡이가 왼쪽 끝에 붙는다', (tester) async {
    // 잡아야 할 잘못된 구현: 꺼짐 색으로 gray1이나 gray4를 쓴다(Figma는
    // gray2다), 또는 손잡이를 항상 오른쪽에 둔다.
    await tester.pumpWidget(
      _host(AppSwitch(value: false, semanticLabel: '알림 허용', onChanged: (_) {})),
    );
    await tester.pumpAndSettle();

    expect(_trackColorOf(tester), AppColors.light.gray2);

    final track = tester.getRect(find.byType(AppSwitch));
    final thumb = tester.getRect(find.byKey(AppSwitch.thumbKey));
    expect(thumb.left - track.left, moreOrLessEquals(2, epsilon: 0.01));
    expect(track.right - thumb.right, moreOrLessEquals(32, epsilon: 0.01));
  });

  testWidgets('탭하면 지금 값의 반대가 onChanged로 올라온다', (tester) async {
    // 잡아야 할 잘못된 구현: 항상 true를 넘긴다(=끌 수 없다), 또는 지금
    // 값을 그대로 넘긴다(=아무 일도 일어나지 않는다).
    final received = <bool>[];

    await tester.pumpWidget(
      _host(AppSwitch(value: false, semanticLabel: '알림 허용', onChanged: received.add)),
    );
    await tester.tap(find.byType(AppSwitch));
    expect(received, [true]);

    await tester.pumpWidget(
      _host(AppSwitch(value: true, semanticLabel: '알림 허용', onChanged: received.add)),
    );
    await tester.tap(find.byType(AppSwitch));
    expect(received, [true, false]);
  });

  testWidgets('스크린리더에 이름과 켜짐/꺼짐 상태가 함께 노출된다', (tester) async {
    // 잡아야 할 잘못된 구현: Semantics를 아예 달지 않는다 — 글자가 없는
    // 스위치라 스크린리더에는 아무것도 읽히지 않는다.
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      _host(AppSwitch(value: true, semanticLabel: '알림 허용', onChanged: (_) {})),
    );

    expect(
      tester.getSemantics(find.byType(AppSwitch)),
      matchesSemantics(
        label: '알림 허용',
        hasToggledState: true,
        isToggled: true,
        hasTapAction: true,
      ),
    );

    // `addTearDown`은 프레임워크의 핸들 검사보다 늦게 돌아 "핸들이 살아
    // 있다"로 실패한다 — 명시적으로 닫는다.
    handle.dispose();
  });
}
