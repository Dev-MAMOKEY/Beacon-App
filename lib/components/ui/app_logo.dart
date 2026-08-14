import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Figma에서 내려받은 Beacon 워드마크(`assets/icons/beacon_logo.svg`, 원본
/// 비율 39.5336×30.5699 — 상단 바 스펙의 실제 값). 스플래시·로그인·상단
/// 바 세 곳이 각자 `Text('Beacon', ...)`으로 같은 문자열을 따로 스타일링해
/// 반복해 오던 것을 이 위젯 하나로 대체한다. 색은 SVG 자체에 `#54A2EA`
/// (=`AppColors.main`)로 이미 박혀 있으므로 여기서 다시 칠하지 않는다.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.height = _naturalHeight});

  static const double _naturalWidth = 39.5336;
  static const double _naturalHeight = 30.5699;

  final double height;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/icons/beacon_logo.svg',
      height: height,
      width: height * (_naturalWidth / _naturalHeight),
    );
  }
}
