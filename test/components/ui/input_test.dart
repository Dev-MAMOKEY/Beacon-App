import 'package:beacon_app/components/ui/input.dart';
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

Color _enabledBorderColorOf(WidgetTester tester) {
  final field = tester.widget<TextField>(find.byType(TextField));
  final border = field.decoration!.enabledBorder! as OutlineInputBorder;
  return border.borderSide.color;
}

void main() {
  group('AppInput', () {
    testWidgets('errorText가 있으면 테두리가 red이고 에러 메시지가 보인다', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        _host(
          AppInput(
            controller: controller,
            label: '이메일',
            errorText: '이메일 형식이 올바르지 않습니다',
          ),
        ),
      );
      await tester.pump();

      expect(_enabledBorderColorOf(tester), AppColors.light.red);
      expect(find.text('이메일 형식이 올바르지 않습니다'), findsOneWidget);
    });

    testWidgets('errorText가 없으면 테두리가 gray4이고 에러 메시지가 없다', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        _host(AppInput(controller: controller, label: '이메일')),
      );
      await tester.pump();

      expect(_enabledBorderColorOf(tester), AppColors.light.gray4);
      expect(find.textContaining('올바르지 않습니다'), findsNothing);
    });
  });

  group('AppPasswordInput', () {
    testWidgets('기본은 숨김 상태이고 아이콘을 탭하면 표시 상태로 바뀐다', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        _host(AppPasswordInput(controller: controller, label: '비밀번호')),
      );
      await tester.pump();

      expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsNothing);

      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pump();

      expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isFalse);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);
    });
  });
}
