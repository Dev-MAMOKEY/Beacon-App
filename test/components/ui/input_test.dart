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

  // #13이 추가한 `prefix`인데 테스트가 하나도 없었다 — `prefixIcon`을 통째로
  // null로 만들어도 스위트 전체가 초록이었다(리뷰 Important 6).
  group('prefix', () {
    testWidgets('prefix를 주면 앞 아이콘으로 그린다', (tester) async {
      await tester.pumpWidget(
        _host(
          AppInput(
            controller: TextEditingController(),
            hint: '비밀번호 입력',
            prefix: const Icon(Icons.lock_outline, key: ValueKey('prefix')),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('prefix')), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).decoration!.prefixIcon, isNotNull);
    });

    // `contentPadding`의 left는 prefix 유무로 갈린다(prefix가 있으면 그
    // Padding이 이미 왼쪽 여백을 만든다). 이 분기는 Phase 1의 **모든** 입력
    // 칸에 영향을 주는데 어느 층에도 테스트가 없었다 — 스위트 통과는
    // "트리가 여전히 빌드된다"는 뜻이지 로그인·회원가입이 그대로 보인다는
    // 뜻이 아니다.
    testWidgets('prefix가 없으면 왼쪽 여백을 직접 주고, 있으면 주지 않는다', (tester) async {
      await tester.pumpWidget(_host(AppInput(controller: TextEditingController(), hint: '학번 입력')));
      await tester.pump();
      final without =
          tester.widget<TextField>(find.byType(TextField)).decoration!.contentPadding!
              as EdgeInsets;
      expect(without.left, 16);
      expect(without.right, 16);

      await tester.pumpWidget(
        _host(
          AppInput(
            controller: TextEditingController(),
            hint: '학번 입력',
            prefix: const Icon(Icons.person_outline),
          ),
        ),
      );
      await tester.pump();
      final with_ =
          tester.widget<TextField>(find.byType(TextField)).decoration!.contentPadding!
              as EdgeInsets;
      expect(with_.left, 0, reason: 'prefix의 Padding이 이미 만든 여백을 두 번 주면 안 된다');
      expect(with_.right, 16);
    });
  });
}
