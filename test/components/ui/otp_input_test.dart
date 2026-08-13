import 'package:beacon_app/components/ui/otp_input.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('length만큼 칸을 그린다', (tester) async {
    await tester.pumpWidget(_host(AppOtpInput(length: 4, onCompleted: (_) {})));
    await tester.pump();

    expect(find.byType(TextField), findsNWidgets(4));
  });

  testWidgets('마지막 자리를 채우면 onCompleted가 한 번 호출된다', (tester) async {
    final entered = <String>[];
    await tester.pumpWidget(
      _host(AppOtpInput(length: 4, onCompleted: entered.add)),
    );
    await tester.pump();

    const digits = ['7', '3', '2', '9'];
    final fields = find.byType(TextField);
    for (var i = 0; i < digits.length; i++) {
      await tester.enterText(fields.at(i), digits[i]);
      await tester.pump();
    }

    expect(entered, ['7329']);
  });

  testWidgets('reset하면 모든 칸이 비워진다', (tester) async {
    final controller = AppOtpController();
    await tester.pumpWidget(
      _host(AppOtpInput(length: 4, controller: controller, onCompleted: (_) {})),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, '1');
    await tester.pump();

    controller.reset();
    await tester.pump();

    final first = tester.widget<TextField>(find.byType(TextField).first);
    expect(first.controller!.text, isEmpty);
  });

  testWidgets('빈 칸에서 backspace를 누르면 이전 칸으로 이동해 그 칸을 지운다', (tester) async {
    await tester.pumpWidget(_host(AppOtpInput(length: 4, onCompleted: (_) {})));
    await tester.pump();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '5');
    await tester.pump();
    // '5' 입력 후 두 번째 칸(index 1)으로 자동 포커스된 상태.

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    final first = tester.widget<TextField>(fields.at(0));
    expect(first.controller!.text, isEmpty);
  });

  testWidgets('컨트롤러를 교체하면 이전 컨트롤러의 신호는 무시하고 새 컨트롤러를 따른다', (tester) async {
    final controllerA = AppOtpController();
    final controllerB = AppOtpController();

    await tester.pumpWidget(
      _host(AppOtpInput(length: 4, controller: controllerA, onCompleted: (_) {})),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, '1');
    await tester.pump();

    await tester.pumpWidget(
      _host(AppOtpInput(length: 4, controller: controllerB, onCompleted: (_) {})),
    );
    await tester.pump();

    // 옛 컨트롤러(A)의 리스너는 이미 떨어졌어야 한다 — 신호를 보내도 무시된다.
    controllerA.reset();
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, '1');

    // 새 컨트롤러(B)로 reset하면 실제로 반응한다.
    controllerB.reset();
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, isEmpty);
  });
}
