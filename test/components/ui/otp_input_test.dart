import 'package:beacon_app/components/ui/otp_input.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('기본값은 출석 코드 팝업의 Figma 실측이다', (tester) async {
    // 잡아야 할 잘못된 구현: 기본값을 초대코드 쪽 수치(43/12/14/영숫자)로
    // 바꾼다. #61에서 이 위젯을 두 화면이 공유하도록 매개변수화하면서
    // **바꿀 수 있게** 만들었는데 검증이 없어, 네 값을 전부 바꿔도 454개가
    // 그대로 통과했다(#63).
    //
    // 이 프로젝트가 이미 두 번 밟은 함정과 같다 — `Timer.new` 기본값,
    // 홈의 `DateTime.now` 기본값. 주입점의 프로덕션 기본값을 지나는 검사가
    // 어딘가에 하나는 있어야 한다.
    //
    // 실측 출처: `339:1683` 출석코드 팝업 — 칸 56×64, 간격 16, 반경 12.
    await tester.pumpWidget(_host(AppOtpInput(length: 4, onCompleted: (_) {})));
    await tester.pump();

    final cell = tester.widgetList<SizedBox>(find.byType(SizedBox)).where(
      (box) => box.width == 56 && box.height == 64,
    );
    expect(cell, hasLength(4), reason: '칸은 56×64다');

    final gaps = tester.widgetList<SizedBox>(find.byType(SizedBox)).where(
      (box) => box.width == 16 && box.height == null,
    );
    expect(gaps, hasLength(3), reason: '칸 사이 간격은 16이고 바깥쪽엔 없다');

    final field = tester.widget<TextField>(find.byType(TextField).first);
    final border = field.decoration!.enabledBorder! as OutlineInputBorder;
    expect(border.borderRadius, BorderRadius.circular(12));
    expect(field.keyboardType, TextInputType.number, reason: '출석 코드는 숫자 전용이다');
  });

  testWidgets('length만큼 칸을 그린다', (tester) async {
    await tester.pumpWidget(_host(AppOtpInput(length: 4, onCompleted: (_) {})));
    await tester.pump();

    expect(find.byType(TextField), findsNWidgets(4));
  });

  // Figma 실측(339:1683, 파일 O9RRQnJwoqsjU8LrJKeaAX)에서 드러난 요소 —
  // 빈 칸은 흰 배경+테두리가 아니라 gray4로 채워지고 가운뎃점(·)
  // 플레이스홀더를 보여준다. 최초 구현(프로즈 브리핑 기반)에는 이
  // 플레이스홀더가 아예 없었다.
  testWidgets('빈 칸은 가운뎃점(·) 플레이스홀더를 보여준다', (tester) async {
    // 잡아야 할 잘못된 구현: hintText를 설정하지 않아 빈 칸이 완전히
    // 비어 보인다.
    await tester.pumpWidget(_host(AppOtpInput(length: 4, onCompleted: (_) {})));
    await tester.pump();

    expect(find.text('·'), findsNWidgets(4));
  });

  testWidgets('마지막 자리를 채우면 onCompleted가 한 번 호출된다', (tester) async {
    final entered = <String>[];
    await tester.pumpWidget(
      _host(AppOtpInput(length: 4, onCompleted: entered.add)),
    );
    await tester.pump();

    const digits = ['7', '3', '2', '9'];
    final fields = find.byType(TextField);
    for (var i = 0; i < digits.length; i++) {
      await tester.enterText(fields.at(i), digits[i]);
      await tester.pump();
    }

    expect(entered, ['7329']);
  });

  // 예전에는 0번 칸만 채우고 0번 칸만 확인했다 — 첫 칸만 지우는 구현도
  // "모든 칸이 비워진다"는 이름을 달고 통과했다. 모든 칸을 채우고 모든 칸을
  // 확인한다.
  testWidgets('reset하면 모든 칸이 비워진다', (tester) async {
    final controller = AppOtpController();
    await tester.pumpWidget(
      _host(AppOtpInput(length: 4, controller: controller, onCompleted: (_) {})),
    );
    await tester.pump();

    final fields = find.byType(TextField);
    const digits = ['1', '2', '3', '4'];
    for (var i = 0; i < digits.length; i++) {
      await tester.enterText(fields.at(i), digits[i]);
      await tester.pump();
    }
    for (var i = 0; i < digits.length; i++) {
      expect(
        tester.widget<TextField>(fields.at(i)).controller!.text,
        digits[i],
        reason: 'shake 전에는 \$i번 칸이 실제로 채워져 있어야 검증이 의미가 있다',
      );
    }

    controller.shake();
    await tester.pump();

    for (var i = 0; i < digits.length; i++) {
      expect(
        tester.widget<TextField>(fields.at(i)).controller!.text,
        isEmpty,
        reason: '$i번 칸이 남아 있으면 다음 입력이 옛 값과 섞인다',
      );
    }
  });

  testWidgets('빈 칸에서 backspace를 누르면 이전 칸으로 이동해 그 칸을 지운다', (tester) async {
    await tester.pumpWidget(_host(AppOtpInput(length: 4, onCompleted: (_) {})));
    await tester.pump();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '5');
    await tester.pump();
    // '5' 입력 후 두 번째 칸(index 1)으로 자동 포커스된 상태.

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    final first = tester.widget<TextField>(fields.at(0));
    expect(first.controller!.text, isEmpty);
  });

  testWidgets('컨트롤러를 교체하면 이전 컨트롤러의 신호는 무시하고 새 컨트롤러를 따른다', (tester) async {
    final controllerA = AppOtpController();
    final controllerB = AppOtpController();

    await tester.pumpWidget(
      _host(AppOtpInput(length: 4, controller: controllerA, onCompleted: (_) {})),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, '1');
    await tester.pump();

    await tester.pumpWidget(
      _host(AppOtpInput(length: 4, controller: controllerB, onCompleted: (_) {})),
    );
    await tester.pump();

    // 옛 컨트롤러(A)의 리스너는 이미 떨어졌어야 한다 — 신호를 보내도 무시된다.
    controllerA.shake();
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, '1');

    // 새 컨트롤러(B)로 신호를 보내면 실제로 반응한다.
    controllerB.shake();
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, isEmpty);
  });
}
