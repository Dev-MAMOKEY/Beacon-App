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
    required this.scrim,
    required this.label,
    required this.attendancePresent,
    required this.attendanceLate,
    required this.attendanceAbsent,
    required this.attendanceEtc,
    required this.iconBadge,
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

  /// 팝업(다이얼로그) 뒤를 덮는 스크림. Figma 변수에는 없고 팝업 프레임의
  /// 배경 불투명도(검정 40%)로만 표현돼 있던 값이라 토큰으로 승격한다 —
  /// `lib/components/ui/popup.dart`가 `Colors.black.withValues(alpha: 0.4)`를
  /// 직접 쓰던 자리다. 알파 0.4 = 0x66.
  final Color scrim;

  final Color label;

  /// 기록 캘린더(#12)의 날짜 배지 4종. Figma 컴포넌트 "날짜"(`289:2875`)의
  /// variant 배경을 그대로 옮긴 값이다 — 출석 `#91CAFF`(`289:2876`), 지각
  /// `#FDD97C`(`289:2878`), 결석 `#FF9797`(`289:2880`).
  ///
  /// [attendanceEtc]만 Figma에 없다. 그 컴포넌트의 네 번째 variant "기본"
  /// (`289:2882`)은 배경이 아예 없는(투명) 상태이고, 캘린더에서는 "그 날짜에
  /// 기록이 없음"을 뜻한다 — `AttendanceStatus.etc`(관리자가 수동으로 남기는
  /// 상태)와는 다른 개념이다. `etc`용 색은 사용자 판정으로 [gray4]와 같은
  /// 값을 쓴다. 값이 같아도 별도 토큰으로 두는 이유는 의미가 다르기
  /// 때문이다 — gray4는 구분선·비활성 배경이고 이건 출석 상태색이라,
  /// 나중에 Figma가 "기타" variant를 실제로 정의하면 여기만 바뀐다.
  final Color attendancePresent;
  final Color attendanceLate;
  final Color attendanceAbsent;
  final Color attendanceEtc;

  /// 마이페이지(#13) 리스트 카드의 아이콘 배지 배경. Figma `353:1692`·
  /// `353:1711` "Background" 실측 `#E9F4FF` — [bg](`#EEF7FF`)와 비슷하지만
  /// 다른 값이고 Figma 변수 목록에는 없어, [disconnectedGlow]·[scrim]과 같은
  /// 이유로 토큰으로 승격한다(값 자체는 Figma에서 그대로 뽑았다).
  final Color iconBadge;

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
    scrim: Color(0x66000000),
    label: Color(0xFF000000),
    attendancePresent: Color(0xFF91CAFF),
    attendanceLate: Color(0xFFFDD97C),
    attendanceAbsent: Color(0xFFFF9797),
    attendanceEtc: Color(0xFFE7E8E9),
    iconBadge: Color(0xFFE9F4FF),
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
    Color? scrim,
    Color? label,
    Color? attendancePresent,
    Color? attendanceLate,
    Color? attendanceAbsent,
    Color? attendanceEtc,
    Color? iconBadge,
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
      scrim: scrim ?? this.scrim,
      label: label ?? this.label,
      attendancePresent: attendancePresent ?? this.attendancePresent,
      attendanceLate: attendanceLate ?? this.attendanceLate,
      attendanceAbsent: attendanceAbsent ?? this.attendanceAbsent,
      attendanceEtc: attendanceEtc ?? this.attendanceEtc,
      iconBadge: iconBadge ?? this.iconBadge,
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
      scrim: Color.lerp(scrim, other.scrim, t)!,
      label: Color.lerp(label, other.label, t)!,
      attendancePresent: Color.lerp(attendancePresent, other.attendancePresent, t)!,
      attendanceLate: Color.lerp(attendanceLate, other.attendanceLate, t)!,
      attendanceAbsent: Color.lerp(attendanceAbsent, other.attendanceAbsent, t)!,
      attendanceEtc: Color.lerp(attendanceEtc, other.attendanceEtc, t)!,
      iconBadge: Color.lerp(iconBadge, other.iconBadge, t)!,
    );
  }
}
