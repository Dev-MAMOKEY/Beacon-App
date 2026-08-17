/// ESP32의 GATT characteristic에 write할 **출석 시작 명령**의 34바이트 인코딩.
///
/// 레이아웃(펌웨어 `gatt_server.ino` 기준):
/// ```
/// [0..15]  PSK          16바이트 — 관리자가 설정 화면에서 입력해 secure
///                       storage에 저장해 둔 32자 hex를 디코딩한 값
/// [16..31] Session UUID 16바이트 — 세션 시작 응답의 uuid에서 하이픈을 빼고
///                       hex 디코딩한 값
/// [32..33] Duration     2바이트 **리틀엔디안** 초 단위(60초 → 0x3C 0x00)
/// ```
///
/// BLE 전송(스캔·연결·discover·write)과 분리해 둔 이유: 전송은 실기기가
/// 없으면 한 줄도 검증할 수 없지만, **이 인코딩은 순수 함수라 전부 검증할 수
/// 있다.** 바이트 하나만 어긋나도 비콘이 광고를 시작하지 않고, 그 실패는
/// 현장에서 "출석이 안 된다"로만 나타나 원인을 짚기 어렵다.
library;

import 'dart:typed_data';

/// 명령의 기본 광고 지속 시간. 펌웨어가 이 값만큼 광고한 뒤 스스로 멈춘다.
const Duration defaultBeaconAdvertiseDuration = Duration(seconds: 60);

/// 페이로드 전체 길이. 펌웨어가 정확히 이 길이만 받는다.
const int beaconCommandPayloadLength = 34;

const int _pskBytes = 16;
const int _uuidBytes = 16;

/// [psk]와 [sessionUuid]로 34바이트 명령을 만든다.
///
/// - [psk]는 하이픈 없는 32자 hex여야 한다(16바이트).
/// - [sessionUuid]는 하이픈이 있어도 되고 없어도 된다 — 제거 후 32자 hex여야
///   한다. 대소문자는 가리지 않는다.
/// - [duration]은 1초 이상이고 `0xFFFF`초 이하여야 한다.
///
/// 어긋나면 [ArgumentError]를 던진다. `assert`가 아닌 이유는 이 프로젝트의
/// 다른 검증과 같다 — `assert`는 릴리즈 빌드에서 통째로 사라지므로, 사용자가
/// 실제로 쓰는 빌드에서 잘못된 길이의 페이로드가 조용히 전송된다.
Uint8List encodeBeaconStartCommand({
  required String psk,
  required String sessionUuid,
  Duration duration = defaultBeaconAdvertiseDuration,
}) {
  final pskBytes = _decodeHex(psk, expectedBytes: _pskBytes, label: 'psk');
  final uuidBytes = _decodeHex(
    sessionUuid.replaceAll('-', ''),
    expectedBytes: _uuidBytes,
    label: 'sessionUuid',
  );

  final seconds = duration.inSeconds;
  if (seconds < 1 || seconds > 0xFFFF) {
    throw ArgumentError.value(
      duration,
      'duration',
      '1초 이상 65535초 이하여야 한다 — 2바이트에 담기지 않으면 펌웨어가 엉뚱한 시간을 읽는다',
    );
  }
  // 초 단위로 잘라 보내므로 밀리초가 남아 있으면 조용히 버려진다. 호출자가
  // 의도한 값과 실제 전송값이 달라지는 것을 막는다.
  if (duration.inMilliseconds % Duration.millisecondsPerSecond != 0) {
    throw ArgumentError.value(
      duration,
      'duration',
      '초 단위여야 한다 — 밀리초는 전송되지 않고 조용히 버려진다',
    );
  }

  final payload = Uint8List(beaconCommandPayloadLength)
    ..setRange(0, _pskBytes, pskBytes)
    ..setRange(_pskBytes, _pskBytes + _uuidBytes, uuidBytes);

  // 리틀엔디안: 하위 바이트가 먼저다(60 → 0x3C 0x00). 빅엔디안으로 보내면
  // 60초가 15360초가 된다.
  payload[32] = seconds & 0xFF;
  payload[33] = (seconds >> 8) & 0xFF;

  return payload;
}

Uint8List _decodeHex(String value, {required int expectedBytes, required String label}) {
  final expectedChars = expectedBytes * 2;
  if (value.length != expectedChars) {
    throw ArgumentError.value(
      value,
      label,
      '하이픈을 제외하고 정확히 $expectedChars자여야 한다(현재 ${value.length}자)',
    );
  }

  final bytes = Uint8List(expectedBytes);
  for (var i = 0; i < expectedBytes; i++) {
    final high = _hexDigit(value.codeUnitAt(i * 2));
    final low = _hexDigit(value.codeUnitAt(i * 2 + 1));
    if (high < 0 || low < 0) {
      throw ArgumentError.value(value, label, '16진수가 아닌 문자가 있다');
    }
    bytes[i] = (high << 4) | low;
  }
  return bytes;
}

/// 16진수 한 글자를 값으로. 아니면 -1.
///
/// `int.parse(radix: 16)`을 쓰지 않는 이유: 그 함수는 앞뒤 공백과 `+`/`-`
/// 부호를 받아들여서 `' 1'`이나 `'-1'`이 조용히 통과한다.
int _hexDigit(int codeUnit) {
  if (codeUnit >= 0x30 && codeUnit <= 0x39) return codeUnit - 0x30; // 0-9
  if (codeUnit >= 0x61 && codeUnit <= 0x66) return codeUnit - 0x61 + 10; // a-f
  if (codeUnit >= 0x41 && codeUnit <= 0x46) return codeUnit - 0x41 + 10; // A-F
  return -1;
}
