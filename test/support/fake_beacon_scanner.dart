import 'dart:async';

import 'package:beacon_app/features/beacon/domain/beacon_scanner.dart';

/// 화면·컨트롤러 테스트가 안정화 판정 없이 상태 시퀀스를 직접 스크립트할 수
/// 있게 해주는 테스트 더블. 안정화·블루투스 재연결·UUID 필터링 같은 실제
/// 로직은 [FlutterBeaconScanner](flutter_beacon_scanner.dart)가 이미 책임지고
/// 검증하므로, 여기서는 [emit]으로 넣은 상태를 그대로 흘려보내기만 한다.
///
/// [BeaconScanner]의 생애주기 계약(재구독이 이전 세션을 대체하고, `stop()`
/// 이후에는 아무것도 방출하지 않는다)만큼은 실제 구현과 똑같이 지킨다 —
/// 이 계약이 새면, 이 가짜에 의존하는 모든 화면 테스트가 실제 스캐너였다면
/// 잡았을 같은 부류의 버그(옛 구독이 계속 살아있는 것)를 놓치게 된다.
class FakeBeaconScanner implements BeaconScanner {
  StreamController<BeaconScanState>? _controller;
  bool _disposed = false;

  /// 가장 최근 [watch] 호출에 넘어온 설정. 화면이 올바른 UUID/임계값으로
  /// 스캔을 시작했는지 검증할 때 쓴다.
  BeaconScanConfig? lastConfig;

  /// [watch]가 불린 횟수.
  int watchCallCount = 0;

  /// [stop]이 불린 횟수.
  int stopCallCount = 0;

  @override
  Stream<BeaconScanState> watch(BeaconScanConfig config) {
    if (_disposed) {
      throw StateError('dispose된 FakeBeaconScanner는 다시 쓸 수 없다.');
    }
    watchCallCount++;
    lastConfig = config;

    // 이전 watch()의 스트림을 즉시 닫는다 — 실제 FlutterBeaconScanner가
    // 재구독마다 이전 세션을 교체하고 그 구독을 정리하는 것과 같은 계약이다.
    // 이걸 하지 않으면 옛 구독자가 새 watch() 이후에도 emit을 계속 받아,
    // "재진입 시 이전 스캔이 대체된다"는 화면 쪽 가정을 이 가짜가 깨뜨린다.
    final old = _controller;
    if (old != null && !old.isClosed) {
      unawaited(old.close());
    }

    final controller = StreamController<BeaconScanState>.broadcast();
    _controller = controller;
    return controller.stream;
  }

  /// 테스트가 원하는 상태를 원하는 순서로 흘려보낸다. [stop] 이후나 옛
  /// [watch] 세션에는 아무것도 전달되지 않는다.
  void emit(BeaconScanState state) {
    final controller = _controller;
    if (controller == null || controller.isClosed) return;
    controller.add(state);
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
    final controller = _controller;
    _controller = null;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
  }

  /// 테스트가 끝날 때 스트림을 정리한다. [stop]과 달리 이후 이 인스턴스를
  /// 다시 쓸 수 없게 만든다.
  Future<void> dispose() async {
    _disposed = true;
    final controller = _controller;
    _controller = null;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
  }
}
