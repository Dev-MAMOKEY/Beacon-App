import 'package:beacon_app/components/ui/button.dart';
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

Color _backgroundOf(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find.byKey(const ValueKey('app_button_surface')),
  );
  return ((container.decoration! as BoxDecoration).color)!;
}

void main() {
  testWidgets('primary는 main 색을 배경으로 쓴다', (tester) async {
    await tester.pumpWidget(_host(AppButton(label: '확인', onPressed: () {})));
    await tester.pump();

    expect(_backgroundOf(tester), AppColors.light.main);
  });

  testWidgets('destructive는 red 색을 배경으로 쓴다', (tester) async {
    await tester.pumpWidget(
      _host(AppButton.destructive(label: '출석 종료하기', onPressed: () {})),
    );
    await tester.pump();

    expect(_backgroundOf(tester), AppColors.light.red);
  });

  testWidgets('onPressed가 null이면 비활성 색을 쓰고 탭해도 콜백이 없다', (tester) async {
    await tester.pumpWidget(_host(const AppButton(label: '확인')));
    await tester.pump();

    expect(_backgroundOf(tester), AppColors.light.gray4);
  });

  testWidgets('탭하면 onPressed가 호출된다', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(AppButton(label: '확인', onPressed: () => taps++)));
    await tester.tap(find.text('확인'));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('isLoading이면 라벨 대신 인디케이터를 보여주고 탭이 막힌다', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(AppButton(label: '확인', isLoading: true, onPressed: () => taps++)),
    );
    await tester.pump();

    expect(find.text('확인'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.byType(AppButton));
    await tester.pump();
    expect(taps, 0);
  });
}
