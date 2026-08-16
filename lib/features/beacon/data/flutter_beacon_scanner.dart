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

/// UUID를 비교 가능한 정본 형태로 만든다 — 하이픈 유무와 대소문자를 모두
/// 무시한다. 서버가 내려주는 UUID와 네이티브 ranging 결과의 UUID가 하이픈
/// 표기만 다를 뿐인데 서로 다른 것으로 취급되면, 사용자는 실제로 우리
/// 비콘 옆에 있어도 영원히 [BeaconScanning]에 머문다.
String _normalizeUuid(String uuid) => uuid.replaceAll('-', '').toUpperCase();

/// [FlutterBeaconScanner.watch] 한 번의 생애주기 동안 필요한 가변 상태를
/// 전부 묶는다. 구독(bluetooth/ranging)과 스트릭 상태를 이 객체 안에만
/// 두는 이유는, 여러 `watch()` 호출이 시간상 겹칠 수 있기 때문이다 — 이전
/// 세션의 정리(teardown)가 비동기로 끝나기 전에 새 세션이 이미 시작될 수
/// 있고, 만약 구독을 스캐너 인스턴스의 공유 필드에 저장했다면 이전 세션의
/// 뒤늦은 정리가 새 세션의 구독을 대신 잘라버리는 사고가 난다. 세션마다
/// 독립된 필드를 쓰면 이 사고는 애초에 구조적으로 불가능하다.
class _Session {
  _Session(this.config, this.controller, this.elapsed);

  final BeaconScanConfig config;
  final StreamController<BeaconScanState> controller;

  /// `watch()`가 시작된 시점부터 흐른 시간. 벽시계(`DateTime.now()`)가
  /// 아니라 단조 시계(모노토닉)여야 한다 — NTP 동기화 등으로 벽시계가
  /// 앞으로 튀면 안정화 조건이 실제로는 연속되지 않은 신호를 연속된 것으로
  /// 착각해 통과시켜 버린다.
  final Duration Function() elapsed;

  StreamSubscription<beacon_lib.BluetoothState>? bluetoothSub;
  StreamSubscription<beacon_lib.RangingResult>? rangingSub;

  /// [BeaconDetected]를 내보낸 뒤 무장하는 만료 타이머.
  ///
  /// 이게 없으면 [BeaconScanConfig.maxSampleGap]은 **다음 샘플이 도착할 때만**
  /// 평가된다. 스트림이 조용해지면 — 앱이 백그라운드로 가면 ranging이 정확히
  /// 그렇게 멈춘다 — 감지 상태가 무기한 남아, 방을 나갔다 돌아와도 출석이
  /// 그대로 통과한다(리뷰 Critical). `checkIn` 요청은 근접 증거를 담지 않아
  /// 서버가 재검증할 수 없으므로, 이 만료가 보증의 일부다.
  Timer? expiryTimer;

  /// 지금 블루투스가 꺼져 있다고 보고 있는지. off→on "전이"만 재개 신호로
  /// 삼기 위한 플래그다 — 그렇지 않으면 최초 구독 시 스트림이 흘려보내는
  /// 첫 상태(꼭 변화가 아니어도)에도 반응해 ranging을 이중으로 시작할 수
  /// 있다.
  bool bluetoothOff = false;

  /// 마지막으로 내보낸 상태가 [BeaconDetected](또는 그 이후 [BeaconOutOfRange])
  /// 였는지 — [BeaconOutOfRange]는 안정적이어야 하므로, 새 스트릭이 다시
  /// 안정화 시간을 채워 [BeaconDetected]가 다시 나오기 전까지는 계속 true로
  /// 남는다.
  bool isDetected = false;

  /// 현재 연속 스트릭이 임계값 이상으로 시작된 시각(경과 시간 기준).
  /// `null`이면 스트릭이 없다.
  Duration? streakStart;

  /// 스트릭 안에서 가장 최근 "좋은" 샘플이 도착한 시각. [BeaconScanConfig.maxSampleGap]
  /// 보다 오래 새 좋은 샘플이 오지 않으면 침묵으로 보고 스트릭을 리셋한다.
  Duration? lastGoodSampleAt;

  /// `_initializeAndStartRanging` 시도가 시작될 때마다 증가한다. 블루투스가
  /// 꺼지는 등으로 시도가 무효화된 뒤에도 뒤늦게 끝나는 옛 시도가 ranging을
  /// 시작해 버리는 것을 막는 세대 값이다.
  int initGeneration = 0;

  bool get isClosed => controller.isClosed;

  void add(BeaconScanState state) {
    if (!controller.isClosed) {
      controller.add(state);
    }
  }

  void cancelExpiry() {
    expiryTimer?.cancel();
    expiryTimer = null;
  }

  /// 감지 상태를 [BeaconScanConfig.maxSampleGap] 뒤에 스스로 만료시킨다.
  /// 그 사이에 좋은 샘플이 오면 [armExpiry]가 다시 불려 타이머가 갱신된다.
  void armExpiry(Timer Function(Duration, void Function()) createTimer) {
    cancelExpiry();
    expiryTimer = createTimer(config.maxSampleGap, () {
      expiryTimer = null;
      if (isClosed || !isDetected) return;
      // 침묵으로 인한 만료다 — 스트릭을 처음부터 다시 쌓게 한다. 다음 좋은
      // 샘플 하나가 곧바로 감지로 이어지면 안 된다.
      streakStart = null;
      lastGoodSampleAt = null;
      add(const BeaconOutOfRange());
    });
  }

  /// ranging 구독만 취소한다 — 블루투스가 꺼졌을 때는 상태 변화 구독은
  /// 유지해야 다시 켜졌을 때 재개할 수 있다.
  Future<void> cancelRanging() async {
    final sub = rangingSub;
    rangingSub = null;
    await sub?.cancel();
  }

  /// 이 세션에 속한 구독을 전부 취소하고, 그 취소가 실제로 끝날 때까지
  /// 기다린다 — `stop()`이 반환된 뒤에도 네이티브 스캔이 계속 돌고 있는
  /// 상태를 만들지 않기 위해서다.
  Future<void> teardown() async {
    cancelExpiry();
    final rs = rangingSub;
    rangingSub = null;
    final bs = bluetoothSub;
    bluetoothSub = null;
    await Future.wait<void>([
      if (rs != null) rs.cancel(),
      if (bs != null) bs.cancel(),
    ]);
  }
}

/// [beacon_lib.DchsFlutterBeacon]을 감싸 [BeaconScanner] 계약으로 바꾸는
/// 어댑터. 이 클래스의 핵심은 안정화 판정이다: `dchs_flutter_beacon`의
/// ranging 스트림은 하드웨어 스캔 주기마다 이벤트를 흘려보내는데, 그 이벤트
/// 자체가 시간의 흐름을 담고 있으므로 별도 `Timer`나 `Stream.periodic` 없이
/// "이 이벤트가 도착한 시각"만으로 "임계값 이상이 얼마나 연속됐는가"를
/// 계산한다. 테스트는 [rangingStreamFactory]·[bluetoothStateStreamFactory]
/// ·[createElapsedClock]을 주입해 실제 BLE 하드웨어나 실제 시간 경과 없이
/// 이 로직을 구동한다.
class FlutterBeaconScanner implements BeaconScanner {
  FlutterBeaconScanner({
    Stream<beacon_lib.RangingResult> Function(List<beacon_lib.Region> regions)? rangingStreamFactory,
    Stream<beacon_lib.BluetoothState> Function()? bluetoothStateStreamFactory,
    Future<beacon_lib.BluetoothState> Function()? currentBluetoothState,
    Future<bool> Function()? initializeAndCheckScanning,
    Future<beacon_lib.AuthorizationStatus> Function()? authorizationStatus,
    Future<bool> Function()? requestAuthorization,
    Duration Function() Function()? createElapsedClock,
    Timer Function(Duration, void Function())? createTimer,
  })  : _rangingStreamFactory = rangingStreamFactory ?? beacon_lib.flutterBeacon.ranging,
        _bluetoothStateStreamFactory = bluetoothStateStreamFactory ?? beacon_lib.flutterBeacon.bluetoothStateChanged,
        _currentBluetoothState = currentBluetoothState ?? (() => beacon_lib.flutterBeacon.bluetoothState),
        _initializeAndCheckScanning =
            initializeAndCheckScanning ?? (() => beacon_lib.flutterBeacon.initializeAndCheckScanning),
        _authorizationStatus = authorizationStatus ?? (() => beacon_lib.flutterBeacon.authorizationStatus),
        _requestAuthorization = requestAuthorization ?? (() => beacon_lib.flutterBeacon.requestAuthorization),
        _createElapsedClock = createElapsedClock ?? _defaultElapsedClockFactory,
        _createTimer = createTimer ?? Timer.new;

  /// 매 `watch()`마다 0부터 새로 흐르는 단조 시계를 만든다. `Stopwatch`는
  /// 시스템 시각이 아니라 단조 클럭을 쓰므로 벽시계 점프의 영향을 받지
  /// 않는다.
  static Duration Function() _defaultElapsedClockFactory() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  final Stream<beacon_lib.RangingResult> Function(List<beacon_lib.Region> regions) _rangingStreamFactory;
  final Stream<beacon_lib.BluetoothState> Function() _bluetoothStateStreamFactory;
  final Future<beacon_lib.BluetoothState> Function() _currentBluetoothState;
  final Future<bool> Function() _initializeAndCheckScanning;
  final Future<beacon_lib.AuthorizationStatus> Function() _authorizationStatus;
  final Future<bool> Function() _requestAuthorization;
  final Duration Function() Function() _createElapsedClock;

  /// 감지 만료 타이머를 만드는 팩토리. 테스트가 시간을 직접 흘려보낼 수
  /// 있도록 주입 가능하게 뒀다 — 나머지 시간 판정은 샘플 도착 시각으로
  /// 하지만, "아무 샘플도 오지 않는다"는 사건만은 타이머로만 관측된다.
  final Timer Function(Duration, void Function()) _createTimer;

  _Session? _session;

  /// 이 스캐너 **인스턴스**가 살아있는 동안 딱 한 번만 [_requestAuthorization]을
  /// 부른다(세션이 아니라 인스턴스 단위 — `watch()`를 다시 부르거나 블루투스를
  /// 껐다 켜도 초기화되지 않는다). Android는 `initializeAndCheckScanning()`
  /// 자체가 이미 시스템 팝업을 띄우고, 그 팝업에서 사용자가 거부해도
  /// 플러그인은 이후 상태를 계속 `notDetermined`로 보고한다(Android에는
  /// 별도 `DENIED`가 없다). 이 플래그가 없으면 우리 쪽 `notDetermined` 분기가
  /// "아직 안 물어봤다"고 매번 착각해, 블루투스를 껐다 켜거나 화면을
  /// 재진입할 때마다 사용자는 방금 거부한 팝업을 다시 보게 된다.
  bool _hasRequestedAuthorization = false;

  @override
  Stream<BeaconScanState> watch(BeaconScanConfig config) {
    final previous = _session;
    if (previous != null) {
      unawaited(previous.teardown());
      if (!previous.controller.isClosed) {
        unawaited(previous.controller.close());
      }
    }

    final controller = StreamController<BeaconScanState>();
    final session = _Session(config, controller, _createElapsedClock());
    _session = session;

    controller.onListen = () => unawaited(_start(session));
    controller.onCancel = () {
      // 컨트롤러를 먼저(동기적으로) 닫아 `isClosed`가 즉시 true가 되게
      // 한다 — 그래야 이 시점에 아직 진행 중인 비동기 연속(초기화·권한
      // 확인 등)이 "아직 안 닫혔다"고 착각해 계속 진행하다가 리스너 없는
      // ranging을 시작해 버리는 일이 없다. 실제 구독 취소는 백그라운드로
      // 넘긴다 — `onCancel`은 취소 완료를 기다려줄 필요가 없다(그건
      // `stop()`의 책임이다).
      if (!controller.isClosed) {
        unawaited(controller.close());
      }
      unawaited(session.teardown());
      if (identical(_session, session)) {
        _session = null;
      }
    };

    return controller.stream;
  }

  /// [session]이 여전히 "지금" 활성 세션이고 아직 닫히지 않았는지. 비동기
  /// await 뒤 이어지는 모든 연속(continuation)은 상태를 방출하거나 구독을
  /// 시작하기 전에 반드시 이 확인을 거친다 — `controller.isClosed`만 보면
  /// 새 `watch()`로 이미 교체된, 그러나 아직 닫히지 않은 컨트롤러를 계속
  /// 건드리는 사고를 잡지 못한다.
  bool _isCurrent(_Session session) => identical(_session, session) && !session.isClosed;

  Future<void> _start(_Session session) async {
    // 블루투스 상태 변화는 초기화가 끝나길 기다리는 동안에도 놓치면 안 되므로
    // 가장 먼저 구독한다.
    session.bluetoothSub = _bluetoothStateStreamFactory().listen((state) {
      _handleBluetoothState(state, session);
    });
    if (!_isCurrent(session)) return;

    final beacon_lib.BluetoothState initialState;
    try {
      initialState = await _currentBluetoothState();
    } catch (_) {
      // 초기 상태를 읽지 못해도 변화 스트림은 이미 구독 중이니 계속
      // 진행한다 — 켜져 있다고 낙관적으로 가정한다.
      if (!_isCurrent(session)) return;
      await _initializeAndStartRanging(session);
      return;
    }
    if (!_isCurrent(session)) return;

    if (initialState == beacon_lib.BluetoothState.stateOff) {
      session.bluetoothOff = true;
      session.add(const BeaconBluetoothOff());
      return;
    }

    await _initializeAndStartRanging(session);
  }

  /// 최초 시작과 블루투스 재개가 공유하는 단일 경로. "재개"를 이 함수가
  /// 아닌 다른 지름길로 구현하면(예: 곧장 ranging만 다시 거는 것) 권한이
  /// 그 사이 거부된 경우를 다시 확인하지 않게 된다.
  Future<void> _initializeAndStartRanging(_Session session) async {
    final myGeneration = ++session.initGeneration;
    bool stillValid() => _isCurrent(session) && session.initGeneration == myGeneration;

    bool initialized;
    try {
      initialized = await _initializeAndCheckScanning();
    } catch (_) {
      initialized = false;
    }
    if (!stillValid()) return;

    if (!initialized) {
      beacon_lib.AuthorizationStatus status;
      try {
        status = await _authorizationStatus();
      } catch (_) {
        status = beacon_lib.AuthorizationStatus.denied;
      }
      if (!stillValid()) return;

      // `notDetermined`는 "거부됨"이 아니라 "아직 물어본 적이 없음"이다 —
      // 이 상태를 바로 거부로 단정하면 사용자는 팝업을 본 적도 없는데
      // 영원히 권한 거부 화면에 갇힌다. 반대로 이미 denied/restricted인
      // 상태에서 다시 요청하는 것은 OS가 무시하는 무의미한 호출이고,
      // 인스턴스 생애주기 동안 이미 한 번 요청했다면(Android가
      // notDetermined를 계속 보고하는 경우 포함) 또 요청하지 않는다.
      if (status == beacon_lib.AuthorizationStatus.notDetermined && !_hasRequestedAuthorization) {
        _hasRequestedAuthorization = true;
        try {
          await _requestAuthorization();
        } catch (_) {
          // 요청 자체가 실패해도 아래에서 상태를 다시 읽어 최종 판정한다.
        }
        if (!stillValid()) return;
        try {
          status = await _authorizationStatus();
        } catch (_) {
          status = beacon_lib.AuthorizationStatus.denied;
        }
        if (!stillValid()) return;
      }

      if (!_isAuthorizationGranted(status)) {
        session.add(const BeaconPermissionDenied());
        return;
      }
      // 권한은 있는데 초기화가 실패했다 — 위치 서비스나 블루투스가 꺼져
      // 있는 경우가 대부분이다. 블루투스 변화 스트림이 실제 on/off를
      // 알려줄 것이므로 스캐닝 상태로 두고 재시도하지 않는다.
    }

    session.add(const BeaconScanning());
    _startRanging(session);
  }

  void _handleBluetoothState(beacon_lib.BluetoothState state, _Session session) {
    if (!_isCurrent(session)) return;

    if (state == beacon_lib.BluetoothState.stateOff) {
      if (session.bluetoothOff) return;
      session.bluetoothOff = true;
      // 진행 중이던 초기화 시도가 있다면 세대를 올려 무효화한다 — 블루투스가
      // 꺼진 뒤 뒤늦게 완료돼 ranging을 시작해 버리는 것을 막는다.
      session.initGeneration++;
      unawaited(session.cancelRanging());
      session.streakStart = null;
      session.lastGoodSampleAt = null;
      session.add(const BeaconBluetoothOff());
    } else if (state == beacon_lib.BluetoothState.stateOn) {
      if (!session.bluetoothOff) return;
      session.bluetoothOff = false;
      // 재개는 최초 시작과 완전히 같은 경로(초기화 → 권한 확인 → ranging)를
      // 탄다 — 권한이 그 사이 여전히 거부 상태라면 곧장 Scanning으로
      // 건너뛰지 않고 다시 PermissionDenied로 가야 한다.
      unawaited(_initializeAndStartRanging(session));
    }
    // 그 외(turning on/off, unknown, resetting 등)는 과도기 상태라 무시한다.
  }

  void _startRanging(_Session session) {
    // 방어적 취소: 이 시점에 이미 살아있는 구독이 있다면(정상적인 경로에서는
    // 있을 수 없지만) 절대 두 개를 동시에 살려두지 않는다.
    final stale = session.rangingSub;
    session.rangingSub = null;
    if (stale != null) {
      unawaited(stale.cancel());
    }

    final config = session.config;
    final region = beacon_lib.Region(identifier: config.uuid, proximityUUID: config.uuid);
    session.rangingSub = _rangingStreamFactory([region]).listen((result) {
      _handleRanging(result, session);
    });
  }

  void _handleRanging(beacon_lib.RangingResult result, _Session session) {
    if (!_isCurrent(session)) return;

    final config = session.config;

    // 네이티브 쪽 region 필터를 신뢰하지 않고 우리 쪽에서도 UUID를 다시
    // 확인한다 — 다른 동아리/무관한 비콘을 절대 우리 것으로 취급하지 않기
    // 위해서다. 하이픈 유무와 대소문자는 무시한다.
    final target = _normalizeUuid(config.uuid);
    final matches = result.beacons.where((b) => _normalizeUuid(b.proximityUUID) == target).toList();

    // 같은 UUID의 비콘이 여러 개 잡히면(같은 동아리의 다른 송신기) 가장
    // 가까운(rssi가 가장 큰) 값을 채택한다 — 둘 중 하나가 멀어도(rssi가
    // 낮아도) 다른 하나가 여전히 임계값을 넘으면 스트릭을 끊을 이유가
    // 없다. 이건 의도된 동작이다.
    final int? rawRssi = matches.isEmpty ? null : matches.map((b) => b.rssi).reduce(max);

    // 실제 RSSI는 항상 음수이므로 0 이상은 판독 실패로 본다. 그것만으로는
    // 부족하다 — `dchs_flutter_beacon`의 `Beacon` 생성자가 값을 못 읽으면
    // 정확히 -1을 채워 넣는데(`rssi = rssi ?? -1`, pub.dev 0.6.10
    // `lib/src/beacon.dart`), -1도 진짜 판독값처럼 보이는 음수라 부호만
    // 확인하면 이 결측치가 "아주 가까움"으로 둔갑해 임계값 판정을 그냥
    // 통과해 버린다 — 우리가 지키려는 "실내에 있다"는 보장 자체가
    // 무너진다. 그래서 이 플러그인의 결측치 표식값인 -1도 명시적으로
    // 함께 걸러낸다.
    final bool isValidReading = rawRssi != null && rawRssi < 0 && rawRssi != -1;
    final bool isGood = isValidReading && rawRssi >= config.rssiThreshold;

    final now = session.elapsed();

    if (isGood) {
      final lastGoodSampleAt = session.lastGoodSampleAt;
      if (session.streakStart == null ||
          lastGoodSampleAt == null ||
          (now - lastGoodSampleAt) > config.maxSampleGap) {
        // 스트릭이 없었거나, 이전 좋은 샘플과 너무 오래 떨어져 있다(=사실상
        // 한동안 침묵했다). 지금 이 샘플부터 새로 스트릭을 센다 — 침묵
        // 뒤에 온 프레임 하나가 안정화를 통과시키면 안 된다.
        session.streakStart = now;
      }
      session.lastGoodSampleAt = now;

      final elapsed = now - session.streakStart!;
      if (elapsed >= Duration(seconds: config.stabilizationSeconds)) {
        session.isDetected = true;
        session.add(BeaconDetected(rawRssi));
        // 좋은 샘플이 올 때마다 만료 시계를 다시 감는다. 샘플이 끊기면
        // 이 타이머가 스스로 OutOfRange로 되돌린다.
        session.armExpiry(_createTimer);
      } else {
        session.add(const BeaconScanning());
      }
    } else {
      // 연속성이 깨졌다 — 스트릭을 처음부터 다시 센다. 이유(임계값 미달·
      // 빈 프레임·다른 UUID·유효하지 않은 rssi)를 가리지 않고 전부 여기로
      // 모인다.
      session.streakStart = null;
      session.lastGoodSampleAt = null;
      // 나쁜 샘플이 이미 판정을 내렸으니 만료 타이머는 필요 없다.
      session.cancelExpiry();
      if (session.isDetected) {
        // OutOfRange는 안정적이어야 한다 — `isDetected`를 여기서 false로
        // 되돌리면 바로 다음 나쁜 프레임이 Scanning으로 깜빡인다. 새
        // 스트릭이 다시 안정화 시간을 채워 BeaconDetected가 나올 때만
        // 갱신된다(위 `isGood` 분기).
        session.add(const BeaconOutOfRange());
      } else {
        session.add(const BeaconScanning());
      }
    }
  }

  @override
  Future<void> stop() async {
    final session = _session;
    _session = null;
    if (session == null) return;
    await session.teardown();
    if (!session.controller.isClosed) {
      await session.controller.close();
    }
  }
}

final beaconScannerProvider = Provider<BeaconScanner>((ref) {
  return FlutterBeaconScanner();
});
