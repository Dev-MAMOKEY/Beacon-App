import 'dart:io';

import 'package:beacon_app/core/theme/app_colors.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:beacon_app/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
  // 필드를 추가하는 사람은 아래 맵에도 한 줄 추가해야 한다 — 맵에 넣지
  // 않으면 그 필드는 여전히 무보증이다(그래서 개수도 함께 고정해 둔다).
  test('AppColors.copyWith()는 넘긴 필드만 바꾸고 나머지는 전부 유지한다', () {
    // 잡아야 할 잘못된 구현 두 가지:
    // 1) 새 필드를 copyWith 시그니처에만 넣고 본문에서는 `this.x`로 흘려
    //    보낸다 — 그 필드에 넘긴 인자가 조용히 무시된다.
    // 2) 필드를 잘못 배선한다(`green: green ?? this.main` 같은 복붙 실수)
    //    — 한 필드를 바꿨는데 다른 필드까지 같이 바뀐다.
    const original = AppColors.light;
    const sentinel = Color(0xFF0B0C0D);

    final fields = <String, (Color Function(AppColors), AppColors Function(AppColors, Color))>{
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
    };

    expect(fields, hasLength(13), reason: 'AppColors에 필드를 추가하면 이 맵과 개수를 함께 갱신해야 한다');

    for (final entry in fields.entries) {
      final (read, copy) = entry.value;
      final mutated = copy(original, sentinel);

      expect(read(mutated), sentinel, reason: '${entry.key}에 넘긴 값이 실제로 반영돼야 한다');

      for (final other in fields.entries) {
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
    for (final entry in fields.entries) {
      expect(entry.value.$1(untouched), entry.value.$1(original), reason: entry.key);
    }
  });

  test('AppTypography.copyWith()는 인자가 없으면 모든 스타일을 그대로 유지한다', () {
    const original = AppTypography.standard;
    final copy = original.copyWith();

    expect(copy.title3, original.title3);
    expect(copy.title4, original.title4);
    expect(copy.title6, original.title6);
    expect(copy.title7, original.title7);
    expect(copy.body1, original.body1);
    expect(copy.body2, original.body2);
    expect(copy.body3, original.body3);
    expect(copy.number1, original.number1);
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
