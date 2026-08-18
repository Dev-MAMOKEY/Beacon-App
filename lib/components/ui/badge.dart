import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

enum BadgeVariant { neutral, info, success, warning, danger }

@immutable
class AppBadgeStyle {
  const AppBadgeStyle({required this.background, required this.foreground});

  final Color background;
  final Color foreground;
}

class AppBadge extends StatelessWidget {
  const AppBadge({super.key, required this.label, this.variant = BadgeVariant.neutral});

  const AppBadge.info({super.key, required this.label}) : variant = BadgeVariant.info;

  const AppBadge.danger({super.key, required this.label}) : variant = BadgeVariant.danger;

  final String label;
  final BadgeVariant variant;

  @override
  Widget build(BuildContext context) {
    final typography = Theme.of(context).extension<AppTypography>()!;
    final style = resolveBadgeStyle(context, variant);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: typography.title7.copyWith(color: style.foreground),
      ),
    );
  }
}

/// variant를 스타일로 해석한다. exhaustive switch라 새 variant를 추가하면
/// 이 함수가 컴파일 타임에 누락을 알려준다 — `build`는 건드리지 않는다.
AppBadgeStyle resolveBadgeStyle(BuildContext context, BadgeVariant variant) {
  final colors = Theme.of(context).extension<AppColors>()!;

  // 경고/위험/성공 배경의 alpha 0.15는 Figma에 배지 배경 토큰이 없어 임시로
  // 정한 값이다 — 출결상태 컴포넌트가 나오는 이슈에서 실제 값으로 교체한다.
  final ({Color background, Color foreground}) palette = switch (variant) {
    BadgeVariant.neutral => (background: colors.gray4, foreground: colors.gray2),
    BadgeVariant.info => (background: colors.bg, foreground: colors.main),
    BadgeVariant.success => (
      background: colors.green.withValues(alpha: 0.15),
      foreground: colors.green,
    ),
    BadgeVariant.warning => (
      background: colors.yellow.withValues(alpha: 0.15),
      foreground: colors.yellow,
    ),
    BadgeVariant.danger => (
      background: colors.red.withValues(alpha: 0.15),
      foreground: colors.red,
    ),
  };

  return AppBadgeStyle(background: palette.background, foreground: palette.foreground);
}
