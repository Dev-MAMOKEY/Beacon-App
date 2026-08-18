import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Figma 컴포넌트 "토글"(`353:1937`)을 그대로 옮긴 스위치.
///
/// 실측: 트랙 58×28에 완전 둥근 모서리, 안쪽 여백 2, 그래서 손잡이는
/// 24×24 흰 원이다. 켜짐(`353:1938`)은 트랙 `main` + 손잡이 오른쪽,
/// 꺼짐(`353:1940`)은 트랙 `gray2` + 손잡이 왼쪽이다.
///
/// Material의 [Switch]를 쓰지 않는 이유는 이 프로젝트가 Phase 1부터 UI
/// 프리미티브를 직접 소유해 온 방식(`button.dart`·`input.dart`)과 같다 —
/// Material 스위치는 손잡이 지름·트랙 두께·오버레이가 테마로 강제돼 이
/// 실측값을 낼 수 없다.
///
/// 비활성(disabled) 상태는 만들지 않았다 — Figma에 그 variant가 없고,
/// 유일한 소비자인 마이페이지는 요청이 진행 중이어도 토글을 잠그지 않는다
/// (겹친 요청은 화면 쪽의 세대 검사가 처리한다).
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  /// 스크린리더가 읽을 이름. 스위치 자체에는 글자가 없으므로 호출자가
  /// 반드시 준다 — 없으면 "켜짐"이라고만 읽히고 무엇이 켜졌는지 알 수 없다.
  final String semanticLabel;

  static const Key thumbKey = ValueKey('app_switch_thumb');

  static const double trackWidth = 58;
  static const double trackHeight = 28;
  static const double trackPadding = 2;
  static const double thumbSize = trackHeight - trackPadding * 2;

  /// 트랙 색·손잡이 위치가 함께 움직이는 시간. `button.dart`의
  /// `AnimatedContainer`와 같은 값이다.
  static const Duration duration = Duration(milliseconds: 120);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    return Semantics(
      toggled: value,
      label: semanticLabel,
      onTap: () => onChanged(!value),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: duration,
          width: trackWidth,
          height: trackHeight,
          padding: const EdgeInsets.all(trackPadding),
          decoration: BoxDecoration(
            color: value ? colors.main : colors.gray2,
            borderRadius: BorderRadius.circular(trackHeight / 2),
          ),
          child: AnimatedAlign(
            duration: duration,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              // 테스트가 손잡이의 실제 위치를 잴 수 있게 한다 — 트랙 색만
              // 확인하면 손잡이가 반대편에 박혀 있어도 통과한다.
              key: thumbKey,
              width: thumbSize,
              height: thumbSize,
              decoration: BoxDecoration(
                color: colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
