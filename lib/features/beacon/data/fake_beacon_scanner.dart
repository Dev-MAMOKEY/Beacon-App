import 'dart:async';

import '../domain/beacon_scanner.dart';

/// 화면·컨트롤러 테스트가 안정화 판정 없이 상태 시퀀스를 직접 스크립트할 수
/// 있게 해주는 테스트 더블. 안정화·블루투스 재연결·UUID 필터링 같은 실제
/// 로직은 [FlutterBeaconScanner](flutter_beacon_scanner.dart)가 이미 책임지고
/// 검증하므로, 여기서는 [emit]으로 넣은 상태를 그대로 흘려보내기만 한다.
class FakeBeaconScanner implements BeaconScanner {
  final StreamController<BeaconScanState> _controller = StreamController<BeaconScanState>.broadcast();

  /// 가장 최근 [watch] 호출에 넘어온 설정. 화면이 올바른 UUID/임계값으로
  /// 스캔을 시작했는지 검증할 때 쓴다.
  BeaconScanConfig? lastConfig;

  /// [watch]가 불린 횟수.
  int watchCallCount = 0;

  /// [stop]이 불린 횟수.
  int stopCallCount = 0;

  @override
  Stream<BeaconScanState> watch(BeaconScanConfig config) {
    watchCallCount++;
    lastConfig = config;
    return _controller.stream;
  }

  /// 테스트가 원하는 상태를 원하는 순서로 흘려보낸다.
  void emit(BeaconScanState state) {
    if (_controller.isClosed) return;
    _controller.add(state);
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
  }

  /// 테스트가 끝날 때 스트림을 정리한다. [stop]과 달리 이후 이 인스턴스를
  /// 다시 쓸 수 없게 만든다.
  Future<void> dispose() => _controller.close();
}
