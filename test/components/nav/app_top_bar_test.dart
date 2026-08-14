import 'package:beacon_app/components/nav/app_top_bar.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) {
  return MaterialApp(theme: buildAppTheme(), home: Scaffold(body: child));
}

void main() {
  testWidgets('아주 긴 제목(사용자 이름)은 오버플로 없이 한 줄로 잘린다', (tester) async {
    // 홈 화면은 이 자리에 사용자 이름을 넣는다. 이 Row의 교차축(세로,
    // 높이 56 고정)은 go_router 확인과 달리 flutter의 RenderFlex가
    // 오버플로 예외/경고 줄무늬를 그리는 축이 아니다(그건 주축 — 세로로
    // 쌓는 Column의 세로/가로로 배치하는 Row의 가로만 해당). maxLines·
    // overflow 없이 두면 예외 없이 "조용히" 텍스트가 바 높이(56)까지
    // 늘어나 버린다 — 실제로 확인했다(WRONG_IMPL에서 Size(_, 56.0)).
    // 그래서 "예외가 나지 않는다"가 아니라 "실제로 한 줄 높이로
    // 렌더된다"를 직접 측정해 검증한다 — 이게 이 버그를 잡는 유일하게
    // 신뢰할 수 있는 방법이다.
    final longTitle = '가나다라마바사아자차' * 20;
    await tester.pumpWidget(_host(AppTopBar(title: longTitle)));
    await tester.pump();

    expect(tester.takeException(), isNull);

    // body1(18px, height 1.0)이므로 한 줄 높이는 정확히 18이어야 한다.
    // maxLines/overflow가 없으면 이 Row의 교차축 제약(56)까지 그대로
    // 늘어나 56.0이 된다 — 아래 잘못된 구현에서 실측했다.
    final textHeight = tester.getSize(find.text(longTitle)).height;
    expect(textHeight, lessThan(30));
  });
}
