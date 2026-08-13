import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  final String serviceName = '마모키';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Scaffold(
      backgroundColor: colors.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Beacon',
              style: typography.title3.copyWith(color: colors.main),
            ),
            const SizedBox(height: 12),
            Text(
              serviceName,
              style: typography.body2.copyWith(color: colors.gray2),
            ),
          ],
        ),
      ),
    );
  }
}
