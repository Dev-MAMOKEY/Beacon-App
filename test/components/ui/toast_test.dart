import 'package:beacon_app/components/ui/toast.dart';
import 'package:beacon_app/core/theme/app_colors.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Figma 실측 — 흰 배경 / gray2 글자 / 반경 20', (tester) async {
    // 잡아야 할 잘못된 구현: Phase 1의 gray3 배경 + 흰 글자 + 반경 12.
    // 정확히 **반대**로 구현돼 있었고 어떤 테스트도 고정하지 않았다(#48).
    // 실측 출처: `405:2325` "변경 알림".
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showAppToast(context, '비밀번호가 변경되었어요'),
              child: const Text('띄우기'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('띄우기'));
    await tester.pump();

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.backgroundColor, AppColors.light.white);
    expect(
      (snackBar.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(20),
    );

    final text = tester.widget<Text>(find.text('비밀번호가 변경되었어요'));
    expect(text.style!.color, AppColors.light.gray2);
    expect(text.style!.fontSize, 16, reason: 'body2(16)다 — body3(14)가 아니다');
  });

}
