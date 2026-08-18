/// BLE 비콘 감지 레이어의 순수 계약. 실제 BLE 하드웨어(dchs_flutter_beacon)나
/// 테스트용 스크립트는 전부 [BeaconScanner]를 구현해 이 상태들만 방출한다 —
/// 화면은 어떤 구현인지 몰라도 된다.
sealed class BeaconScanState {
  const BeaconScanState();
}

/// 스캔을 시작하기 전의 기본 상태. [BeaconScanner] 구현체가 직접 방출하지는
/// 않는다 — 화면이 `watch()`를 부르기 전 자신의 초기값으로 쓴다.
class BeaconIdle extends BeaconScanState {
  const BeaconIdle();

  @override
  bool operator ==(Object other) => other is BeaconIdle;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'BeaconIdle';
}

/// 블루투스 자체가 꺼져 있어 ranging을 진행할 수 없다.
class BeaconBluetoothOff extends BeaconScanState {
  const BeaconBluetoothOff();

  @override
  bool operator ==(Object other) => other is BeaconBluetoothOff;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'BeaconBluetoothOff';
}

/// 스캔에 필요한 권한(위치 등)이 거부됐다.
class BeaconPermissionDenied extends BeaconScanState {
  const BeaconPermissionDenied();

  @override
  bool operator ==(Object other) => other is BeaconPermissionDenied;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'BeaconPermissionDenied';
}

/// 스캔 중이지만 아직 [BeaconDetected]로 안정화되지 않았다 — 신호가 아예
/// 없거나, 임계값 이상이지만 안정화 시간을 채우는 중인 경우 둘 다 포함한다.
class BeaconScanning extends BeaconScanState {
  const BeaconScanning();

  @override
  bool operator ==(Object other) => other is BeaconScanning;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'BeaconScanning';
}

/// `rssi >= rssiThreshold`가 `stabilizationSeconds` 이상 연속으로 유지되어
/// 출석 인정 대상으로 확정됐다.
class BeaconDetected extends BeaconScanState {
  const BeaconDetected(this.rssi);

  final int rssi;

  @override
  bool operator ==(Object other) => other is BeaconDetected && other.rssi == rssi;

  @override
  int get hashCode => Object.hash(runtimeType, rssi);

  @override
  String toString() => 'BeaconDetected(rssi: $rssi)';
}

/// [BeaconDetected] 이후 신호가 임계값 아래로 떨어졌다.
class BeaconOutOfRange extends BeaconScanState {
  const BeaconOutOfRange();

  @override
  bool operator ==(Object other) => other is BeaconOutOfRange;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'BeaconOutOfRange';
}

/// 스캔 하나를 설정하는 값. 클럽마다 서버가 내려주는 [BeaconConfig]로부터
/// 채워진다.
class BeaconScanConfig {
  // 아래 검증이 Duration 비교(인스턴스 생성·연산자 호출)를 필요로 해
  // Dart의 컴파일타임 상수 평가기가 다룰 수 있는 범위를 벗어난다 — 그래서
  // 이 생성자는 (Task 1 시점과 달리) 더 이상 `const`가 아니다. 기존
  // `const BeaconScanConfig(...)` 호출부는 전부 일반 호출로 바꿨다.
  //
  // `assert`가 아니라 `ArgumentError`인 이유: `assert`는 릴리즈 빌드에서
  // 통째로 사라지므로, 사용자가 실제로 쓰는 빌드에서는 이 불변식이 아무것도
  // 막지 못한다("검증이 있다"는 착시만 남는다). 오늘의 유일한 실제 경로
  // ([BeaconScanConfigMapping.toScanConfig])는 `maxSampleGap`을
  // `stabilizationSeconds` 이하로 클램프해서 넘기므로 서버가 무슨 값을
  // 내려주든 이 예외에 닿지 않는다 — 즉 이 예외는 손으로 잘못 만든 설정
  // (앞으로 생길 다른 호출자)에만 반응하는 진짜 방어선이지, 정상 경로를
  // 깨뜨리는 장치가 아니다.
  BeaconScanConfig({
    required this.uuid,
    this.rssiThreshold = -70,
    this.stabilizationSeconds = 3,
    this.maxSampleGap = const Duration(seconds: 2),
  }) {
    if (maxSampleGap > Duration(seconds: stabilizationSeconds)) {
      throw ArgumentError.value(
        maxSampleGap,
        'maxSampleGap',
        'maxSampleGap는 stabilizationSeconds(${stabilizationSeconds}s)를 넘을 수 없다 — 넘으면 그 사이의 '
            '진짜 침묵(신호 없음)도 "연속 감지"로 오인되어, 출석 인정의 유일한 보증(실내에 계속 있었다)이 무너진다.',
      );
    }
  }

  /// 우리 클럽 비콘의 proximity UUID. 대소문자와 하이픈 유무는 비교 시
  /// 무시한다.
  final String uuid;

  /// 이 값 이상이어야 "감지됨" 후보로 본다.
  final int rssiThreshold;

  /// [rssiThreshold] 이상이 연속으로 유지되어야 하는 최소 시간(초).
  final int stabilizationSeconds;

  /// 연속된 두 "좋은" 샘플 사이에 이 값보다 긴 공백이 있으면 침묵으로 보고
  /// 스트릭을 리셋한다. ranging은 대략 1초에 한 번씩 이벤트를 흘려보내므로
  /// 기본값 2초는 정상적인 스캔 주기 지터는 흡수하면서도, 한동안 신호가
  /// 아예 없다가 온 프레임 하나가 "계속 연속됐다"고 착각하는 것은 막는다.
  final Duration maxSampleGap;
}

/// BLE 비콘 감지를 추상화한 계약. 화면과 컨트롤러는 이 인터페이스에만
/// 의존한다 — 실 구현은 [FlutterBeaconScanner](data), 테스트는
/// `FakeBeaconScanner`(test/support)를 쓴다.
abstract interface class BeaconScanner {
  /// [config]로 스캔을 시작하고 상태 변화를 흘려보낸다. 새로 부르면 이전
  /// 스캔은 정리되고 새 스캔으로 대체된다.
  Stream<BeaconScanState> watch(BeaconScanConfig config);

  /// 스캔을 멈추고 관련 구독을 전부 해제한다.
  Future<void> stop();
}
