import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.background,
    this.borderColor,
  });

  static const double radius = 16;

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? background;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: borderColor == null ? null : Border.all(color: borderColor!, width: 2),
      ),
      child: child,
    );
  }
}

class AppCardHeader extends StatelessWidget {
  const AppCardHeader({super.key, required this.title, this.trailing, this.subtitle});

  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final typography = Theme.of(context).extension<AppTypography>()!;
    final colors = Theme.of(context).extension<AppColors>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DefaultTextStyle.merge(
                style: typography.title4.copyWith(color: colors.gray3),
                child: title,
              ),
            ),
            ?trailing,
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          DefaultTextStyle.merge(
            style: typography.body3.copyWith(color: colors.gray2),
            child: subtitle!,
          ),
        ],
      ],
    );
  }
}

class AppCardContent extends StatelessWidget {
  const AppCardContent({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.only(top: 16), child: child);
  }
}

class AppCardFooter extends StatelessWidget {
  const AppCardFooter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.only(top: 16), child: child);
  }
}
