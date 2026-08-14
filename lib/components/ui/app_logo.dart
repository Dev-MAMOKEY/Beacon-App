import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/app_colors.dart';

/// Figma에서 내려받은 Beacon 워드마크(`assets/icons/beacon_logo.svg`, 원본
/// 비율 39.5336×30.5699 — 상단 바 스펙의 실제 값). 스플래시·로그인·상단
/// 바 세 곳이 각자 `Text('Beacon', ...)`으로 같은 문자열을 따로 스타일링해
/// 반복해 오던 것을 이 위젯 하나로 대체한다.
///
/// SVG 파일 자체에는 `#54A2EA`(=`AppColors.main`)가 박혀 있지만, 그 값을
/// 그대로 믿고 칠하지 않는다 — 그러면 테마의 `main` 토큰을 바꿔도 이
/// 자산은 색이 안 바뀌는, `lib/core/theme/` 밖 하드코딩 `Color(0x…)`와
/// 같은 부류의 결함이 grep 게이트만 피해 숨어버린다. 항상
/// `Theme.of(context)`에서 읽은 `AppColors.main`으로 `colorFilter`를
/// 입혀, 자산의 원래 색과 우연히 같아 보여도 실제로는 테마가 정본이 되게
/// 한다.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.height = _naturalHeight});

  static const double _naturalWidth = 39.5336;
  static const double _naturalHeight = 30.5699;

  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    return SvgPicture.asset(
      'assets/icons/beacon_logo.svg',
      height: height,
      width: height * (_naturalWidth / _naturalHeight),
      colorFilter: ColorFilter.mode(colors.main, BlendMode.srcIn),
    );
  }
}
