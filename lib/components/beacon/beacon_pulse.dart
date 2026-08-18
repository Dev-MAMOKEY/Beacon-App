import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// [BeaconPulse]가 그리는 두 상태. `Scanning`(아직 감지 전)과
/// `Detected`(안정화 통과) 두 [BeaconScanState]에만 대응한다 — 그 외
/// 상태(블루투스 꺼짐/권한 거부/범위 이탈)는 홈 화면이 안내 문구와 버튼으로
/// 따로 그린다.
enum BeaconPulseState { connected, disconnected }

/// 홈 화면 중앙의 동심원 시각화. Figma 실측(`339:1642`/`326:1587`, 파일
/// `O9RRQnJwoqsjU8LrJKeaAX`) 기준:
/// - 바깥 래퍼 256×256, 글로우(블러 35) 230, 안쪽 원 192.
/// - 감지됨: `#16CE69`(=[AppColors.green]) 100%/30%, 아이콘 `router-fill`,
///   라벨 `CONNETED`(디자인 표기 그대로 — 오타 아님).
/// - 미감지: 아이콘 `router-line`, 라벨 `NOT CONNETED`, 색은
///   `#94A8BD`(=[AppColors.disconnectedGlow]) — Figma에서 그대로 뽑아낸
///   값을 토큰으로 승격했다(1차 재작업에서는 토큰 밖이라 `gray1`로
///   임시 대체했었다).
/// - 아이콘-라벨 세로 배치, 간격 6, 라벨 스타일은 `body1`(18px Medium) —
///   `title6`이 아니다.
class BeaconPulse extends StatelessWidget {
  const BeaconPulse({super.key, required this.state});

  final BeaconPulseState state;

  static const double _wrapperSize = 256;
  static const double _outerSize = 230;
  static const double _innerSize = 192;
  static const double _outerBlurSigma = 35;
  static const double _iconSize = 36;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return switch (state) {
      BeaconPulseState.connected => _Pulse(
        glowColor: colors.green,
        innerColor: colors.green.withValues(alpha: 0.3),
        iconAsset: 'assets/icons/router-fill.svg',
        label: 'CONNETED',
        semanticLabel: '비콘 감지됨',
        typography: typography,
        colors: colors,
      ),
      BeaconPulseState.disconnected => _Pulse(
        glowColor: colors.disconnectedGlow,
        innerColor: colors.disconnectedGlow.withValues(alpha: 0.3),
        iconAsset: 'assets/icons/router-line.svg',
        label: 'NOT CONNETED',
        semanticLabel: '비콘을 찾는 중입니다',
        typography: typography,
        colors: colors,
      ),
    };
  }
}

class _Pulse extends StatelessWidget {
  const _Pulse({
    required this.glowColor,
    required this.innerColor,
    required this.iconAsset,
    required this.label,
    required this.semanticLabel,
    required this.typography,
    required this.colors,
  });

  final Color glowColor;
  final Color innerColor;
  final String iconAsset;
  final String label;
  final String semanticLabel;
  final AppTypography typography;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        width: BeaconPulse._wrapperSize,
        height: BeaconPulse._wrapperSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: BeaconPulse._outerBlurSigma,
                sigmaY: BeaconPulse._outerBlurSigma,
              ),
              child: Container(
                width: BeaconPulse._outerSize,
                height: BeaconPulse._outerSize,
                decoration: BoxDecoration(shape: BoxShape.circle, color: glowColor),
              ),
            ),
            Container(
              width: BeaconPulse._innerSize,
              height: BeaconPulse._innerSize,
              decoration: BoxDecoration(shape: BoxShape.circle, color: innerColor),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    iconAsset,
                    width: BeaconPulse._iconSize,
                    height: BeaconPulse._iconSize,
                    colorFilter: ColorFilter.mode(colors.white, BlendMode.srcIn),
                  ),
                  const SizedBox(height: 6),
                  Text(label, style: typography.body1.copyWith(color: colors.white)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
