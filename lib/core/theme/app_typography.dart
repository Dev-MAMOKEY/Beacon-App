import 'package:flutter/material.dart';

/// Figma 텍스트 스타일 변수를 그대로 옮긴 타이포 토큰.
@immutable
class AppTypography extends ThemeExtension<AppTypography> {
  const AppTypography({
    required this.title2,
    required this.title3,
    required this.title4,
    required this.title6,
    required this.title7,
    required this.body1,
    required this.body2,
    required this.body3,
    required this.body4,
    required this.number1,
  });

  /// Figma `title2`(SemiBold 28, 자간 0). 초대코드 화면의 제목
  /// (`289:3264`)이 이 토큰을 쓴다 — 그전까지 쓰는 화면이 없어 토큰만
  /// 빠져 있었다(#61).
  final TextStyle title2;

  final TextStyle title3;
  final TextStyle title4;
  final TextStyle title6;
  final TextStyle title7;
  final TextStyle body1;
  final TextStyle body2;
  final TextStyle body3;

  /// Figma 스타일 `body4`(12/Medium/자간 0.6). 마이페이지(#13) 리스트 카드의
  /// 부제(`353:1577`·`353:1716`)가 처음 쓴다 — 그 전까지 12px 스타일을 쓰는
  /// 화면이 없어 토큰에도 없었다.
  final TextStyle body4;

  final TextStyle number1;

  static const String _pretendard = 'Pretendard';
  static const String _manrope = 'Manrope';

  static const AppTypography standard = AppTypography(
    title2: TextStyle(
      fontFamily: _pretendard,
      fontSize: 28,
      fontWeight: FontWeight.w600,
      height: 1,
    ),
    title3: TextStyle(
      fontFamily: _pretendard,
      fontSize: 24,
      fontWeight: FontWeight.w600,
      height: 1,
      letterSpacing: 0.5,
    ),
    title4: TextStyle(
      fontFamily: _pretendard,
      fontSize: 20,
      fontWeight: FontWeight.w600,
      height: 1,
      letterSpacing: 0.25,
    ),
    title6: TextStyle(
      fontFamily: _pretendard,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1,
    ),
    title7: TextStyle(
      fontFamily: _pretendard,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1,
      letterSpacing: 0.7,
    ),
    body1: TextStyle(
      fontFamily: _pretendard,
      fontSize: 18,
      fontWeight: FontWeight.w500,
      height: 1,
    ),
    body2: TextStyle(
      fontFamily: _pretendard,
      fontSize: 16,
      fontWeight: FontWeight.w500,
      height: 1,
    ),
    body3: TextStyle(
      fontFamily: _pretendard,
      fontSize: 14,
      fontWeight: FontWeight.w500,
      height: 1,
    ),
    body4: TextStyle(
      fontFamily: _pretendard,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1,
      letterSpacing: 0.6,
    ),
    number1: TextStyle(
      fontFamily: _manrope,
      fontSize: 50,
      fontWeight: FontWeight.w500,
      height: 1,
    ),
  );

  @override
  AppTypography copyWith({
    TextStyle? title2,
    TextStyle? title3,
    TextStyle? title4,
    TextStyle? title6,
    TextStyle? title7,
    TextStyle? body1,
    TextStyle? body2,
    TextStyle? body3,
    TextStyle? body4,
    TextStyle? number1,
  }) {
    return AppTypography(
      title2: title2 ?? this.title2,
      title3: title3 ?? this.title3,
      title4: title4 ?? this.title4,
      title6: title6 ?? this.title6,
      title7: title7 ?? this.title7,
      body1: body1 ?? this.body1,
      body2: body2 ?? this.body2,
      body3: body3 ?? this.body3,
      body4: body4 ?? this.body4,
      number1: number1 ?? this.number1,
    );
  }

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    return AppTypography(
      title2: TextStyle.lerp(title2, other.title2, t)!,
      title3: TextStyle.lerp(title3, other.title3, t)!,
      title4: TextStyle.lerp(title4, other.title4, t)!,
      title6: TextStyle.lerp(title6, other.title6, t)!,
      title7: TextStyle.lerp(title7, other.title7, t)!,
      body1: TextStyle.lerp(body1, other.body1, t)!,
      body2: TextStyle.lerp(body2, other.body2, t)!,
      body3: TextStyle.lerp(body3, other.body3, t)!,
      body4: TextStyle.lerp(body4, other.body4, t)!,
      number1: TextStyle.lerp(number1, other.number1, t)!,
    );
  }
}
