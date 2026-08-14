import 'package:beacon_app/components/nav/app_top_bar.dart';
import 'package:beacon_app/core/theme/app_colors.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:beacon_app/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) {
  return MaterialApp(theme: buildAppTheme(), home: Scaffold(body: child));
}

/// `AppColors.light.gray2`(#787878)와 겹치지 않는 커스텀 테마 — 알림
/// 아이콘 채색이 자산에 박힌 리터럴이 아니라 진짜 테마를 읽는지 구분하는
/// 유일한 방법(기본 테마로는 우연히 같은 색이라 구분이 안 된다).
const _customGray2 = Color(0xFF445566);
final _customColors = AppColors.light.copyWith(gray2: _customGray2);

void main() {
  testWidgets('아주 긴 제목(사용자 이름)은 오버플로 없이 한 줄 + 줄임표로 잘린다', (tester) async {
    // 홈 화면은 이 자리에 사용자 이름을 넣는다. 이 Row의 교차축(세로,
    // 높이 56 고정)은 flutter의 RenderFlex가 오버플로 예외/경고
    // 줄무늬를 그리는 축이 아니다(그건 주축 — Column의 세로/Row의
    // 가로만 해당, 직접 확인했다). maxLines·overflow 없이 두면 예외
    // 없이 "조용히" 텍스트가 바 높이(56)까지 늘어나 버린다.
    final longTitle = '가나다라마바사아자차' * 20;
    await tester.pumpWidget(_host(AppTopBar(title: longTitle)));
    await tester.pump();

    expect(tester.takeException(), isNull);

    // 줄임표 자체를 직접 확인한다 — `TextOverflow.clip`이나
    // `softWrap: false`도 "한 줄 높이"라는 결과만 보면 통과해 버린다.
    final textWidget = tester.widget<Text>(find.text(longTitle));
    expect(textWidget.maxLines, 1);
    expect(textWidget.overflow, TextOverflow.ellipsis);

    // body1(18px, height 1.0)이므로 한 줄 높이는 정확히 18이어야 한다.
    final textHeight = tester.getSize(find.text(longTitle)).height;
    expect(textHeight, lessThan(30));
  });

  testWidgets('알림 아이콘 색은 자산에 박힌 리터럴이 아니라 AppColors.gray2에서 온다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [_customColors, AppTypography.standard]),
        home: const Scaffold(body: AppTopBar()),
      ),
    );
    await tester.pump();

    final pictures = tester.widgetList<SvgPicture>(find.byType(SvgPicture)).toList();
    // 좌측 로고 다음이 알림 아이콘 — 두 SvgPicture 중 gray2 필터를 쓰는
    // 쪽을 찾는다(로고는 main을 쓴다).
    final notification = pictures.firstWhere(
      (p) => p.colorFilter == const ColorFilter.mode(_customGray2, BlendMode.srcIn),
      orElse: () => throw StateError('알림 아이콘이 gray2 colorFilter로 렌더되지 않았다'),
    );
    expect(notification.colorFilter, const ColorFilter.mode(_customGray2, BlendMode.srcIn));
  });
}
