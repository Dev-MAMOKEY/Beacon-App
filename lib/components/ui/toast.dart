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
        // Figma 실측(`405:2325` "변경 알림"): 흰 배경 / gray2 글자 /
        // body2(16) / 반경 20 / 좌우 40·상하 16 패딩. Phase 1은 정반대로
        // (gray3 배경 / 흰 글자 / body3 / 반경 12) 구현돼 있었다(#48).
        content: Text(
          message,
          style: typography.body2.copyWith(color: colors.gray2),
        ),
        backgroundColor: colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        duration: const Duration(seconds: 2),
      ),
    );
}
