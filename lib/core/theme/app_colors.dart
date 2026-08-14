import 'package:flutter/material.dart';

/// Figma 변수에서 그대로 옮긴 색 토큰.
/// 위젯은 이 확장을 통해서만 색을 읽는다.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.main,
    required this.bg,
    required this.white,
    required this.gray1,
    required this.gray2,
    required this.gray3,
    required this.gray4,
    required this.yellow,
    required this.red,
    required this.green,
    required this.disconnectedGlow,
    required this.label,
  });

  final Color main;
  final Color bg;
  final Color white;
  final Color gray1;
  final Color gray2;
  final Color gray3;
  final Color gray4;
  final Color yellow;
  final Color red;

  /// 비콘 감지(홈 화면) 동심원과 출석 성공 표시에 쓰는 초록. Figma 변수에는
  /// 없던 값이라 badge.dart의 success variant는 그동안 `main` 계열로
  /// 대체해 왔다 — 이 값을 뽑아낸 김에 그쪽도 이 토큰으로 갱신한다.
  final Color green;

  /// 홈 화면 동심원의 미감지(disconnected) 상태 글로우·내부 원 색.
  /// Figma 실측 `#94A8BD`(`339:1642`/`326:1587`) — 기존 `AppColors`에
  /// 없던 값이라 재작업 1차에서는 `gray1`로 임시 대체했었다. 이 값은
  /// 발명이 아니라 Figma에서 그대로 뽑아낸 값이라 토큰으로 승격한다.
  final Color disconnectedGlow;

  final Color label;

  static const AppColors light = AppColors(
    main: Color(0xFF54A2EA),
    bg: Color(0xFFEEF7FF),
    white: Color(0xFFFFFFFF),
    gray1: Color(0xFFB4B4B5),
    gray2: Color(0xFF787878),
    gray3: Color(0xFF414754),
    gray4: Color(0xFFE7E8E9),
    yellow: Color(0xFFFBBF24),
    red: Color(0xFFFF5D5D),
    green: Color(0xFF16CE69),
    disconnectedGlow: Color(0xFF94A8BD),
    label: Color(0xFF000000),
  );

  @override
  AppColors copyWith({
    Color? main,
    Color? bg,
    Color? white,
    Color? gray1,
    Color? gray2,
    Color? gray3,
    Color? gray4,
    Color? yellow,
    Color? red,
    Color? green,
    Color? disconnectedGlow,
    Color? label,
  }) {
    return AppColors(
      main: main ?? this.main,
      bg: bg ?? this.bg,
      white: white ?? this.white,
      gray1: gray1 ?? this.gray1,
      gray2: gray2 ?? this.gray2,
      gray3: gray3 ?? this.gray3,
      gray4: gray4 ?? this.gray4,
      yellow: yellow ?? this.yellow,
      red: red ?? this.red,
      green: green ?? this.green,
      disconnectedGlow: disconnectedGlow ?? this.disconnectedGlow,
      label: label ?? this.label,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      main: Color.lerp(main, other.main, t)!,
      bg: Color.lerp(bg, other.bg, t)!,
      white: Color.lerp(white, other.white, t)!,
      gray1: Color.lerp(gray1, other.gray1, t)!,
      gray2: Color.lerp(gray2, other.gray2, t)!,
      gray3: Color.lerp(gray3, other.gray3, t)!,
      gray4: Color.lerp(gray4, other.gray4, t)!,
      yellow: Color.lerp(yellow, other.yellow, t)!,
      red: Color.lerp(red, other.red, t)!,
      green: Color.lerp(green, other.green, t)!,
      disconnectedGlow: Color.lerp(disconnectedGlow, other.disconnectedGlow, t)!,
      label: Color.lerp(label, other.label, t)!,
    );
  }
}
