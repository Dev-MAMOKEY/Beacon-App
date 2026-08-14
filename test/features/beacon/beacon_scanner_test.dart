import 'dart:async';

import 'package:beacon_app/features/beacon/data/flutter_beacon_scanner.dart';
import 'package:beacon_app/features/beacon/domain/beacon_scanner.dart';
import 'package:dchs_flutter_beacon/dchs_flutter_beacon.dart' as beacon_lib;
import 'package:flutter_test/flutter_test.dart';

const String _uuid = 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0';
const String _otherUuid = 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE';

/// [beacon_lib.RangingResult]는 `RangingResult.from(json)`으로만 만들 수
/// 있으므로(공개 생성자가 없다), 테스트가 원하는 (uuid, rssi) 조합을 그
/// json 모양으로 감싼다. `beacons`가 비어 있으면 "이번 스캔 프레임에 우리
/// region과 일치하는 비콘이 하나도 없었다"를 뜻한다.
beacon_lib.RangingResult _ranging(List<(String uuid, int rssi)> beacons) {
  return beacon_lib.RangingResult.from({
    'region': {'identifier': 'test-region'},
    'beacons': [
      for (final b in beacons) {'proximityUUID': b.$1, 'major': 1, 'minor': 1, 'rssi': b.$2, 'accuracy': 1.0},
    ],
  });
}

/// 테스트가 직접 흐르게 하는 가짜 시계. `FlutterBeaconScanner`는 이 시계로만
/// "지금"을 알아내므로, 실제로 몇 초를 기다리지 않고도 안정화 판정을
/// 결정적으로 구동할 수 있다.
class _FakeClock {
  _FakeClock(this._now);

  DateTime _now;

  DateTime call() => _now;

  void advance(Duration duration) => _now = _now.add(duration);
}

/// [FlutterBeaconScanner]가 실제 BLE 대신 이 더블들을 쓰도록 배선한다.
/// ranging 스트림은 호출마다(=재구독마다) 새 컨트롤러를 만든다 — 실제
/// dchs_flutter_beacon의 `ranging()`도 호출마다 새 EventChannel 구독을
/// 시작하고, 그 구독이 취소되면 네이티브 스캔도 멈추기 때문이다. 여기서는
/// 그 취소가 실제로 일어났는지를 `rangingCancelCount`로 관찰한다.
class _Harness {
  _Harness({
    beacon_lib.BluetoothState initialBluetoothState = beacon_lib.BluetoothState.stateOn,
    bool initializeSucceeds = true,
    beacon_lib.AuthorizationStatus authorization = beacon_lib.AuthorizationStatus.allowed,
    DateTime? startAt,
  }) : clock = _FakeClock(startAt ?? DateTime(2026, 8, 14)) {
    scanner = FlutterBeaconScanner(
      rangingStreamFactory: (regions) {
        lastRegions = regions;
        rangingStarts++;
        final controller = StreamController<beacon_lib.RangingResult>(onCancel: () => rangingCancelCount++);
        rangingControllers.add(controller);
        return controller.stream;
      },
      bluetoothStateStreamFactory: () => bluetoothController.stream,
      currentBluetoothState: () async => initialBluetoothState,
      initializeAndCheckScanning: () async => initializeSucceeds,
      authorizationStatus: () async => authorization,
      now: clock.call,
    );
  }

  final _FakeClock clock;
  late final FlutterBeaconScanner scanner;
  final StreamController<beacon_lib.BluetoothState> bluetoothController = StreamController<beacon_lib.BluetoothState>();
  final List<StreamController<beacon_lib.RangingResult>> rangingControllers = [];
  List<beacon_lib.Region>? lastRegions;
  int rangingStarts = 0;
  int rangingCancelCount = 0;
  final List<BeaconScanState> states = [];

  StreamController<beacon_lib.RangingResult> get currentRanging => rangingControllers.last;

  /// [config]로 스캔을 시작하고, 최초 초기화(권한·초기 블루투스 상태
  /// 확인)가 끝나 ranging 구독이 실제로 걸릴 때까지 기다린다.
  Future<void> start(BeaconScanConfig config) async {
    scanner.watch(config).listen(states.add);
    await pumpEventQueue();
  }

  void emitGood(int rssi, {String uuid = _uuid}) => currentRanging.add(_ranging([(uuid, rssi)]));

  void emitBad({String uuid = _uuid, int rssi = -100}) => currentRanging.add(_ranging([(uuid, rssi)]));

  void emitEmpty() => currentRanging.add(_ranging(const []));

  Future<void> settle() => pumpEventQueue();
}

void main() {
  const config = BeaconScanConfig(uuid: _uuid, rssiThreshold: -70, stabilizationSeconds: 3);

  test('임계값 이상이 안정화 시간 미만이면 Detected를 방출하지 않는다', () async {
    // 잡아야 할 잘못된 구현: 첫 프레임에서 바로 Detected를 방출한다.
    final h = _Harness();
    await h.start(config);

    h.emitGood(-60); // t=0, 아직 0초 연속
    await h.settle();

    expect(h.states, isNot(contains(isA<BeaconDetected>())));
    expect(h.states.last, isA<BeaconScanning>());
  });

  test('임계값 이상이 안정화 시간 이상 지속되면 Detected를 방출한다', () async {
    // 잡아야 할 잘못된 구현: 영원히 Scanning만 방출한다(안정화 조건을 절대
    // 만족시키지 못함).
    final h = _Harness();
    await h.start(config);

    h.emitGood(-60); // t=0
    await h.settle();
    h.clock.advance(const Duration(seconds: 3));
    h.emitGood(-55); // t=3, 연속 3초 이상 임계값 이상
    await h.settle();

    expect(h.states.last, isA<BeaconDetected>());
    expect((h.states.last as BeaconDetected).rssi, -55);
  });

  test('중간에 임계값 아래로 떨어지면 타이머가 리셋되어 처음부터 다시 센다', () async {
    // 잡아야 할 잘못된 구현: 연속성을 보지 않고 "좋은 프레임" 사이 간격을
    // 무조건 누적한다 — 아래 시나리오에서 t=0 good, t=1 good(누적 1초),
    // t=1 bad(무시), t=3 good이 들어오면 누적 구현은 (3-1)=2초를 더해
    // 총 3초가 됐다고 착각해 이 시점에 Detected를 방출한다. 연속성을 보는
    // 구현은 bad 프레임에서 스트릭이 끊겼으므로 t=3의 스트릭 시작은 t=3
    // 자신이고, 경과 0초라 Scanning이어야 한다.
    final h = _Harness();
    await h.start(config);

    h.emitGood(-60); // t=0
    await h.settle();
    h.clock.advance(const Duration(seconds: 1));
    h.emitGood(-60); // t=1, 연속 1초
    await h.settle();
    h.emitBad(); // t=1, 임계값 아래로 떨어짐 -> 리셋
    await h.settle();
    h.clock.advance(const Duration(seconds: 2));
    h.emitGood(-60); // t=3, 리셋됐다면 이제 막 시작한 스트릭(0초)
    await h.settle();

    expect(
      h.states.last,
      isA<BeaconScanning>(),
      reason: 'bad 프레임 이후에는 처음부터 다시 3초를 채워야 Detected가 나와야 한다',
    );

    // 리셋 이후에도 실제로 3초를 연속으로 채우면 정상적으로 Detected가
    // 나온다는 것까지 확인한다.
    h.clock.advance(const Duration(seconds: 3));
    h.emitGood(-60); // t=6, 새 스트릭(t=3) 기준 연속 3초
    await h.settle();

    expect(h.states.last, isA<BeaconDetected>());
  });

  test('Detected 이후 신호가 끊기면 OutOfRange로 전이한다', () async {
    // 잡아야 할 잘못된 구현: Detected를 한 번 방출하고 이후 상태를 그대로
    // 고정한다.
    final h = _Harness();
    await h.start(config);

    h.emitGood(-60); // t=0
    await h.settle();
    h.clock.advance(const Duration(seconds: 3));
    h.emitGood(-60); // t=3, Detected
    await h.settle();
    expect(h.states.last, isA<BeaconDetected>());

    h.emitBad(); // 신호가 끊김
    await h.settle();

    expect(h.states.last, isA<BeaconOutOfRange>());
  });

  test('블루투스가 꺼지면 BluetoothOff로 전이하고 ranging 구독을 취소한다', () async {
    // 잡아야 할 잘못된 구현: 상태만 BluetoothOff로 바꾸고 ranging 구독은
    // 그대로 유지한다(=배터리 낭비, 꺼진 블루투스로 계속 스캔 시도).
    final h = _Harness();
    await h.start(config);
    expect(h.rangingCancelCount, 0);

    h.bluetoothController.add(beacon_lib.BluetoothState.stateOff);
    await h.settle();

    expect(h.states.last, isA<BeaconBluetoothOff>());
    expect(
      h.rangingCancelCount,
      1,
      reason: 'ranging 스트림 구독이 실제로 취소되어야 한다 — 상태만 바뀌는 것으론 부족하다',
    );
  });

  test('블루투스가 다시 켜지면 스캔을 재개한다', () async {
    // 잡아야 할 잘못된 구현: 한 번 꺼지면 다시 켜져도 영구히 멈춰 있는다.
    final h = _Harness();
    await h.start(config);

    h.bluetoothController.add(beacon_lib.BluetoothState.stateOff);
    await h.settle();
    expect(h.states.last, isA<BeaconBluetoothOff>());
    expect(h.rangingStarts, 1);

    h.bluetoothController.add(beacon_lib.BluetoothState.stateOn);
    await h.settle();

    expect(h.states.last, isA<BeaconScanning>());
    expect(h.rangingStarts, 2, reason: '재개됐다면 ranging 구독을 새로 시작해야 한다');

    // 재개된 구독이 실제로 살아 있는지, 새 프레임을 처리하는지까지 확인한다.
    h.emitGood(-60);
    await h.settle();
    h.clock.advance(const Duration(seconds: 3));
    h.emitGood(-60);
    await h.settle();

    expect(h.states.last, isA<BeaconDetected>());
  });

  test('다른 UUID의 비콘은 무시한다', () async {
    // 잡아야 할 잘못된 구현: region으로 걸러지지 않은 모든 비콘을 우리 것으로
    // 취급한다.
    final h = _Harness();
    await h.start(config);

    h.emitGood(-50, uuid: _otherUuid); // t=0, 남의 비콘이지만 신호는 강함
    await h.settle();
    h.clock.advance(const Duration(seconds: 5));
    h.emitGood(-50, uuid: _otherUuid); // t=5, 5초 연속이어도 남의 비콘
    await h.settle();

    expect(
      h.states,
      isNot(contains(isA<BeaconDetected>())),
      reason: '다른 UUID의 비콘 신호가 아무리 강하고 오래 지속돼도 Detected로 이어지면 안 된다',
    );
    expect(h.states.last, isA<BeaconScanning>());
  });

  test('빈 ranging 결과(주변에 비콘 없음)는 나쁜 프레임으로 취급된다', () async {
    final h = _Harness();
    await h.start(config);

    h.emitGood(-60);
    await h.settle();
    h.clock.advance(const Duration(seconds: 3));
    h.emitGood(-60);
    await h.settle();
    expect(h.states.last, isA<BeaconDetected>());

    h.emitEmpty();
    await h.settle();

    expect(h.states.last, isA<BeaconOutOfRange>());
  });

  test('watch(config)는 region에 proximityUUID를 항상 담아 넘긴다 (iOS 요구사항)', () async {
    final h = _Harness();
    await h.start(config);

    expect(h.lastRegions, hasLength(1));
    expect(h.lastRegions!.single.proximityUUID, _uuid);
  });
}
