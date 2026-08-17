import '../../support/fake_beacon_scanner.dart';
import 'package:beacon_app/features/beacon/domain/beacon_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

/// [FakeBeaconScanner]는 모든 Phase 2 화면 테스트가 의존할 테스트 더블이다
/// — 이 더블이 [BeaconScanner]의 생애주기 계약(재구독이 이전 세션을
/// 대체하고, `stop()` 이후에는 아무것도 방출하지 않는다)을 지키지 못하면,
/// 그 계약을 어기는 화면 쪽 버그를 이 더블에 의존하는 어떤 테스트도 잡지
/// 못한다.
final _config = BeaconScanConfig(uuid: 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0');

void main() {
  test('두 번째 watch()가 이전 스트림을 대체한다 — 이전 구독자는 더는 이벤트를 받지 않는다', () async {
    // 잡아야 할 잘못된 구현: watch()가 매번 같은 컨트롤러의 스트림을
    // 그대로 반환해, 옛 구독자와 새 구독자가 동시에 같은 이벤트를 받는다.
    final scanner = FakeBeaconScanner();
    addTearDown(scanner.dispose);

    final firstEvents = <BeaconScanState>[];
    scanner.watch(_config).listen(firstEvents.add);

    scanner.watch(_config); // 재구독 — 이전 스트림은 대체돼야 한다

    final secondEvents = <BeaconScanState>[];
    scanner.watch(_config).listen(secondEvents.add);

    scanner.emit(const BeaconScanning());
    await pumpEventQueue();

    expect(
      firstEvents,
      isEmpty,
      reason: '가장 처음 watch()로 받은 구독은 이미 두 번 대체됐으니 새 emit을 받으면 안 된다',
    );
    expect(secondEvents, [const BeaconScanning()]);
  });

  test('stop() 이후의 emit()은 무시된다', () async {
    // 잡아야 할 잘못된 구현: stop()이 카운터만 올릴 뿐 구독을 끊지 않아,
    // emit()이 stop() 이후에도 계속 화면에 전달된다.
    final scanner = FakeBeaconScanner();
    addTearDown(scanner.dispose);

    final events = <BeaconScanState>[];
    scanner.watch(_config).listen(events.add);

    scanner.emit(const BeaconScanning());
    await pumpEventQueue();
    expect(events, [const BeaconScanning()]);

    await scanner.stop();
    scanner.emit(const BeaconDetected(-60)); // stop() 이후 — 전달되면 안 된다
    await pumpEventQueue();

    expect(
      events,
      [const BeaconScanning()],
      reason: 'stop() 이후의 emit()은 아무 구독자에게도 전달되면 안 된다',
    );
  });

  test('stop() 이후에도 새 watch()로 다시 시작할 수 있다', () async {
    final scanner = FakeBeaconScanner();
    addTearDown(scanner.dispose);

    scanner.watch(_config).listen((_) {});
    await scanner.stop();

    final events = <BeaconScanState>[];
    scanner.watch(_config).listen(events.add);
    scanner.emit(const BeaconScanning());
    await pumpEventQueue();

    expect(events, [const BeaconScanning()]);
  });
}
