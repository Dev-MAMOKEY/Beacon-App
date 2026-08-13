import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// 명세서의 "토스트 메시지로 안내합니다" 를 한 곳에서 처리한다.
void showAppToast(BuildContext context, String message) {
  final colors = Theme.of(context).extension<AppColors>()!;
  final typography = Theme.of(context).extension<AppTypography>()!;

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: typography.body3.copyWith(color: colors.white),
        ),
        backgroundColor: colors.gray3,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
}
