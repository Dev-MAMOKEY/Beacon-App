import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

enum BadgeVariant { neutral, info, success, warning, danger }

class AppBadge extends StatelessWidget {
  const AppBadge({super.key, required this.label, this.variant = BadgeVariant.neutral});

  const AppBadge.info({super.key, required this.label}) : variant = BadgeVariant.info;

  const AppBadge.danger({super.key, required this.label}) : variant = BadgeVariant.danger;

  final String label;
  final BadgeVariant variant;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    // 성공(초록)은 Figma 변수에 없어 main 계열로 대체한다.
    // 홈 화면(#11)에서 초록을 추출하면 그때 success를 갱신한다.
    final palette = <BadgeVariant, ({Color background, Color foreground})>{
      BadgeVariant.neutral: (background: colors.gray4, foreground: colors.gray2),
      BadgeVariant.info: (background: colors.bg, foreground: colors.main),
      BadgeVariant.success: (background: colors.bg, foreground: colors.main),
      BadgeVariant.warning: (background: colors.yellow.withValues(alpha: 0.15), foreground: colors.yellow),
      BadgeVariant.danger: (background: colors.red.withValues(alpha: 0.15), foreground: colors.red),
    }[variant]!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: typography.title7.copyWith(color: palette.foreground),
      ),
    );
  }
}
