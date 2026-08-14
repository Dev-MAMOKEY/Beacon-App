import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// [BeaconPulse]가 그리는 두 상태. `Scanning`(아직 감지 전)과
/// `Detected`(안정화 통과) 두 [BeaconScanState]에만 대응한다 — 그 외
/// 상태(블루투스 꺼짐/권한 거부/범위 이탈)는 홈 화면이 안내 문구와 버튼으로
/// 따로 그린다.
enum BeaconPulseState { connected, disconnected }

/// 홈 화면 중앙의 동심원 시각화. 디자인 값(고정): 감지됨은 `#16CE69` —
/// 바깥 글로우(35 블러, 230 크기)와 안쪽 원(30% 불투명도, 192 크기)의
/// 조합이고 라벨은 디자인 표기 그대로 `CONNETED`. 미감지는 `gray1` 단색
/// 원과 `NOT CONNETED` 라벨이다.
class BeaconPulse extends StatelessWidget {
  const BeaconPulse({super.key, required this.state});

  final BeaconPulseState state;

  static const double _outerSize = 230;
  static const double _innerSize = 192;
  static const double _outerBlurSigma = 35;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return switch (state) {
      BeaconPulseState.connected => _ConnectedPulse(colors: colors, typography: typography),
      BeaconPulseState.disconnected => _DisconnectedPulse(colors: colors, typography: typography),
    };
  }
}

class _ConnectedPulse extends StatelessWidget {
  const _ConnectedPulse({required this.colors, required this.typography});

  final AppColors colors;
  final AppTypography typography;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '비콘 감지됨',
      child: SizedBox(
        width: BeaconPulse._outerSize,
        height: BeaconPulse._outerSize,
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
                decoration: BoxDecoration(shape: BoxShape.circle, color: colors.green),
              ),
            ),
            Container(
              width: BeaconPulse._innerSize,
              height: BeaconPulse._innerSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.green.withValues(alpha: 0.3),
              ),
            ),
            Text(
              'CONNETED',
              style: typography.title6.copyWith(color: colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisconnectedPulse extends StatelessWidget {
  const _DisconnectedPulse({required this.colors, required this.typography});

  final AppColors colors;
  final AppTypography typography;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '비콘을 찾는 중입니다',
      child: SizedBox(
        width: BeaconPulse._outerSize,
        height: BeaconPulse._outerSize,
        child: Center(
          child: Container(
            width: BeaconPulse._innerSize,
            height: BeaconPulse._innerSize,
            decoration: BoxDecoration(shape: BoxShape.circle, color: colors.gray1),
            alignment: Alignment.center,
            child: Text(
              'NOT CONNETED',
              style: typography.title6.copyWith(color: colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
