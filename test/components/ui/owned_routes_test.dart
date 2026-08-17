import 'package:beacon_app/components/ui/owned_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [OwnedRoutes]의 핵심 책임은 목록 관리가 아니라 **거부**다 — 화면이
/// 숨겨져 있으면 push가 아무 일도 하지 않아야 한다. 세 화면이 각자 손으로
/// 만들던 시절에는 홈의 push 지점 셋 중 하나만 가시성을 확인했고, 그 빠진
/// 하나가 사용자가 보고 있는 다른 탭 위에 모달을 띄웠다(#41).
class _StackObserver extends NavigatorObserver {
  final List<Route<dynamic>> stack = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => stack.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => stack.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => stack.remove(route);
}

Route<void> _route(String label) => DialogRoute<void>(
  context: _context!,
  builder: (context) => Text(label),
);

BuildContext? _context;

Future<({OwnedRoutes owned, _StackObserver routes})> _pump(WidgetTester tester) async {
  final routes = _StackObserver();
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [routes],
      home: Builder(
        builder: (context) {
          _context = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return (owned: OwnedRoutes(navigatorKey.currentState!), routes: routes);
}

void main() {
  testWidgets('보이는 동안에는 push한다', (tester) async {
    final (:owned, :routes) = await _pump(tester);

    final pushed = owned.push(_route('A'));
    await tester.pumpAndSettle();

    expect(pushed, isNotNull);
    expect(routes.stack, hasLength(2));
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('숨겨져 있으면 push하지 않고 null을 돌려준다', (tester) async {
    // 잡아야 할 잘못된 구현: 가시성 판정을 호출부에 맡긴다 — 호출부가 하나만
    // 늘어도 그 하나를 잊는 순간 다른 탭 위에 모달이 뜬다.
    final (:owned, :routes) = await _pump(tester);
    owned.visible = false;

    final pushed = owned.push(_route('A'));
    await tester.pumpAndSettle();

    expect(pushed, isNull);
    expect(routes.stack, hasLength(1), reason: '라우트 스택이 늘어나면 안 된다');
    expect(find.text('A'), findsNothing);
    expect(owned.isEmpty, isTrue, reason: '띄우지 않았으므로 소유하지도 않는다');
  });

  testWidgets('다시 보이면 push가 재개된다', (tester) async {
    // 부정 짝이 없으면 "항상 거부한다"는 구현도 통과한다.
    final (:owned, :routes) = await _pump(tester);
    owned.visible = false;
    owned.push(_route('A'));
    await tester.pumpAndSettle();
    expect(routes.stack, hasLength(1));

    owned.visible = true;
    owned.push(_route('B'));
    await tester.pumpAndSettle();

    expect(routes.stack, hasLength(2));
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('closeAll은 소유한 것만 전부 닫는다', (tester) async {
    final (:owned, :routes) = await _pump(tester);
    owned.push(_route('A'));
    await tester.pumpAndSettle();
    // 소유하지 않은 라우트를 위에 얹는다.
    final foreign = _route('외부');
    _pushForeign(foreign);
    await tester.pumpAndSettle();
    expect(routes.stack, hasLength(3));

    owned.closeAll();
    await tester.pumpAndSettle();

    expect(find.text('A'), findsNothing);
    expect(find.text('외부'), findsOneWidget, reason: '남의 라우트를 닫으면 안 된다');
    expect(owned.isEmpty, isTrue);
  });

  testWidgets('take는 추적만 비우고 라우트는 화면에 남긴다', (tester) async {
    // 빌드 단계에서는 내비게이션을 할 수 없어 제거를 프레임 뒤로 미뤄야
    // 하는데, 추적 상태는 지금 바로 지워야 그 사이 도착하는 이벤트가
    // "이미 떠 있다"고 오판하지 않는다.
    final (:owned, :routes) = await _pump(tester);
    owned.push(_route('A'));
    await tester.pumpAndSettle();

    final taken = owned.take();

    expect(taken, hasLength(1));
    expect(owned.isEmpty, isTrue, reason: '추적은 즉시 비운다');
    expect(routes.stack, hasLength(2), reason: '실제 제거는 아직이다');

    owned.removeAll(taken);
    await tester.pumpAndSettle();
    expect(routes.stack, hasLength(1));
  });

  group('closeTop', () {
    testWidgets('맨 위 하나만 닫고 밑은 남긴다', (tester) async {
      // 시트 위에 팝업을 얹는 화면이 필요로 하는 동작이다. `closeAll`을
      // 쓰면 팝업만 닫으려던 호출이 그 밑의 시트까지 닫는다.
      final (:owned, :routes) = await _pump(tester);
      owned.push(_route('시트'));
      await tester.pumpAndSettle();
      owned.push(_route('팝업'));
      await tester.pumpAndSettle();

      owned.closeTop();
      await tester.pumpAndSettle();

      expect(find.text('팝업'), findsNothing);
      expect(find.text('시트'), findsOneWidget);
    });

    testWidgets('남은 라우트를 계속 소유한다', (tester) async {
      // 호출부가 `remove(take().last)`로 흉내 내던 동작의 결함이 여기다 —
      // `take()`가 추적을 통째로 비우는 바람에 밑의 시트가 **주인 없는
      // 라우트**가 된다. 그러면 화면을 떠날 때 `closeAll`이 그걸 못 닫고,
      // 시트가 다음 탭 위에 그대로 남는다(#41과 같은 결함).
      final (:owned, :routes) = await _pump(tester);
      final sheet = owned.push(_route('시트'))!;
      await tester.pumpAndSettle();
      owned.push(_route('팝업'));
      await tester.pumpAndSettle();

      owned.closeTop();
      await tester.pumpAndSettle();

      expect(owned.owns(sheet), isTrue, reason: '시트는 여전히 이 화면 소유다');

      owned.closeAll();
      await tester.pumpAndSettle();
      expect(find.text('시트'), findsNothing);
      expect(routes.stack, hasLength(1));
    });

    testWidgets('소유한 것이 없으면 아무것도 닫지 않는다', (tester) async {
      // 남의 라우트가 위에 얹혀 있을 때 그걸 닫아 버리면 안 된다.
      final (:owned, :routes) = await _pump(tester);
      _pushForeign(_route('외부'));
      await tester.pumpAndSettle();

      owned.closeTop();
      await tester.pumpAndSettle();

      expect(find.text('외부'), findsOneWidget);
      expect(routes.stack, hasLength(2));
    });
  });

  testWidgets('사용자가 닫은 라우트는 소유 목록에서 스스로 빠진다', (tester) async {
    final (:owned, :routes) = await _pump(tester);
    final pushed = owned.push(_route('A'))!;
    await tester.pumpAndSettle();
    expect(owned.owns(pushed), isTrue);

    Navigator.of(_context!, rootNavigator: true).removeRoute(pushed);
    await tester.pumpAndSettle();

    expect(owned.isEmpty, isTrue, reason: '남아 있으면 closeAll이 이미 없는 것을 닫으려 든다');
    expect(routes.stack, hasLength(1));
  });
}

void _pushForeign(Route<void> route) {
  Navigator.of(_context!, rootNavigator: true).push<void>(route);
}
