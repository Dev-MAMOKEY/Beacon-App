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
      label: Color.lerp(label, other.label, t)!,
    );
  }
}
