import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../ui/app_logo.dart';

/// 상단 바(`340:1923`). 좌: Beacon 로고, 중앙: 화면 제목/사용자 이름
/// (`18px gray3` — `AppTypography.body1`이 정확히 18px이라 그대로 쓴다),
/// 우: 알림 아이콘 24×24(`assets/icons/notification.svg`, Figma
/// `notification-2-line`).
///
/// `AppBar`를 쓰지 않는다 — 이 프로젝트는 Phase 1부터 UI 프리미티브를
/// 직접 소유하는 방식(shadcn류)을 유지해 왔고, 이 레이아웃은 Material의
/// AppBar 테마링과 맞지 않는 로고·이름·종 아이콘 3분할 구조라 커스텀
/// 위젯이 더 맞는다.
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
                const AppLogo(),
                Expanded(
                  child: Center(
                    child: title == null
                        ? null
                        : Text(
                            title!,
                            // 이 자리는 화면 제목뿐 아니라 사용자 이름도
                            // 들어온다(홈 화면) — maxLines/overflow 없이
                            // 두면 예외 없이 이 바의 높이(56)까지 조용히
                            // 늘어난다(RenderFlex는 Row의 교차축 오버플로를
                            // 경고하지 않는다 — 직접 확인했다). 한 줄로
                            // 자른다.
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: typography.body1.copyWith(color: colors.gray3),
                          ),
                  ),
                ),
                SvgPicture.asset(
                  'assets/icons/notification.svg',
                  width: 24,
                  height: 24,
                  // 자산에 박혀 있던 #787878(=gray2)은 걷어내고 중립
                  // 플레이스홀더로 바꿨다 — AppLogo와 같은 이유(주석 참고).
                  // 테마의 gray2가 정본이다.
                  colorFilter: ColorFilter.mode(colors.gray2, BlendMode.srcIn),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
