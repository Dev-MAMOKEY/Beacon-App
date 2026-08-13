import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// 다크 모드는 디자인에 없으므로 만들지 않는다.
ThemeData buildAppTheme() {
  const colors = AppColors.light;
  const typography = AppTypography.standard;

  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Pretendard',
    scaffoldBackgroundColor: colors.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: colors.main,
      primary: colors.main,
      onPrimary: colors.white,
      error: colors.red,
      onError: colors.white,
      surface: colors.white,
      onSurface: colors.gray3,
    ),
    extensions: const <ThemeExtension<dynamic>>[colors, typography],
  );
}
