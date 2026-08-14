import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// 상단 바(`340:1923`). 좌: Beacon 로고, 중앙: 화면 제목/사용자 이름
/// (`18px gray3` — `AppTypography.body1`이 정확히 18px이라 그대로 쓴다),
/// 우: 알림 아이콘 24×24.
///
/// Figma가 내보낸 실제 로고·아이콘 SVG를 이 태스크에서 구하지 못했다 —
/// 접근 가능한 Figma 파일 URL/키를 찾지 못했고, 손으로 벡터를 그리거나
/// 비슷한 아이콘으로 대체하지 않기로 했다(지침). 로고 자리는 스플래시
/// 화면과 동일하게 "Beacon" 텍스트 워드마크로, 알림 아이콘 자리는 24×24
/// 빈 자리로 채워 레이아웃만 맞춰 두고, 실제 에셋이 확보되면 교체한다.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({super.key, this.title});

  /// 화면 제목 또는 사용자 이름. null이면 중앙이 비어 있다.
  final String? title;

  static const double _height = 56;

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return ColoredBox(
      color: colors.white,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: _height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Text('Beacon', style: typography.title6.copyWith(color: colors.main)),
                Expanded(
                  child: Center(
                    child: title == null
                        ? null
                        : Text(
                            title!,
                            style: typography.body1.copyWith(color: colors.gray3),
                          ),
                  ),
                ),
                const SizedBox(width: 24, height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
