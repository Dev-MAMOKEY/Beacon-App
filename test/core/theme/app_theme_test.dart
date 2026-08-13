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
  });

  test('lerp는 t=0에서 원본을 유지한다', () {
    const a = AppColors.light;
    final b = a.copyWith(main: const Color(0xFF000000));
    final mid = a.lerp(b, 0);
    expect(mid.main, a.main);
  });
}
