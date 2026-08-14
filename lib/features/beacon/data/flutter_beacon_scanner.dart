import 'dart:async';
import 'dart:math';

import 'package:dchs_flutter_beacon/dchs_flutter_beacon.dart' as beacon_lib;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/beacon_scanner.dart';

/// 권한이 승인됐다고 볼 수 있는지 판정한다. Android는
/// [beacon_lib.AuthorizationStatus.allowed] 하나뿐이고, iOS는 "항상"과
/// "사용 중"을 구분한다. `AuthorizationStatus`가 `==`를 오버라이드하므로
/// `const Set` 리터럴에 넣을 수 없어 함수로 판정한다.
bool _isAuthorizationGranted(beacon_lib.AuthorizationStatus status) {
  return status == beacon_lib.AuthorizationStatus.allowed ||
      status == beacon_lib.AuthorizationStatus.always ||
      status == beacon_lib.AuthorizationStatus.whenInUse;
}

/// [beacon_lib.DchsFlutterBeacon]을 감싸 [BeaconScanner] 계약으로 바꾸는
/// 어댑터. 이 클래스의 핵심은 안정화 판정이다: `dchs_flutter_beacon`의
/// ranging 스트림은 하드웨어 스캔 주기마다 이벤트를 흘려보내는데, 그 이벤트
/// 자체가 시간의 흐름을 담고 있으므로 별도 `Timer`나 `Stream.periodic` 없이
/// "이 이벤트가 도착한 시각"([_now])만으로 "임계값 이상이 얼마나 연속됐는가"
/// 를 계산한다. 테스트는 [rangingStreamFactory]·[bluetoothStateStreamFactory]
/// ·[now] 를 주입해 실제 BLE 하드웨어나 실제 시간 경과 없이 이 로직을
/// 구동한다.
class FlutterBeaconScanner implements BeaconScanner {
  FlutterBeaconScanner({
    Stream<beacon_lib.RangingResult> Function(List<beacon_lib.Region> regions)? rangingStreamFactory,
    Stream<beacon_lib.BluetoothState> Function()? bluetoothStateStreamFactory,
    Future<beacon_lib.BluetoothState> Function()? currentBluetoothState,
    Future<bool> Function()? initializeAndCheckScanning,
    Future<beacon_lib.AuthorizationStatus> Function()? authorizationStatus,
    DateTime Function()? now,
  })  : _rangingStreamFactory = rangingStreamFactory ?? beacon_lib.flutterBeacon.ranging,
        _bluetoothStateStreamFactory = bluetoothStateStreamFactory ?? beacon_lib.flutterBeacon.bluetoothStateChanged,
        _currentBluetoothState = currentBluetoothState ?? (() => beacon_lib.flutterBeacon.bluetoothState),
        _initializeAndCheckScanning =
            initializeAndCheckScanning ?? (() => beacon_lib.flutterBeacon.initializeAndCheckScanning),
        _authorizationStatus = authorizationStatus ?? (() => beacon_lib.flutterBeacon.authorizationStatus),
        _now = now ?? DateTime.now;

  final Stream<beacon_lib.RangingResult> Function(List<beacon_lib.Region> regions) _rangingStreamFactory;
  final Stream<beacon_lib.BluetoothState> Function() _bluetoothStateStreamFactory;
  final Future<beacon_lib.BluetoothState> Function() _currentBluetoothState;
  final Future<bool> Function() _initializeAndCheckScanning;
  final Future<beacon_lib.AuthorizationStatus> Function() _authorizationStatus;
  final DateTime Function() _now;

  StreamController<BeaconScanState>? _controller;
  StreamSubscription<beacon_lib.BluetoothState>? _bluetoothSub;
  StreamSubscription<beacon_lib.RangingResult>? _rangingSub;

  /// 지금 블루투스가 꺼져 있다고 보고 있는지. off→on "전이"만 재개 신호로
  /// 삼기 위한 플래그다 — 그렇지 않으면 최초 구독 시 스트림이 흘려보내는
  /// 첫 상태(꼭 변화가 아니어도)에도 반응해 ranging을 이중으로 시작할 수
  /// 있다.
  bool _bluetoothOff = false;

  /// 현재 연속 스트릭이 임계값 이상으로 시작된 시각. `null`이면 스트릭이
  /// 없다(직전 프레임이 임계값 아래였거나 아직 프레임이 없다).
  DateTime? _streakStart;

  /// 마지막으로 내보낸 상태가 [BeaconDetected]였는지. 다음 프레임이 나쁠 때
  /// [BeaconOutOfRange]로 보낼지 그냥 [BeaconScanning]으로 보낼지 가른다.
  bool _isDetected = false;

  @override
  Stream<BeaconScanState> watch(BeaconScanConfig config) {
    _teardownSubscriptions();
    unawaited(_controller?.close());

    final controller = StreamController<BeaconScanState>();
    _controller = controller;
    _streakStart = null;
    _isDetected = false;
    _bluetoothOff = false;

    controller.onListen = () => unawaited(_start(config, controller));
    controller.onCancel = () {
      _teardownSubscriptions();
      if (identical(_controller, controller)) {
        _controller = null;
      }
    };

    return controller.stream;
  }

  Future<void> _start(BeaconScanConfig config, StreamController<BeaconScanState> controller) async {
    // 블루투스 상태 변화는 초기화가 끝나길 기다리는 동안에도 놓치면 안 되므로
    // 가장 먼저 구독한다.
    _bluetoothSub = _bluetoothStateStreamFactory().listen((state) {
      _handleBluetoothState(state, config, controller);
    });

    final beacon_lib.BluetoothState initialState;
    try {
      initialState = await _currentBluetoothState();
    } catch (_) {
      // 초기 상태를 읽지 못해도 변화 스트림은 이미 구독 중이니 계속
      // 진행한다 — 켜져 있다고 낙관적으로 가정한다.
      await _initializeAndStartRanging(config, controller);
      return;
    }
    if (controller.isClosed) return;

    if (initialState == beacon_lib.BluetoothState.stateOff) {
      _bluetoothOff = true;
      controller.add(const BeaconBluetoothOff());
      return;
    }

    await _initializeAndStartRanging(config, controller);
  }

  Future<void> _initializeAndStartRanging(
    BeaconScanConfig config,
    StreamController<BeaconScanState> controller,
  ) async {
    bool initialized;
    try {
      initialized = await _initializeAndCheckScanning();
    } catch (_) {
      initialized = false;
    }
    if (controller.isClosed) return;

    if (!initialized) {
      beacon_lib.AuthorizationStatus status;
      try {
        status = await _authorizationStatus();
      } catch (_) {
        status = beacon_lib.AuthorizationStatus.denied;
      }
      if (controller.isClosed) return;
      if (!_isAuthorizationGranted(status)) {
        controller.add(const BeaconPermissionDenied());
        return;
      }
      // 권한은 있는데 초기화가 실패했다 — 위치 서비스나 블루투스가 꺼져
      // 있는 경우가 대부분이다. 블루투스 변화 스트림이 실제 on/off를
      // 알려줄 것이므로 스캐닝 상태로 두고 재시도하지 않는다.
    }

    controller.add(const BeaconScanning());
    _startRanging(config, controller);
  }

  void _handleBluetoothState(
    beacon_lib.BluetoothState state,
    BeaconScanConfig config,
    StreamController<BeaconScanState> controller,
  ) {
    if (controller.isClosed) return;

    if (state == beacon_lib.BluetoothState.stateOff) {
      if (_bluetoothOff) return;
      _bluetoothOff = true;
      _cancelRanging();
      _streakStart = null;
      _isDetected = false;
      controller.add(const BeaconBluetoothOff());
    } else if (state == beacon_lib.BluetoothState.stateOn) {
      if (!_bluetoothOff) return;
      _bluetoothOff = false;
      controller.add(const BeaconScanning());
      _startRanging(config, controller);
    }
    // 그 외(turning on/off, unknown, resetting 등)는 과도기 상태라 무시한다.
  }

  void _startRanging(BeaconScanConfig config, StreamController<BeaconScanState> controller) {
    final region = beacon_lib.Region(identifier: config.uuid, proximityUUID: config.uuid);
    _rangingSub = _rangingStreamFactory([region]).listen((result) {
      _handleRanging(result, config, controller);
    });
  }

  void _handleRanging(
    beacon_lib.RangingResult result,
    BeaconScanConfig config,
    StreamController<BeaconScanState> controller,
  ) {
    if (controller.isClosed) return;

    // 네이티브 쪽 region 필터를 신뢰하지 않고 우리 쪽에서도 UUID를 다시
    // 확인한다 — 다른 동아리/무관한 비콘을 절대 우리 것으로 취급하지 않기
    // 위해서다.
    final target = config.uuid.toUpperCase();
    final matches = result.beacons.where((b) => b.proximityUUID.toUpperCase() == target).toList();

    final int? rssi = matches.isEmpty ? null : matches.map((b) => b.rssi).reduce(max);
    final isGood = rssi != null && rssi >= config.rssiThreshold;

    if (isGood) {
      final now = _now();
      final streakStart = _streakStart ??= now;
      final elapsed = now.difference(streakStart);
      if (elapsed >= Duration(seconds: config.stabilizationSeconds)) {
        _isDetected = true;
        controller.add(BeaconDetected(rssi));
      } else {
        controller.add(const BeaconScanning());
      }
    } else {
      // 연속성이 깨졌다 — 스트릭을 처음부터 다시 센다.
      _streakStart = null;
      if (_isDetected) {
        _isDetected = false;
        controller.add(const BeaconOutOfRange());
      } else {
        controller.add(const BeaconScanning());
      }
    }
  }

  void _cancelRanging() {
    _rangingSub?.cancel();
    _rangingSub = null;
  }

  void _teardownSubscriptions() {
    _cancelRanging();
    _bluetoothSub?.cancel();
    _bluetoothSub = null;
  }

  @override
  Future<void> stop() async {
    _teardownSubscriptions();
    final controller = _controller;
    _controller = null;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
  }
}

final beaconScannerProvider = Provider<BeaconScanner>((ref) {
  return FlutterBeaconScanner();
});
