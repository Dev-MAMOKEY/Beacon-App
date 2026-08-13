import 'package:beacon_app/core/theme/app_colors.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:beacon_app/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('테마에서 AppColors와 AppTypography를 꺼낼 수 있다', () {
    final theme = buildAppTheme();

    final colors = theme.extension<AppColors>();
    expect(colors, isNotNull);
    expect(colors!.main, const Color(0xFF54A2EA));
    expect(colors.bg, const Color(0xFFEEF7FF));
    expect(colors.red, const Color(0xFFFF5D5D));

    final typography = theme.extension<AppTypography>();
    expect(typography, isNotNull);
    expect(typography!.title4.fontFamily, 'Pretendard');
    expect(typography.title4.fontSize, 20);
    expect(typography.title4.fontWeight, FontWeight.w600);
    expect(typography.number1.fontFamily, 'Manrope');

    expect(theme.colorScheme.primary, AppColors.light.main);
    expect(theme.colorScheme.error, AppColors.light.red);
  });

  test('lerp는 t=0에서 원본을 유지한다', () {
    const a = AppColors.light;
    final b = a.copyWith(main: const Color(0xFF000000));
    final mid = a.lerp(b, 0);
    expect(mid.main, a.main);
  });

  test('AppColors.copyWith()는 인자가 없으면 모든 필드를 그대로 유지한다', () {
    const original = AppColors.light;
    final copy = original.copyWith();

    expect(copy.main, original.main);
    expect(copy.bg, original.bg);
    expect(copy.white, original.white);
    expect(copy.gray1, original.gray1);
    expect(copy.gray2, original.gray2);
    expect(copy.gray3, original.gray3);
    expect(copy.gray4, original.gray4);
    expect(copy.yellow, original.yellow);
    expect(copy.red, original.red);
    expect(copy.label, original.label);
  });

  test('AppTypography.copyWith()는 인자가 없으면 모든 스타일을 그대로 유지한다', () {
    const original = AppTypography.standard;
    final copy = original.copyWith();

    expect(copy.title3, original.title3);
    expect(copy.title4, original.title4);
    expect(copy.title6, original.title6);
    expect(copy.title7, original.title7);
    expect(copy.body1, original.body1);
    expect(copy.body2, original.body2);
    expect(copy.body3, original.body3);
    expect(copy.number1, original.number1);
  });
}
