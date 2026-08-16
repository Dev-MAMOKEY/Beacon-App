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

/// 테스트가 직접 흐르게 하는 가짜 경과 시계. `FlutterBeaconScanner`는
/// `watch()`마다 새 단조 시계(실기기에서는 `Stopwatch`)를 요청하므로, 이
/// 클래스도 "0부터 시작하는 경과 시간"만 제공한다 — 벽시계 개념 자체가
/// 없다.
class _FakeElapsedClock {
  Duration _elapsed = Duration.zero;

  Duration call() => _elapsed;

  void advance(Duration duration) => _elapsed += duration;
}

/// [FlutterBeaconScanner]가 만드는 만료 타이머를 가로채, 테스트가 원하는
/// 순간에 직접 발화시킬 수 있게 한다. "아무 샘플도 오지 않는다"는 사건은
/// 스트림으로 표현할 수 없어 타이머로만 관측되므로, 경과 시계만으로는
/// 이 경로를 구동할 수 없다.
class _FakeTimer implements Timer {
  _FakeTimer(this.duration, this.callback);

  final Duration duration;
  final void Function() callback;
  bool cancelled = false;

  void fire() {
    if (cancelled) return;
    callback();
  }

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
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
    Future<bool> Function()? initializeOverride,
    this.authorization = beacon_lib.AuthorizationStatus.allowed,
    this.authorizationAfterRequest,
    this.requestAuthorizationGate,
    Completer<void>? rangingCancelGate,
  }) {
    scanner = FlutterBeaconScanner(
      rangingStreamFactory: (regions) {
        lastRegions = regions;
        rangingStarts++;
        final controller = StreamController<beacon_lib.RangingResult>(
          onCancel: () async {
            rangingCancelCount++;
            if (rangingCancelGate != null) {
              await rangingCancelGate.future;
            }
          },
        );
        rangingControllers.add(controller);
        return controller.stream;
      },
      bluetoothStateStreamFactory: () => bluetoothController.stream,
      currentBluetoothState: () async => initialBluetoothState,
      initializeAndCheckScanning: () {
        initializeCalls++;
        return (initializeOverride ?? (() async => initializeSucceeds))();
      },
      authorizationStatus: () async => authorization,
      requestAuthorization: () async {
        requestAuthorizationCallCount++;
        final gate = requestAuthorizationGate;
        if (gate != null) {
          await gate.future;
        }
        if (authorizationAfterRequest != null) {
          authorization = authorizationAfterRequest!;
        }
        return true;
      },
      createElapsedClock: _makeElapsedClock,
      createTimer: (duration, callback) {
        final timer = _FakeTimer(duration, callback);
        timers.add(timer);
        return timer;
      },
    );
  }

  final Completer<void>? requestAuthorizationGate;

  /// 현재 권한 상태. `requestAuthorization`이 불리면 [authorizationAfterRequest]로
  /// 바뀐다 — "요청 후 사용자가 승인/거부했다"를 흉내낸다.
  beacon_lib.AuthorizationStatus authorization;
  final beacon_lib.AuthorizationStatus? authorizationAfterRequest;

  late final FlutterBeaconScanner scanner;
  // broadcast여야 한다 — 한 하니스가 여러 번 watch()되면(예: region 캐싱
  // 회귀 테스트) 매번 새로 구독이 걸리는데, 단일 구독 스트림은 한 번
  // 취소된 뒤 다시 리슨하면 "Stream has already been listened to"로 죽는다.
  final StreamController<beacon_lib.BluetoothState> bluetoothController =
      StreamController<beacon_lib.BluetoothState>.broadcast();
  final List<StreamController<beacon_lib.RangingResult>> rangingControllers = [];
  final List<_FakeElapsedClock> _elapsedClocks = [];
  final List<_FakeTimer> timers = [];
  List<beacon_lib.Region>? lastRegions;
  int rangingStarts = 0;
  int rangingCancelCount = 0;
  int requestAuthorizationCallCount = 0;
  int initializeCalls = 0;
  final List<BeaconScanState> states = [];

  StreamController<beacon_lib.RangingResult> get currentRanging => rangingControllers.last;

  /// 매 `watch()`마다 새 경과 시계를 만든다 — 실제 구현이 매번 새
  /// `Stopwatch`를 요청하는 것과 동일하다. [clock]은 항상 "가장 최근에
  /// 만들어진(=지금 활성 세션의)" 시계를 가리킨다.
  Duration Function() _makeElapsedClock() {
    final c = _FakeElapsedClock();
    _elapsedClocks.add(c);
    return c.call;
  }

  _FakeElapsedClock get clock => _elapsedClocks.last;

  /// 아직 취소되지 않은 만료 타이머. 감지 상태에서만 존재한다.
  _FakeTimer? get liveExpiryTimer =>
      timers.where((t) => t.isActive).isEmpty ? null : timers.lastWhere((t) => t.isActive);

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

  /// 좋은 신호가 [duration] 동안 끊기지 않고 유지된 것처럼 1초 간격으로
  /// 프레임을 흘려보낸다 — 실제 ranging이 대략 1초에 한 번 이벤트를
  /// 내보내는 주기를 흉내낸다(`BeaconScanConfig.maxSampleGap` 기본값
  /// 2초보다 촘촘해야 "침묵"으로 오인되지 않는다). 스트릭을 시작할 첫
  /// 프레임은 호출 전에 직접 보내야 한다 — 이 메서드는 그 이후
  /// [duration]만큼만 채운다.
  Future<void> holdGoodFor(Duration duration, {int rssi = -60, String uuid = _uuid}) async {
    var remaining = duration;
    const step = Duration(seconds: 1);
    while (remaining > Duration.zero) {
      final advance = remaining < step ? remaining : step;
      clock.advance(advance);
      remaining -= advance;
      emitGood(rssi, uuid: uuid);
      await settle();
    }
  }
}

void main() {
  final config = BeaconScanConfig(uuid: _uuid, rssiThreshold: -70, stabilizationSeconds: 3);

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
    await h.holdGoodFor(const Duration(seconds: 3), rssi: -55); // t=1,2,3 — 연속 3초 이상 임계값 이상

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
    // 나온다는 것까지 1초 간격으로 확인한다.
    await h.holdGoodFor(const Duration(seconds: 3)); // t=4,5,6 — 새 스트릭(t=3) 기준 연속 3초

    expect(h.states.last, isA<BeaconDetected>());
  });

  test('Detected 이후 신호가 끊기면 OutOfRange로 전이한다', () async {
    // 잡아야 할 잘못된 구현: Detected를 한 번 방출하고 이후 상태를 그대로
    // 고정한다.
    final h = _Harness();
    await h.start(config);

    h.emitGood(-60); // t=0
    await h.settle();
    await h.holdGoodFor(const Duration(seconds: 3)); // t=1,2,3 -> Detected
    expect(h.states.last, isA<BeaconDetected>());

    h.emitBad(); // 신호가 끊김
    await h.settle();

    expect(h.states.last, isA<BeaconOutOfRange>());
  });

  test('OutOfRange는 안정적이다 — 신호 부재가 계속되는 동안 Scanning으로 돌아가지 않는다', () async {
    // 잡아야 할 잘못된 구현(이번 라운드 이전 동작): Detected 이후 첫 나쁜
    // 프레임에서 OutOfRange를 방출한 뒤 내부 플래그를 곧장 되돌려, 바로
    // 다음 나쁜 프레임에서 Scanning으로 되돌아간다.
    final h = _Harness();
    await h.start(config);

    h.emitGood(-60); // t=0
    await h.settle();
    await h.holdGoodFor(const Duration(seconds: 3)); // -> Detected
    expect(h.states.last, isA<BeaconDetected>());

    h.emitBad();
    await h.settle();
    expect(h.states.last, isA<BeaconOutOfRange>());

    h.emitBad(); // 두 번째 연속 나쁜 프레임
    await h.settle();
    expect(
      h.states.last,
      isA<BeaconOutOfRange>(),
      reason: '신호 부재가 계속되는 동안은 계속 OutOfRange여야 한다 — Scanning으로 깜빡이면 안 된다',
    );

    h.emitBad(); // 세 번째
    await h.settle();
    expect(h.states.last, isA<BeaconOutOfRange>());
  });

  test('OutOfRange 이후 재획득해도 스트릭이 리셋돼 있어 곧장 Detected가 나오지 않는다', () async {
    // 잡아야 할 잘못된 구현: OutOfRange를 방출하면서도 스트릭 시작 시각을
    // 지우지 않는다 — 그러면 재획득 시 옛 스트릭의 잔여 경과 시간이 남아
    // 있어, 좋은 프레임 단 하나로도 곧장 Detected가 나와 버린다.
    final h = _Harness();
    await h.start(config);

    h.emitGood(-60); // t=0
    await h.settle();
    await h.holdGoodFor(const Duration(seconds: 3)); // -> Detected
    expect(h.states.last, isA<BeaconDetected>());

    h.emitEmpty(); // 신호 소실 -> OutOfRange
    await h.settle();
    expect(h.states.last, isA<BeaconOutOfRange>());

    h.clock.advance(const Duration(seconds: 1)); // 아직 3초 미만
    h.emitGood(-60); // 재획득된 지 1초
    await h.settle();

    expect(
      h.states.last,
      isA<BeaconScanning>(),
      reason: '재획득 직후 단 1초 만에 Detected가 나오면 스트릭이 리셋되지 않은 것이다',
    );
  });

  test('스트릭 리셋은 빈 프레임과 다른 UUID 프레임에도 똑같이 적용된다', () async {
    // 잡아야 할 잘못된 구현: 숫자로 된 임계값 미달 rssi에서만 스트릭을
    // 리셋하고, 빈 프레임이나 다른 UUID만 잡힌 프레임(둘 다 rssi 자체가
    // 없다)에서는 리셋을 건너뛴다. 프레임 간격을 전부 1초로 좁게 유지하는
    // 이유는, 2초를 넘는 간격은 `maxSampleGap`(침묵 감지)이 별도로 스트릭을
    // 리셋시켜 이 테스트가 원래 노리는 "리셋 사유별 분기 누락"을 가려버리기
    // 때문이다 — 이 테스트는 오직 명시적인 나쁜 프레임 리셋 경로만 본다.
    final h = _Harness();
    await h.start(config);

    h.emitGood(-60); // t=0, 스트릭 시작
    await h.settle();
    h.clock.advance(const Duration(seconds: 1));
    h.emitEmpty(); // t=1, 빈 프레임 -> 리셋되어야 함
    await h.settle();
    h.clock.advance(const Duration(seconds: 1));
    h.emitGood(-60); // t=2, 리셋됐다면 방금 시작한 스트릭(0초)
    await h.settle();
    h.clock.advance(const Duration(seconds: 1));
    h.emitGood(-60); // t=3, 리셋됐다면 재획득 후 1초뿐
    await h.settle();

    expect(
      h.states.last,
      isA<BeaconScanning>(),
      reason: '빈 프레임도 스트릭을 리셋해야 한다 — 리셋되지 않으면 t=0부터 누적 3초로 착각해 Detected가 나온다',
    );

    h.clock.advance(const Duration(seconds: 1));
    h.emitGood(-60, uuid: _otherUuid); // t=4, 다른 UUID -> 리셋되어야 함
    await h.settle();
    h.clock.advance(const Duration(seconds: 1));
    h.emitGood(-60); // t=5, 리셋됐다면 방금 시작한 스트릭(0초)
    await h.settle();
    h.clock.advance(const Duration(seconds: 1));
    h.emitGood(-60); // t=6, 리셋됐다면 재획득 후 1초뿐
    await h.settle();

    expect(
      h.states.last,
      isA<BeaconScanning>(),
      reason: '다른 UUID만 잡힌 프레임도 스트릭을 리셋해야 한다',
    );
  });

  test('한동안 침묵하다 온 단 하나의 좋은 프레임은 안정화를 통과시키지 못한다', () async {
    // 잡아야 할 잘못된 구현(이번 라운드 이전 동작): 이전 좋은 샘플과의
    // 간격을 보지 않고 스트릭 시작 시각만으로 경과 시간을 계산한다 —
    // 그러면 10분 동안 아무 이벤트도 없다가 온 프레임 하나가 "스트릭이
    // 10분 지속됐다"고 착각한다.
    final h = _Harness();
    await h.start(config);

    h.emitGood(-60); // t=0, 스트릭 시작
    await h.settle();
    h.clock.advance(const Duration(minutes: 10)); // 완전한 침묵(이벤트 자체가 없음)
    h.emitGood(-60); // t=600s, 첫 샘플 이후 10분간 아무 프레임도 없었다
    await h.settle();

    expect(
      h.states.last,
      isA<BeaconScanning>(),
      reason: '침묵 뒤에 온 프레임 하나로 안정화 시간이 채워진 것처럼 보이면 안 된다',
    );
  });

  test('rssi가 0 이상(유효하지 않은 판독값)이면 나쁜 프레임으로 취급한다', () async {
    // 잡아야 할 잘못된 구현: rssi 부호를 확인하지 않아 -1(플러그인이 값을
    // 못 읽었을 때 채우는 기본값) 같은 값도 임계값(-70) 이상이라는
    // 이유만으로 좋은 프레임으로 인정한다.
    final h = _Harness();
    await h.start(config);

    h.emitGood(-1); // t=0, 유효하지 않은 판독값(신호 없음의 기본값)
    await h.settle();
    await h.holdGoodFor(const Duration(seconds: 3), rssi: -1);

    expect(
      h.states,
      isNot(contains(isA<BeaconDetected>())),
      reason: '유효하지 않은 rssi가 아무리 오래 지속돼도 Detected로 이어지면 안 된다',
    );
  });

  test('rssi가 임계값과 정확히 같으면 좋은 프레임으로 인정한다(경계값)', () async {
    // 잡아야 할 잘못된 구현: `rssi >= threshold`가 아니라 `rssi > threshold`를
    // 써서, 정확히 임계값과 같은 값을 나쁜 프레임으로 잘못 취급한다.
    final h = _Harness();
    await h.start(config); // rssiThreshold: -70

    h.emitGood(-70); // t=0, 정확히 임계값
    await h.settle();
    await h.holdGoodFor(const Duration(seconds: 3), rssi: -70);

    expect(h.states.last, isA<BeaconDetected>());
  });

  group('감지 만료 — 샘플이 끊기면 스스로 범위 이탈로 되돌린다', () {
    // 이 경로가 없으면 `maxSampleGap`은 **다음 샘플이 도착할 때만** 평가된다.
    // 스트림이 조용해지면(앱이 백그라운드로 가면 ranging이 정확히 그렇게
    // 멈춘다) 감지 상태가 무기한 남고, 방을 나갔다 돌아와도 출석이 통과한다.
    // `checkIn`은 근접 증거를 담지 않아 서버가 재검증할 수 없으므로 이
    // 만료가 보증의 일부다(리뷰 Critical).

    test('감지 후 아무 샘플도 오지 않으면 maxSampleGap 뒤에 OutOfRange가 된다', () async {
      final h = _Harness();
      await h.start(config);

      h.emitGood(-60);
      await h.settle();
      await h.holdGoodFor(const Duration(seconds: 3));
      expect(h.states.last, isA<BeaconDetected>());

      // 스트림이 조용해진다 — 샘플을 하나도 넣지 않는다.
      final timer = h.liveExpiryTimer;
      expect(timer, isNotNull, reason: '감지 상태에서는 만료 시계가 무장돼 있어야 한다');
      expect(timer!.duration, config.maxSampleGap);

      timer.fire();
      await h.settle();

      expect(h.states.last, isA<BeaconOutOfRange>());
    });

    test('만료 뒤 좋은 샘플 하나가 곧바로 감지로 이어지지 않는다', () async {
      // 잡아야 할 잘못된 구현: 만료 시 상태만 바꾸고 스트릭을 남겨 둔다 —
      // 그러면 침묵 뒤 첫 프레임이 안정화를 건너뛰고 통과한다.
      final h = _Harness();
      await h.start(config);

      h.emitGood(-60);
      await h.settle();
      await h.holdGoodFor(const Duration(seconds: 3));
      h.liveExpiryTimer!.fire();
      await h.settle();
      expect(h.states.last, isA<BeaconOutOfRange>());

      // 만료가 일어난 시점 = 마지막 좋은 샘플로부터 정확히 maxSampleGap.
      // 여기서 시계를 더 크게 밀면 안 된다 — 기존 gap 검사(`> maxSampleGap`)가
      // 어차피 스트릭을 리셋해버려, 만료 경로가 스트릭을 지우는지 아닌지를
      // 테스트가 구별하지 못한다(처음에 30초를 밀었다가 이 변이가 살아남는
      // 것을 확인했다).
      h.clock.advance(config.maxSampleGap);
      h.emitGood(-60);
      await h.settle();

      expect(
        h.states.last,
        isA<BeaconScanning>(),
        reason: '침묵 뒤 첫 프레임은 새 스트릭의 시작일 뿐, 곧바로 감지가 되면 안 된다',
      );
    });

    test('좋은 샘플이 계속 오면 만료 시계가 갱신돼 감지가 유지된다', () async {
      // 잡아야 할 잘못된 구현: 타이머를 한 번만 무장하고 갱신하지 않는다 —
      // 신호가 멀쩡히 오는데도 maxSampleGap 뒤에 범위 이탈로 떨어진다.
      final h = _Harness();
      await h.start(config);

      h.emitGood(-60);
      await h.settle();
      await h.holdGoodFor(const Duration(seconds: 3));
      final first = h.liveExpiryTimer;

      await h.holdGoodFor(const Duration(seconds: 3));
      final second = h.liveExpiryTimer;

      expect(first!.isActive, isFalse, reason: '앞선 시계는 취소돼야 한다');
      expect(second, isNot(same(first)), reason: '샘플마다 시계를 다시 감는다');
      expect(h.states.last, isA<BeaconDetected>());
    });

    test('나쁜 샘플로 범위를 벗어나면 만료 시계를 남기지 않는다', () async {
      // 잡아야 할 잘못된 구현: 취소를 빠뜨려, 이미 판정이 끝난 뒤에 옛 타이머가
      // 뒤늦게 발화해 상태를 한 번 더 뒤집는다.
      final h = _Harness();
      await h.start(config);

      h.emitGood(-60);
      await h.settle();
      await h.holdGoodFor(const Duration(seconds: 3));
      expect(h.liveExpiryTimer, isNotNull);

      h.emitGood(-90); // 임계값 미달
      await h.settle();

      expect(h.states.last, isA<BeaconOutOfRange>());
      expect(h.liveExpiryTimer, isNull, reason: '판정이 끝났으면 시계를 남기지 않는다');
    });

    test('stop()은 만료 시계도 함께 취소한다', () async {
      // 잡아야 할 잘못된 구현: teardown에서 타이머를 놔둬, 스캔을 멈춘 뒤에도
      // 닫힌 컨트롤러에 상태를 밀어 넣으려 한다.
      final h = _Harness();
      await h.start(config);

      h.emitGood(-60);
      await h.settle();
      await h.holdGoodFor(const Duration(seconds: 3));
      final timer = h.liveExpiryTimer;
      expect(timer, isNotNull);

      await h.scanner.stop();
      await h.settle();

      expect(timer!.isActive, isFalse);
    });
  });

  test('stabilizationSeconds 설정값을 실제로 사용한다(하드코딩된 3초가 아니다)', () async {
    // 잡아야 할 잘못된 구현: config.stabilizationSeconds를 무시하고 3초를
    // 하드코딩한다.
    final customConfig = BeaconScanConfig(uuid: _uuid, rssiThreshold: -70, stabilizationSeconds: 5);
    final h = _Harness();
    await h.start(customConfig);

    h.emitGood(-60); // t=0
    await h.settle();
    await h.holdGoodFor(const Duration(seconds: 3)); // t=1,2,3 — 하드코딩된 3초라면 여기서 이미 통과

    expect(
      h.states.last,
      isA<BeaconScanning>(),
      reason: '설정은 5초인데 3초 만에 Detected가 나오면 하드코딩된 것이다',
    );

    await h.holdGoodFor(const Duration(seconds: 2)); // t=4,5 — 총 5초

    expect(h.states.last, isA<BeaconDetected>());
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
    await h.holdGoodFor(const Duration(seconds: 3));

    expect(h.states.last, isA<BeaconDetected>());
  });

  test('권한이 거부된 상태에서 블루투스를 껐다 켜도 재확인 없이 곧장 스캐닝하지 않는다', () async {
    // 잡아야 할 잘못된 구현: 재개(on) 분기가 곧장 _startRanging()을 불러,
    // 그 사이 권한이 여전히 거부 상태인지 다시 확인하지 않는다.
    final h = _Harness(
      initializeSucceeds: false,
      authorization: beacon_lib.AuthorizationStatus.denied,
    );
    await h.start(config);
    expect(h.states.last, isA<BeaconPermissionDenied>());
    expect(h.rangingStarts, 0);

    h.bluetoothController.add(beacon_lib.BluetoothState.stateOff);
    await h.settle();
    expect(h.states.last, isA<BeaconBluetoothOff>());

    h.bluetoothController.add(beacon_lib.BluetoothState.stateOn);
    await h.settle();

    expect(
      h.states.last,
      isA<BeaconPermissionDenied>(),
      reason: '권한이 여전히 거부된 상태이므로 재개해도 다시 거부여야 한다 — 곧장 Scanning으로 건너뛰면 안 된다',
    );
    expect(h.rangingStarts, 0, reason: '권한 없이 ranging을 시작하면 안 된다');
  });

  test('블루투스가 꺼지면 초기화 경쟁으로 생긴 옛 시도는 ranging을 시작하지 못한다', () async {
    // 잡아야 할 잘못된 구현: 초기화 시도에 세대를 매기지 않아, 블루투스가
    // 꺼졌다 다시 켜지는 사이 뒤늦게 끝난 옛 초기화 시도도 그대로
    // ranging을 시작해 버린다 — off 핸들러는 "그 순간" 추적 중이던 구독
    // 하나만 취소하므로, 이렇게 생긴 구독은 아무도 취소하지 않는다.
    final gate = Completer<bool>();
    final h = _Harness(initializeOverride: () => gate.future);

    await h.start(config); // gen=1: initializeAndCheckScanning()에서 블록
    expect(h.initializeCalls, 1);

    h.bluetoothController.add(beacon_lib.BluetoothState.stateOff);
    await h.settle();
    expect(h.states.last, isA<BeaconBluetoothOff>());

    h.bluetoothController.add(beacon_lib.BluetoothState.stateOn);
    await h.settle();
    expect(h.initializeCalls, 2, reason: '재개는 초기화를 처음부터 다시 시도해야 한다');

    gate.complete(true); // gen=1(낡음)과 gen=2(현재) 둘 다 풀려난다

    await h.settle();

    expect(h.rangingStarts, 1, reason: '세대가 낡은 시도는 ranging을 시작하면 안 된다');
    expect(h.rangingCancelCount, 0, reason: '살아있는 구독이 하나뿐이면 취소도 없어야 한다');
    expect(h.states.last, isA<BeaconScanning>());
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

  test('UUID 비교는 하이픈 유무와 대소문자를 모두 무시한다', () async {
    // 잡아야 할 잘못된 구현: 대소문자만 무시하고 하이픈은 그대로 비교해,
    // 서버·기기가 하이픈 표기를 다르게 내려주면 영원히 Scanning에 머문다.
    const differentFormatUuid = 'e2c56db5dffb48d2b060d0f5a71096e0'; // 소문자 + 하이픈 없음
    final h = _Harness();
    await h.start(config); // config.uuid = _uuid (하이픈 있음, 대문자)

    h.emitGood(-60, uuid: differentFormatUuid); // t=0
    await h.settle();
    await h.holdGoodFor(const Duration(seconds: 3), rssi: -60, uuid: differentFormatUuid);

    expect(
      h.states.last,
      isA<BeaconDetected>(),
      reason: '같은 비콘인데 하이픈/대소문자 표기만 다르면 매칭에 실패하면 안 된다',
    );
  });

  test('빈 ranging 결과(주변에 비콘 없음)는 나쁜 프레임으로 취급된다', () async {
    final h = _Harness();
    await h.start(config);

    h.emitGood(-60); // t=0
    await h.settle();
    await h.holdGoodFor(const Duration(seconds: 3));
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

  test('watch()를 다시 부르면 region이 새 config의 UUID를 쓴다(첫 UUID를 캐싱하지 않는다)', () async {
    // 잡아야 할 잘못된 구현: 최초 region을 스캐너 인스턴스에 캐싱해 두
    // 번째 watch()에서도 옛 UUID를 계속 쓴다.
    final h = _Harness();
    await h.start(config); // uuid = _uuid
    expect(h.lastRegions!.single.proximityUUID, _uuid);

    final config2 = BeaconScanConfig(uuid: _otherUuid, rssiThreshold: -70, stabilizationSeconds: 3);
    await h.start(config2); // 같은 스캐너 인스턴스에 두 번째 watch()

    expect(h.lastRegions!.single.proximityUUID, _otherUuid);
  });

  // 홈 탭이 숨겨지면 스캔을 멈추고, 다시 보이면 `watch()`를 다시 부른다
  // (`home_screen.dart`). 그때 "탭을 잠깐 떠났다 돌아왔다"는 이유로 이미
  // 채워둔 안정화 시간이 그대로 인정되면, 실제로는 방을 나갔다 들어온
  // 사용자가 곧바로 출석 대상이 된다 — 재구독은 반드시 스트릭을 0에서
  // 다시 세야 한다.
  test('stop() 후 watch()를 다시 부르면 안정화 스트릭이 0에서 다시 쌓인다', () async {
    // 잡아야 할 잘못된 구현: 스트릭 상태(streakStart/lastGoodSampleAt)나
    // 경과 시계를 세션이 아니라 스캐너 인스턴스에 두어, 재구독 후 첫
    // 좋은 프레임 하나만으로 곧장 Detected가 나온다.
    final h = _Harness();
    await h.start(config);
    h.emitGood(-60);
    await h.settle();
    await h.holdGoodFor(const Duration(seconds: 3));
    expect(h.states.last, isA<BeaconDetected>());

    await h.scanner.stop();

    final resumed = <BeaconScanState>[];
    h.scanner.watch(config).listen(resumed.add);
    await pumpEventQueue();

    // 재개 직후의 좋은 프레임 하나 — 안정화 시간을 다시 채우기 전이다.
    h.emitGood(-60);
    await h.settle();

    expect(
      resumed.whereType<BeaconDetected>(),
      isEmpty,
      reason: '재구독은 새 세션이므로 스트릭도 시계도 0에서 시작해야 한다',
    );

    // 그리고 안정화 시간을 다시 채우면 그때는 Detected가 나온다 —
    // "영원히 안 나온다"가 아니라 "처음부터 다시 센다"임을 함께 고정한다.
    await h.holdGoodFor(const Duration(seconds: 3));
    expect(resumed.last, isA<BeaconDetected>());
  });

  test('stop()은 실제 구독 취소가 끝날 때까지 기다린다', () async {
    // 잡아야 할 잘못된 구현: cancel() Future들을 기다리지 않고 stop()이
    // 먼저 반환돼 버린다.
    final rangingCancelGate = Completer<void>();
    final h = _Harness(rangingCancelGate: rangingCancelGate);
    await h.start(config);
    h.emitGood(-60);
    await h.settle();
    await h.holdGoodFor(const Duration(seconds: 3));
    expect(h.states.last, isA<BeaconDetected>());

    var stopCompleted = false;
    unawaited(h.scanner.stop().then((_) => stopCompleted = true));
    await pumpEventQueue();

    expect(
      stopCompleted,
      isFalse,
      reason: 'ranging 구독의 cancel()이 아직 안 끝났으니 stop()도 끝나면 안 된다',
    );

    rangingCancelGate.complete();
    await pumpEventQueue();

    expect(stopCompleted, isTrue);
  });

  group('권한 요청 — notDetermined을 거부로 단정하지 않는다', () {
    // notDetermined("아직 물어본 적 없음")를 denied로 잘못 취급하면, 사용자는
    // 팝업을 본 적도 없는데 영원히 권한 거부 화면에 갇힌다. 아래 항목들은 이
    // 판정 경로 전체를 고정한다.

    test('notDetermined이면 요청을 정확히 한 번 호출하고 상태를 다시 읽는다', () async {
      // 잡아야 할 잘못된 구현: 요청 없이 바로 PermissionDenied를 방출한다(수정 전 동작).
      final h = _Harness(
        initializeSucceeds: false,
        authorization: beacon_lib.AuthorizationStatus.notDetermined,
        authorizationAfterRequest: beacon_lib.AuthorizationStatus.notDetermined,
      );
      await h.start(config);

      expect(h.requestAuthorizationCallCount, 1);
      // 재요청 후에도 여전히 notDetermined(=거부로 볼 수밖에 없음)면
      // PermissionDenied로 마무리되어야 "다시 읽었다"는 것이 증명된다.
      expect(h.states.last, isA<BeaconPermissionDenied>());
    });

    test('notDetermined에서 요청 후 승인되면 BeaconScanning으로 전이하고 ranging을 시작한다', () async {
      // 잡아야 할 잘못된 구현: 방금 승인됐는데도 PermissionDenied를 방출한다.
      final h = _Harness(
        initializeSucceeds: false,
        authorization: beacon_lib.AuthorizationStatus.notDetermined,
        authorizationAfterRequest: beacon_lib.AuthorizationStatus.allowed,
      );
      await h.start(config);

      expect(h.states.last, isA<BeaconScanning>());
      expect(h.rangingStarts, 1);
    });

    test('notDetermined에서 요청 후에도 거부면 BeaconPermissionDenied를 방출한다', () async {
      // 잡아야 할 잘못된 구현: 요청 후 상태를 다시 확인하지 않고 무조건 스캔을 진행한다.
      final h = _Harness(
        initializeSucceeds: false,
        authorization: beacon_lib.AuthorizationStatus.notDetermined,
        authorizationAfterRequest: beacon_lib.AuthorizationStatus.denied,
      );
      await h.start(config);

      expect(h.states.last, isA<BeaconPermissionDenied>());
      expect(h.rangingStarts, 0, reason: '권한이 없는 채로 ranging을 시작하면 안 된다');
    });

    test('이미 denied면 즉시 PermissionDenied를 방출하고 요청은 부르지 않는다', () async {
      // 잡아야 할 잘못된 구현: 상태와 무관하게 스캔을 시작할 때마다 요청을 부른다.
      final h = _Harness(
        initializeSucceeds: false,
        authorization: beacon_lib.AuthorizationStatus.denied,
      );
      await h.start(config);

      expect(h.states.last, isA<BeaconPermissionDenied>());
      expect(
        h.requestAuthorizationCallCount,
        0,
        reason: '이미 거부된 상태에서 다시 요청하는 것은 OS가 무시하는 무의미한 호출이다',
      );
    });

    test('이미 승인된 상태면 요청을 부르지 않는다', () async {
      // 잡아야 할 잘못된 구현: 정상 경로에서도 불필요하게 요청을 부른다.
      final h = _Harness(
        initializeSucceeds: false,
        authorization: beacon_lib.AuthorizationStatus.allowed,
      );
      await h.start(config);

      expect(h.requestAuthorizationCallCount, 0);
      expect(h.states.last, isA<BeaconScanning>());
    });

    test('권한 요청은 인스턴스 생애주기 동안 최대 한 번만 이뤄진다(재개해도 다시 묻지 않는다)', () async {
      // 잡아야 할 잘못된 구현: 세션이 아니라 매번 "지금 상태가 notDetermined인가"
      // 만 보고 요청 여부를 판단해, Android처럼 거부 후에도 계속
      // notDetermined를 보고하는 환경에서 재개할 때마다 또 요청한다.
      final h = _Harness(
        initializeSucceeds: false,
        authorization: beacon_lib.AuthorizationStatus.notDetermined,
        authorizationAfterRequest: beacon_lib.AuthorizationStatus.notDetermined,
      );
      await h.start(config);
      expect(h.requestAuthorizationCallCount, 1);
      expect(h.states.last, isA<BeaconPermissionDenied>());

      // 블루투스를 껐다 켜서 재개(재시도)를 유도한다.
      h.bluetoothController.add(beacon_lib.BluetoothState.stateOff);
      await h.settle();
      h.bluetoothController.add(beacon_lib.BluetoothState.stateOn);
      await h.settle();

      expect(
        h.requestAuthorizationCallCount,
        1,
        reason: '이미 한 번 요청했으니 재개해도 또 요청하면 안 된다 — Android는 거부 후에도 notDetermined를 계속 보고한다',
      );
      expect(h.states.last, isA<BeaconPermissionDenied>());
    });

    test('요청을 실제로 기다린 뒤에 상태를 다시 읽는다(경쟁 조건 없음)', () async {
      // 잡아야 할 잘못된 구현: requestAuthorization()을 기다리지 않고
      // (fire-and-forget) 곧장 상태를 다시 읽어버려, 사용자가 아직
      // 응답하지 않았는데도 이미 결론을 내 버린다.
      final gate = Completer<void>();
      final h = _Harness(
        initializeSucceeds: false,
        authorization: beacon_lib.AuthorizationStatus.notDetermined,
        authorizationAfterRequest: beacon_lib.AuthorizationStatus.allowed,
        requestAuthorizationGate: gate,
      );

      h.scanner.watch(config).listen(h.states.add);
      await pumpEventQueue();

      expect(
        h.states,
        isNot(anyOf(contains(isA<BeaconPermissionDenied>()), contains(isA<BeaconScanning>()))),
        reason: '아직 사용자가 응답하지 않았다(게이트가 안 풀렸다) — 요청을 기다리지 않았다면 '
            '이미 상태를 재확인해 결론을 내렸을 것이다',
      );

      gate.complete();
      await pumpEventQueue();

      expect(h.states.last, isA<BeaconScanning>());
    });
  });
}
