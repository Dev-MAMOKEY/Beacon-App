import 'package:beacon_app/components/ui/button.dart';
import 'package:beacon_app/core/theme/app_colors.dart';
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

  testWidgets('포커스된 상태에서 Enter/Space를 누르면 onPressed가 호출된다', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(AppButton(label: '확인', onPressed: () => taps++)));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(taps, 2);
  });

  // #13이 추가한 variant인데 테스트가 하나도 없었다 — `gray1`을 `main`으로
  // 바꿔도 스위트 전체가 초록이었다(리뷰 Important 6). 팝업의 취소 버튼이
  // 실행 버튼과 같은 색이 되면 사용자가 되돌릴 수 없는 쪽을 눌러 버린다.
  testWidgets('cancel은 gray1을 배경으로 쓰고 primary와 구별된다', (tester) async {
    await tester.pumpWidget(
      _host(AppButton(label: '취소', variant: ButtonVariant.cancel, onPressed: () {})),
    );
    await tester.pump();

    final colors = buildAppTheme().extension<AppColors>()!;
    expect(_backgroundOf(tester), colors.gray1);
    expect(
      _backgroundOf(tester),
      isNot(colors.main),
      reason: '취소가 실행 버튼과 같은 색이면 안 된다',
    );
  });

  testWidgets('trailing을 주면 라벨 뒤에 함께 그린다', (tester) async {
    await tester.pumpWidget(
      _host(
        AppButton(
          label: '로그아웃',
          trailing: const Icon(Icons.chevron_right, key: ValueKey('trailing')),
          onPressed: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('trailing')), findsOneWidget);
    expect(find.text('로그아웃'), findsOneWidget);
  });
}
