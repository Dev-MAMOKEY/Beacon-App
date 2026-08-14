import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// 진행률(0.0~1.0)을 채워진 막대로 보여주는 프리미티브. 홈 화면의 이번 달
/// 출석률 요약 카드가 먼저 쓰고, #12(기록 캘린더 하단 요약)가 재사용한다.
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    super.key,
    required this.value,
    this.height = 8,
    this.color,
    this.backgroundColor,
  });

  /// 0.0(0%)~1.0(100%) 범위. 범위를 벗어나면 clamp한다 — 서버가 100을
  /// 넘는 출석률(예: 반올림 오차)을 내려줘도 막대가 카드 밖으로 넘치지
  /// 않는다.
  final double value;

  final double height;
  final Color? color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final fraction = value.clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Container(
                  width: constraints.maxWidth,
                  height: height,
                  color: backgroundColor ?? colors.gray4,
                ),
                Container(
                  width: constraints.maxWidth * fraction,
                  height: height,
                  color: color ?? colors.main,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
