import 'package:beacon_app/components/nav/app_bottom_nav.dart';
import 'package:beacon_app/core/theme/app_colors.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) {
  return MaterialApp(theme: buildAppTheme(), home: Scaffold(body: child));
}

/// `AppBottomNav` 안에서 라벨 `Text` 위젯이 렌더된 순서 그대로 뽑는다 —
/// 개수와 순서를 동시에 검증하는 데 쓴다. `find.text('...')`로 하나씩
/// 존재 여부만 확인하면 항목이 뒤섞여도(잘못된 순서) 통과해 버린다.
List<String> _renderedLabelsInOrder(WidgetTester tester) {
  final texts = tester.widgetList<Text>(
    find.descendant(of: find.byType(AppBottomNav), matching: find.byType(Text)),
  );
  return texts.map((t) => t.data!).toList();
}

void main() {
  testWidgets('showAdmin: false면 홈/기록/마이 3개가 이 순서로만 렌더된다', (tester) async {
    await tester.pumpWidget(
      _host(AppBottomNav(currentIndex: 0, showAdmin: false, onTap: (_) {})),
    );

    // 개수와 순서를 함께 본다 — 라벨 4개가 뒤섞인 순서로 있어도
    // find.text 단독 검사로는 못 잡는다.
    expect(_renderedLabelsInOrder(tester), ['홈', '기록', '마이']);
  });

  testWidgets('showAdmin: true면 홈/기록/관리자/마이 4개가 이 순서로 렌더된다', (tester) async {
    await tester.pumpWidget(
      _host(AppBottomNav(currentIndex: 0, showAdmin: true, onTap: (_) {})),
    );

    expect(_renderedLabelsInOrder(tester), ['홈', '기록', '관리자', '마이']);
  });

  testWidgets('탭을 누르면 그 탭 자신의 브랜치 인덱스로만 onTap이 호출된다', (tester) async {
    var tapped = -1;
    await tester.pumpWidget(
      _host(AppBottomNav(currentIndex: 0, showAdmin: true, onTap: (index) => tapped = index)),
    );

    // 네 탭 전부 자기 자신의 인덱스를 돌려주는지 하나씩 확인한다 — 마이
    // 하나만 확인하면 나머지 셋이 잘못된 인덱스를 돌려줘도 못 잡는다.
    const expected = {'홈': 0, '기록': 1, '관리자': 2, '마이': 3};
    for (final entry in expected.entries) {
      tapped = -1;
      await tester.tap(find.text(entry.key));
      await tester.pump();
      expect(tapped, entry.value, reason: '"${entry.key}" 탭은 인덱스 ${entry.value}를 돌려줘야 한다');
    }
  });

  testWidgets('선택된 탭 아이콘은 main, 나머지는 gray1로 칠해진다', (tester) async {
    // currentIndex: 1 == 기록이 선택된 상태.
    await tester.pumpWidget(
      _host(AppBottomNav(currentIndex: 1, showAdmin: true, onTap: (_) {})),
    );

    final icons = tester
        .widgetList<SvgPicture>(
          find.descendant(of: find.byType(AppBottomNav), matching: find.byType(SvgPicture)),
        )
        .toList();

    expect(icons, hasLength(4));
    final main = ColorFilter.mode(AppColors.light.main, BlendMode.srcIn);
    final gray1 = ColorFilter.mode(AppColors.light.gray1, BlendMode.srcIn);
    expect(icons[0].colorFilter, gray1, reason: '홈(0)은 선택되지 않았다');
    expect(icons[1].colorFilter, main, reason: '기록(1)이 선택됐다');
    expect(icons[2].colorFilter, gray1, reason: '관리자(2)는 선택되지 않았다');
    expect(icons[3].colorFilter, gray1, reason: '마이(3)는 선택되지 않았다');
  });
}
