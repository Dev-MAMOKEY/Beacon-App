import 'dart:async';

import 'package:flutter/widgets.dart';

/// 한 화면이 **루트 내비게이터에 직접 push한 라우트**(팝업·시트)의 소유권을
/// 한 곳에 모은다.
///
/// 세 화면이 각자 손으로 같은 것을 만들고 있었고 능력이 조금씩 달랐다 —
/// 홈은 목록 + 가시성 인지 동기화, 기록은 단일 라우트 + 날짜, 마이페이지는
/// 단일 라우트. 그 비대칭이 실제 결함(#41)의 원인이었다: 홈에 push 지점이
/// 셋인데 그중 하나만 가시성을 확인했고, 나머지 하나가 **사용자가 보고 있는
/// 다른 탭 위에** 모달을 띄웠다.
///
/// 그래서 이 클래스의 핵심 책임은 목록 관리가 아니라 **거부**다 — 화면이
/// 숨겨져 있으면 [push]가 아무것도 하지 않는다. 호출부마다 가드를 기억해야
/// 하는 구조를 없애는 것이 목적이므로, 가시성 확인을 호출부로 되돌리는
/// 변경은 이 클래스의 존재 이유를 지운다.
///
/// `StatefulShellRoute.indexedStack`은 선택되지 않은 브랜치를 dispose하지
/// 않고 살려 두므로, 숨은 화면이 계속 살아서 라우트를 push할 수 있다는 점이
/// 이 모든 것의 전제다.
class OwnedRoutes {
  OwnedRoutes(this._navigator);

  final NavigatorState _navigator;
  final List<Route<void>> _routes = [];

  /// 이 화면이 지금 사용자에게 보이는지. 화면이 `TickerMode`에서 유도해
  /// 갱신한다.
  bool visible = true;

  /// 지금 소유 중인 라우트가 있는지.
  bool get isEmpty => _routes.isEmpty;

  /// [route]가 이 소유자가 push한 것인지.
  bool owns(Route<void> route) => _routes.contains(route);

  /// 보일 때만 push한다. 숨겨져 있으면 **아무것도 하지 않고 null**을 돌려준다.
  ///
  /// 반환값을 라우트 정체성 추적에 쓰는 호출부(홈의 `_shownPopupRoute`)는
  /// null을 "띄우지 않았다"로 다뤄야 한다.
  Route<void>? push(Route<void> route) {
    if (!visible) return null;
    _routes.add(route);
    unawaited(
      _navigator.push<void>(route).then((_) => _routes.remove(route)),
    );
    return route;
  }

  /// 추적 상태만 비우고 라우트 목록을 돌려준다.
  ///
  /// 실제 제거([removeAll])와 분리돼 있는 이유: 빌드 단계에서는 내비게이션을
  /// 할 수 없어 제거를 프레임 뒤로 미뤄야 하는데, 추적 상태는 **지금 바로**
  /// 지워야 그 사이에 도착하는 이벤트가 "이미 떠 있다"고 오판하지 않는다.
  List<Route<void>> take() {
    final taken = List<Route<void>>.of(_routes);
    _routes.clear();
    return taken;
  }

  /// [routes] 중 아직 살아 있는 것만 제거한다.
  ///
  /// `Navigator.pop()`이 아니라 `removeRoute`인 이유: `pop`은 "스택 맨 위"를
  /// 닫을 뿐 정체성을 모른다 — 우리 라우트 위에 다른 것이 얹혀 있으면 엉뚱한
  /// 것이 닫히고 정작 닫아야 할 것은 남는다.
  /// `isActive` 검사를 지워도 실패하는 테스트가 없다(직접 확인) — 이미
  /// 닫힌 라우트를 다시 닫는 경로가 오늘은 없기 때문이다. 방어로 남긴다.
  void removeAll(List<Route<void>> routes) {
    for (final route in routes) {
      if (route.isActive) _navigator.removeRoute(route);
    }
  }

  /// 지금 소유 중인 것을 전부 즉시 닫는다.
  void closeAll() => removeAll(take());

  /// 소유한 것 중 **맨 위 하나**만 닫는다.
  ///
  /// 시트 위에 팝업을 얹는 화면이 필요로 한다. [closeAll]을 쓰면 팝업만
  /// 닫으려던 호출이 그 밑의 시트까지 닫는다.
  ///
  /// `remove(take().last)`로 흉내 내면 안 된다 — [take]가 추적을 통째로
  /// 비워서 밑의 시트가 **주인 없는 라우트**가 되고, 화면을 떠날 때
  /// [closeAll]이 그걸 못 닫아 다음 탭 위에 그대로 남는다(#41과 같은 결함).
  void closeTop() {
    if (_routes.isEmpty) return;
    remove(_routes.last);
  }

  /// 특정 라우트 하나만 닫는다.
  void remove(Route<void> route) {
    _routes.remove(route);
    if (route.isActive) _navigator.removeRoute(route);
  }
}
