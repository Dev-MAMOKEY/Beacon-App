import 'dart:io';

import 'package:beacon_app/core/theme/app_colors.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:beacon_app/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `AppColors`의 모든 필드를 읽고 쓰는 표. 필드를 추가하면 여기에 한 줄
/// 추가해야 한다 — 아래 두 테이블 테스트가 개수도 함께 고정한다.
final _colorFields = <String, (Color Function(AppColors), AppColors Function(AppColors, Color))>{
  'main': ((c) => c.main, (c, v) => c.copyWith(main: v)),
  'bg': ((c) => c.bg, (c, v) => c.copyWith(bg: v)),
  'white': ((c) => c.white, (c, v) => c.copyWith(white: v)),
  'gray1': ((c) => c.gray1, (c, v) => c.copyWith(gray1: v)),
  'gray2': ((c) => c.gray2, (c, v) => c.copyWith(gray2: v)),
  'gray3': ((c) => c.gray3, (c, v) => c.copyWith(gray3: v)),
  'gray4': ((c) => c.gray4, (c, v) => c.copyWith(gray4: v)),
  'yellow': ((c) => c.yellow, (c, v) => c.copyWith(yellow: v)),
  'red': ((c) => c.red, (c, v) => c.copyWith(red: v)),
  'green': ((c) => c.green, (c, v) => c.copyWith(green: v)),
  'disconnectedGlow': ((c) => c.disconnectedGlow, (c, v) => c.copyWith(disconnectedGlow: v)),
  'scrim': ((c) => c.scrim, (c, v) => c.copyWith(scrim: v)),
  'label': ((c) => c.label, (c, v) => c.copyWith(label: v)),
  'attendancePresent': ((c) => c.attendancePresent, (c, v) => c.copyWith(attendancePresent: v)),
  'attendanceLate': ((c) => c.attendanceLate, (c, v) => c.copyWith(attendanceLate: v)),
  'attendanceAbsent': ((c) => c.attendanceAbsent, (c, v) => c.copyWith(attendanceAbsent: v)),
  'attendanceEtc': ((c) => c.attendanceEtc, (c, v) => c.copyWith(attendanceEtc: v)),
  'iconBadge': ((c) => c.iconBadge, (c, v) => c.copyWith(iconBadge: v)),
};

/// `AppTypography`의 모든 필드를 읽고 쓰는 표. [_colorFields]와 같은 이유로
/// 필드를 추가하면 여기에도 한 줄 추가해야 한다.
final _textFields =
    <String, (TextStyle Function(AppTypography), AppTypography Function(AppTypography, TextStyle))>{
  'title3': ((t) => t.title3, (t, v) => t.copyWith(title3: v)),
  'title4': ((t) => t.title4, (t, v) => t.copyWith(title4: v)),
  'title6': ((t) => t.title6, (t, v) => t.copyWith(title6: v)),
  'title7': ((t) => t.title7, (t, v) => t.copyWith(title7: v)),
  'body1': ((t) => t.body1, (t, v) => t.copyWith(body1: v)),
  'body2': ((t) => t.body2, (t, v) => t.copyWith(body2: v)),
  'body3': ((t) => t.body3, (t, v) => t.copyWith(body3: v)),
  'body4': ((t) => t.body4, (t, v) => t.copyWith(body4: v)),
  'number1': ((t) => t.number1, (t, v) => t.copyWith(number1: v)),
};

const _textSentinel = TextStyle(fontFamily: 'Sentinel', fontSize: 99, letterSpacing: 3.25);

/// 필드 값이 전부 다른 타이포 기준값. `AppTypography.standard`를 기준으로
/// 쓰면 안 되는 이유는 [_distinctColors]와 같다 — 실제로 `body2`와 `title6`은
/// 크기(16)가 같고 `body3`와 `title7`도 크기(14)가 같아, 그 쌍 사이의
/// 오배선은 표준값으로는 절대 드러나지 않는다.
AppTypography _distinctTypography() {
  var seed = 0;
  TextStyle next() {
    seed++;
    return TextStyle(fontFamily: 'Distinct$seed', fontSize: seed.toDouble());
  }

  return AppTypography(
    title2: next(),
    title3: next(),
    title4: next(),
    title6: next(),
    title7: next(),
    body1: next(),
    body2: next(),
    body3: next(),
    body4: next(),
    number1: next(),
  );
}

const _sentinel = Color(0xFFDEADBE);

/// 모든 필드 값이 서로 다른 기준값.
///
/// 이 함수가 필요한 이유를 실제로 재현해서 확인했다. `AppColors.light`를
/// 기준값으로 쓰면 `attendanceEtc`와 `gray4`가 **같은 값**이라,
/// `attendanceEtc: attendanceEtc ?? this.gray4` 같은 오배선이 아래 표
/// 테스트를 그대로 통과한다 — 인자를 넘긴 경우엔 `??`의 왼쪽이 이기고,
/// 인자를 안 넘긴 경우엔 `this.gray4`가 우연히 정답과 같기 때문이다.
/// 기준값에 중복이 하나라도 있으면 그 두 필드 사이의 오배선은 영원히
/// 보이지 않는다. 그래서 값이 전부 다른 기준값을 따로 만든다.
AppColors _distinctColors() {
  var seed = 0;
  Color next() {
    seed++;
    // 1..18에 대해 전부 다른 값이고 _sentinel과도 겹치지 않는다.
    return Color(0xFF000000 | (seed * 0x010203));
  }

  return AppColors(
    main: next(),
    bg: next(),
    white: next(),
    gray1: next(),
    gray2: next(),
    gray3: next(),
    gray4: next(),
    yellow: next(),
    red: next(),
    green: next(),
    disconnectedGlow: next(),
    scrim: next(),
    label: next(),
    attendancePresent: next(),
    attendanceLate: next(),
    attendanceAbsent: next(),
    attendanceEtc: next(),
    iconBadge: next(),
  );
}

void main() {
  // 기준값이 실제로 전부 다른지부터 확인한다 — 중복이 생기면 아래 표
  // 테스트들이 조용히 무력화된다(그게 바로 `AppColors.light`를 안 쓰는
  // 이유다).
  test('표 테스트의 기준값은 필드 값이 전부 다르다', () {
    final base = _distinctColors();
    final values = _colorFields.values.map((f) => f.$1(base).toARGB32()).toList();
    expect(values.toSet(), hasLength(values.length), reason: '기준값에 중복이 있으면 오배선이 보이지 않는다');
    expect(values, isNot(contains(_sentinel.toARGB32())));
  });

  // 색은 `lib/core/theme/` 밖에서 하드코딩하지 않는다 — 그 금지는 Dart
  // 코드뿐 아니라 SVG 에셋 안에도 적용된다. 에셋에 토큰값을 구워 넣으면
  // `AppColors`를 바꿔도 그 아이콘만 옛 색으로 남는다(오늘은 전부
  // `ColorFilter(srcIn)`로 덧칠하니 화면상으로는 티가 안 나지만, 그래서
  // 오히려 조용히 썩는다 — 누군가 필터를 빼는 순간 옛 색이 되살아난다).
  //
  // 규칙: `assets/icons/*.svg`에는 16진수 색 리터럴이 없어야 한다. 중립
  // 플레이스홀더 키워드(`black`/`white`/`none`)만 허용한다 — Task 2의
  // `nav_*.svg`(`fill="black"`)와 `router-*.svg`(`fill="white"`)가 이미 쓰는
  // 관례이고, 실제 색은 위젯이 테마 토큰으로 칠한다.
  test('assets/icons의 SVG에는 16진수 색 리터럴이 없다', () {
    // 잡아야 할 잘못된 구현: Figma에서 내려받은 아이콘을 그대로 커밋해
    // `fill="#FBBF24"`(=AppColors.yellow)처럼 토큰값이 에셋에 박혀 있다.
    final iconsDir = Directory('assets/icons');
    expect(iconsDir.existsSync(), isTrue, reason: '테스트는 패키지 루트에서 실행된다');

    final svgFiles = iconsDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.svg'))
        .toList();
    expect(svgFiles, isNotEmpty);

    final hex = RegExp(r'#[0-9A-Fa-f]{3,8}');
    final offenders = <String>[];
    for (final file in svgFiles) {
      final matches = hex.allMatches(file.readAsStringSync()).map((m) => m[0]!).toSet();
      if (matches.isNotEmpty) {
        offenders.add('${file.uri.pathSegments.last}: ${matches.join(', ')}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '색은 테마 토큰(AppColors)에서만 나온다 — 에셋에는 중립 플레이스홀더만 둔다',
    );
  });

  test('테마에서 AppColors와 AppTypography를 꺼낼 수 있다', () {
    final theme = buildAppTheme();

    final colors = theme.extension<AppColors>();
    expect(colors, isNotNull);
    expect(colors!.main, const Color(0xFF54A2EA));
    expect(colors.bg, const Color(0xFFEEF7FF));
    expect(colors.red, const Color(0xFFFF5D5D));

    final typography = theme.extension<AppTypography>();
    expect(typography, isNotNull);
    expect(typography!.title4.fontFamily, 'Pretendard');
    expect(typography.title4.fontSize, 20);
    expect(typography.title4.fontWeight, FontWeight.w600);
    expect(typography.number1.fontFamily, 'Manrope');

    expect(theme.colorScheme.primary, AppColors.light.main);
    expect(theme.colorScheme.error, AppColors.light.red);
  });

  test('lerp는 t=0에서 원본을 유지한다', () {
    const a = AppColors.light;
    final b = a.copyWith(main: const Color(0xFF000000));
    final mid = a.lerp(b, 0);
    expect(mid.main, a.main);
    expect(mid.disconnectedGlow, a.disconnectedGlow);
  });

  // 이전 버전은 `original.copyWith()`를 인자 **하나도 없이** 부르고 모든
  // 필드가 그대로인지만 봤다 — `copyWith`가 어떤 필드를 아예 무시하고
  // `this.x`만 돌려줘도(=새 필드 `disconnectedGlow`·`scrim`이 배선에서
  // 빠져도) 그 테스트는 초록색이었다. 필드마다 실제로 값을 넘겨봐야
  // "인자가 그 필드에 도달하는가"를 증명할 수 있다.
  //
  // 필드를 추가하는 사람은 [_colorFields] 맵에도 한 줄 추가해야 한다 — 맵에
  // 넣지 않으면 그 필드는 여전히 무보증이다(그래서 개수도 함께 고정해 둔다).
  test('AppColors.copyWith()는 넘긴 필드만 바꾸고 나머지는 전부 유지한다', () {
    // 잡아야 할 잘못된 구현 두 가지:
    // 1) 새 필드를 copyWith 시그니처에만 넣고 본문에서는 `this.x`로 흘려
    //    보낸다 — 그 필드에 넘긴 인자가 조용히 무시된다.
    // 2) 필드를 잘못 배선한다(`green: green ?? this.main` 같은 복붙 실수)
    //    — 한 필드를 바꿨는데 다른 필드까지 같이 바뀐다.
    final original = _distinctColors();
    const sentinel = _sentinel;

    expect(_colorFields, hasLength(18), reason: 'AppColors에 필드를 추가하면 이 맵과 개수를 함께 갱신해야 한다');

    for (final entry in _colorFields.entries) {
      final (read, copy) = entry.value;
      final mutated = copy(original, sentinel);

      expect(read(mutated), sentinel, reason: '${entry.key}에 넘긴 값이 실제로 반영돼야 한다');

      for (final other in _colorFields.entries) {
        if (other.key == entry.key) continue;
        expect(
          other.value.$1(mutated),
          other.value.$1(original),
          reason: '${entry.key}만 바꿨는데 ${other.key}까지 바뀌었다',
        );
      }
    }

    // 인자를 하나도 주지 않으면 원본과 완전히 같아야 한다는 것도 함께 본다.
    final untouched = original.copyWith();
    for (final entry in _colorFields.entries) {
      expect(entry.value.$1(untouched), entry.value.$1(original), reason: entry.key);
    }
  });

  // Figma "날짜" 컴포넌트(`289:2875`)의 variant 배경 실측값. 이 값들은
  // 위젯 테스트가 "출석 셀은 attendancePresent로 칠해진다"만 확인해서는
  // 고정되지 않는다 — 토큰 자체가 엉뚱한 값이어도 위젯은 그 엉뚱한 값을
  // 충실히 쓰기 때문에 그런 테스트는 초록색이다. 값 자체를 여기서 못박는다.
  test('출석 상태 배지 색 4종이 Figma 실측값과 일치한다', () {
    // 잡아야 할 잘못된 구현: variant 색을 눈대중으로 옮겨 적는다(예:
    // attendancePresent를 main(#54A2EA)으로 대체), 또는 출석/지각 값을
    // 서로 바꿔 넣는다.
    const colors = AppColors.light;
    expect(colors.attendancePresent, const Color(0xFF91CAFF));
    expect(colors.attendanceLate, const Color(0xFFFDD97C));
    expect(colors.attendanceAbsent, const Color(0xFFFF9797));
    // "기타"는 Figma에 variant가 없다 — 사용자 판정으로 지금은 gray4와 같은
    // 값을 쓴다. **못박는 것은 그 값이지 "gray4와 같다"는 관계가 아니다.**
    //
    // 예전에는 `expect(colors.attendanceEtc, colors.gray4)`가 함께 있었는데,
    // 그건 두 토큰이 영원히 같이 움직여야 한다는 뜻이 되어 이 토큰을 따로 둔
    // 이유(의미가 다르므로 Figma가 "기타" variant를 정의하면 여기만 바뀐다)와
    // 정면으로 어긋났다. 게다가 두 값이 같다는 사실이 위젯 층의 실명을
    // 영구화했다 — `records_calendar.dart`가 `etc`를 `gray4`로 칠해도
    // 위젯 테스트가 눈치채지 못했다(리뷰 Important 6). 그 실명은
    // `records_screen_test.dart`가 attendanceEtc만 다른 값으로 덮어쓴 테마로
    // pump해 따로 잡는다.
    expect(colors.attendanceEtc, const Color(0xFFE7E8E9));
  });

  // `lerp`는 생성자 인자가 전부 required라 필드를 "빠뜨릴" 수는 없다
  // (컴파일이 안 된다) — 실제 위험은 복붙 오배선이다
  // (`attendanceLate: Color.lerp(attendancePresent, other.attendancePresent, t)`).
  // 기존 `lerp t=0` 테스트는 두 필드(main·disconnectedGlow)만 보고, t=0에서는
  // 오배선된 필드도 "원본 계열의 값"이라 우연히 통과할 수 있다. 필드마다
  // 그 필드 하나만 다른 상대와 t=1로 섞어, 그 필드가 정확히 상대의 **자기
  // 자신** 값을 가져오는지 본다.
  test('AppColors.lerp(t=1)은 필드마다 상대의 같은 필드 값을 가져온다', () {
    // 잡아야 할 잘못된 구현: lerp 본문에서 필드를 잘못 배선한다 — 한 필드를
    // 바꿨는데 다른 필드가 따라 바뀌거나, 그 필드가 안 바뀐다.
    final original = _distinctColors();
    const sentinel = _sentinel;

    expect(_colorFields, hasLength(18), reason: 'AppColors에 필드를 추가하면 이 맵과 개수를 함께 갱신해야 한다');

    for (final entry in _colorFields.entries) {
      final (read, copy) = entry.value;
      final target = copy(original, sentinel);
      final blended = original.lerp(target, 1);

      expect(
        read(blended).toARGB32(),
        sentinel.toARGB32(),
        reason: 't=1에서 ${entry.key}는 상대의 ${entry.key} 값이어야 한다',
      );

      for (final other in _colorFields.entries) {
        if (other.key == entry.key) continue;
        expect(
          other.value.$1(blended).toARGB32(),
          other.value.$1(original).toARGB32(),
          reason: '${entry.key}만 다른 상대와 섞었는데 ${other.key}까지 바뀌었다',
        );
      }
    }
  });

  // 이전 버전은 `original.copyWith()`를 인자 **하나도 없이** 부르고 모든
  // 스타일이 그대로인지만 봤다 — `AppColors`쪽에서 이미 확인된 것과 똑같은
  // 실명이다. 새 필드(`body4`)를 copyWith 시그니처에서 통째로 빼고 본문이
  // 항상 `this.body4`를 쓰게 만들어도 그 테스트는 초록색이었다. 필드마다
  // 실제로 값을 넘겨봐야 "인자가 그 필드에 도달하는가"를 증명할 수 있다.
  test('AppTypography.copyWith()는 넘긴 필드만 바꾸고 나머지는 전부 유지한다', () {
    // 잡아야 할 잘못된 구현:
    // 1) 새 스타일을 필드로만 추가하고 copyWith 인자에서 빠뜨린다.
    // 2) 복붙 오배선(`body4: body4 ?? this.body3`) — 한 스타일을 바꿨는데
    //    다른 스타일까지 따라 바뀐다.
    final original = _distinctTypography();

    expect(_textFields, hasLength(9), reason: 'AppTypography에 필드를 추가하면 이 맵과 개수를 함께 갱신해야 한다');

    for (final entry in _textFields.entries) {
      final (read, copy) = entry.value;
      final mutated = copy(original, _textSentinel);

      expect(read(mutated), _textSentinel, reason: '${entry.key}에 넘긴 값이 실제로 반영돼야 한다');

      for (final other in _textFields.entries) {
        if (other.key == entry.key) continue;
        expect(
          other.value.$1(mutated),
          other.value.$1(original),
          reason: '${entry.key}만 바꿨는데 ${other.key}까지 바뀌었다',
        );
      }
    }

    final untouched = original.copyWith();
    for (final entry in _textFields.entries) {
      expect(entry.value.$1(untouched), entry.value.$1(original), reason: entry.key);
    }
  });

  // `lerp`는 생성자 인자가 전부 required라 필드를 "빠뜨릴" 수는 없지만
  // 복붙 오배선은 그대로 가능하다(`AppColors.lerp`와 같은 이유).
  test('AppTypography.lerp(t=1)은 필드마다 상대의 같은 필드 값을 가져온다', () {
    // 잡아야 할 잘못된 구현: lerp 본문에서 필드를 잘못 배선한다 —
    // `body4: TextStyle.lerp(body3, other.body3, t)` 같은 복붙 실수.
    final original = _distinctTypography();

    for (final entry in _textFields.entries) {
      final (read, copy) = entry.value;
      final blended = original.lerp(copy(original, _textSentinel), 1);

      expect(
        read(blended).fontFamily,
        _textSentinel.fontFamily,
        reason: 't=1에서 ${entry.key}는 상대의 ${entry.key} 값이어야 한다',
      );

      for (final other in _textFields.entries) {
        if (other.key == entry.key) continue;
        expect(
          other.value.$1(blended).fontFamily,
          other.value.$1(original).fontFamily,
          reason: '${entry.key}만 다른 상대와 섞었는데 ${other.key}까지 바뀌었다',
        );
      }
    }
  });

  // Figma 스타일 `body4`(12/Medium/자간 0.6) 실측값. 위젯 테스트가
  // "부제는 body4로 그린다"만 확인해서는 고정되지 않는다 — 토큰 자체가
  // 엉뚱한 값이어도 위젯은 그 값을 충실히 쓰기 때문이다.
  test('body4는 Figma 실측값(12/Medium/자간 0.6)이다', () {
    // 잡아야 할 잘못된 구현: 가장 가까운 기존 토큰(body3, 14px)을 복사해
    // 크기만 안 고치거나, 자간 0.6을 빠뜨린다.
    final body4 = AppTypography.standard.body4;
    expect(body4.fontFamily, 'Pretendard');
    expect(body4.fontSize, 12);
    expect(body4.fontWeight, FontWeight.w500);
    expect(body4.letterSpacing, 0.6);
  });

  test('iconBadge는 Figma 실측값(#E9F4FF)이고 bg와 다른 색이다', () {
    // 잡아야 할 잘못된 구현: 눈대중으로 비슷한 기존 토큰(bg #EEF7FF)을
    // 그대로 쓴다 — 두 값은 실제로 다르다.
    const colors = AppColors.light;
    expect(colors.iconBadge, const Color(0xFFE9F4FF));
    expect(colors.iconBadge, isNot(colors.bg));
  });

  testWidgets('Theme.of(context).extension()으로 위젯 트리에서 토큰에 접근할 수 있다', (
    WidgetTester tester,
  ) async {
    AppColors? colorsFromContext;
    AppTypography? typographyFromContext;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) {
            colorsFromContext = Theme.of(context).extension<AppColors>();
            typographyFromContext =
                Theme.of(context).extension<AppTypography>();
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(colorsFromContext, isNotNull);
    expect(colorsFromContext!.main, AppColors.light.main);

    expect(typographyFromContext, isNotNull);
    expect(typographyFromContext!.title4.fontFamily, 'Pretendard');
  });
}
