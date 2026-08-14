import 'package:beacon_app/components/nav/app_bottom_nav.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('showAdmin: false면 관리자 탭이 렌더되지 않는다', (tester) async {
    await tester.pumpWidget(
      _host(AppBottomNav(currentIndex: 0, showAdmin: false, onTap: (_) {})),
    );

    expect(find.text('홈'), findsOneWidget);
    expect(find.text('기록'), findsOneWidget);
    expect(find.text('관리자'), findsNothing);
    expect(find.text('마이'), findsOneWidget);
  });

  testWidgets('showAdmin: true면 관리자 탭까지 4개 모두 렌더된다', (tester) async {
    await tester.pumpWidget(
      _host(AppBottomNav(currentIndex: 0, showAdmin: true, onTap: (_) {})),
    );

    expect(find.text('홈'), findsOneWidget);
    expect(find.text('기록'), findsOneWidget);
    expect(find.text('관리자'), findsOneWidget);
    expect(find.text('마이'), findsOneWidget);
  });

  testWidgets('탭을 누르면 그 탭의 브랜치 인덱스로 onTap이 호출된다', (tester) async {
    var tapped = -1;
    await tester.pumpWidget(
      _host(AppBottomNav(currentIndex: 0, showAdmin: true, onTap: (index) => tapped = index)),
    );

    await tester.tap(find.text('마이'));
    await tester.pump();

    expect(tapped, 3);
  });
}
