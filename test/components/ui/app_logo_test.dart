import 'package:beacon_app/components/ui/app_logo.dart';
import 'package:beacon_app/core/theme/app_colors.dart';
import 'package:beacon_app/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// `AppColors.light.main`(#54A2EA)과 겹치지 않는 커스텀 테마. 로고
/// 렌더링이 실제로 이 테마를 읽는지, 아니면 자산(`beacon_logo.svg`)에
/// 박힌 `#54A2EA` 리터럴을 몰래 그대로 쓰는지를 구분하는 유일한 방법은
/// 색이 다른 테마를 넣어 보는 것뿐이다 — 기본 테마로만 확인하면 두 경우
/// 다 같은 색으로 보여 구분이 안 된다.
const _customMain = Color(0xFF123456);
final _customColors = AppColors.light.copyWith(main: _customMain);

Widget _host(Widget child) {
  return MaterialApp(
    theme: ThemeData(extensions: [_customColors, AppTypography.standard]),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('로고 색은 자산에 박힌 리터럴이 아니라 AppColors.main에서 온다', (tester) async {
    await tester.pumpWidget(_host(const AppLogo()));
    await tester.pump();

    final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(picture.colorFilter, const ColorFilter.mode(_customMain, BlendMode.srcIn));
  });
}
