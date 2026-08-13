import 'package:beacon_app/components/ui/otp_input.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
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
}
