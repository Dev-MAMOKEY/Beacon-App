import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// ESP32 비콘과 공유하는 사전 공유 키(PSK).
///
/// **API에 이 값의 출처가 없다.** 서버는 PSK를 내려주지도, 받지도 않는다 —
/// 펌웨어에 구워진 값과 관리자 앱이 들고 있는 값이 같아야 GATT 명령이
/// 받아들여진다. 그래서 관리자에게 직접 입력받아 이 기기에만 저장한다.
///
/// 저장 위치가 `flutter_secure_storage`인 이유: 이 값을 아는 사람은 누구나
/// 그 동아리의 비콘에 출석 시작을 명령할 수 있다. 평문 파일(`SharedPreferences`)
/// 에 두면 루팅된 기기에서 그대로 읽힌다.
abstract interface class BeaconPskStore {
  /// 저장된 PSK. 없으면 null.
  Future<String?> read();

  /// [psk]를 저장한다. 32자 hex가 아니면 [ArgumentError]를 던진다.
  Future<void> save(String psk);

  Future<void> clear();
}

/// PSK 형식 검증. 통과한 값만 저장·전송된다.
///
/// `assert`가 아니라 순수 함수 + [ArgumentError]인 이유는 이 프로젝트의
/// 다른 검증과 같다 — `assert`는 릴리즈에서 사라져, 사용자가 실제로 쓰는
/// 빌드에서 잘못된 키가 조용히 저장된다.
///
/// 형식이 틀린 PSK는 **증상이 늦게 나타난다**: 저장은 되고, 세션도 시작되고,
/// 비콘만 광고를 시작하지 않는다. 그 실패는 현장에서 "출석이 안 된다"로만
/// 보이므로 입력 시점에 막는다.
bool isValidBeaconPsk(String value) {
  if (value.length != 32) return false;
  for (var i = 0; i < value.length; i++) {
    final c = value.codeUnitAt(i);
    final isDigit = c >= 0x30 && c <= 0x39;
    final isLower = c >= 0x61 && c <= 0x66;
    final isUpper = c >= 0x41 && c <= 0x46;
    if (!isDigit && !isLower && !isUpper) return false;
  }
  return true;
}

class SecureBeaconPskStore implements BeaconPskStore {
  const SecureBeaconPskStore(this._storage);

  static const String _key = 'beacon_psk';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> save(String psk) {
    if (!isValidBeaconPsk(psk)) {
      throw ArgumentError.value(psk, 'psk', 'PSK는 32자 16진수여야 한다');
    }
    // 소문자로 정규화해 저장한다 — 대소문자가 섞여 들어와도 페이로드
    // 인코딩 결과는 같지만, 저장값이 갈리면 "같은 키를 다시 입력했는데
    // 왜 또 묻지?" 같은 혼란이 생긴다.
    return _storage.write(key: _key, value: psk.toLowerCase());
  }

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

final beaconPskStoreProvider = Provider<BeaconPskStore>((ref) {
  return const SecureBeaconPskStore(FlutterSecureStorage());
});
