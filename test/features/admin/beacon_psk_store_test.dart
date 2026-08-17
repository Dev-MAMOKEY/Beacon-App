import 'package:beacon_app/features/admin/data/beacon_psk_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// 형식이 틀린 PSK는 **증상이 늦게 나타난다** — 저장되고, 세션도 시작되고,
/// 비콘만 광고를 시작하지 않는다. 그 실패는 현장에서 "출석이 안 된다"로만
/// 보이고 앱에는 단서가 없다. 그래서 입력 시점에 막는다.
void main() {
  const valid = '000102030405060708090a0b0c0d0e0f';

  group('형식 검증', () {
    test('32자 16진수를 받는다', () {
      expect(isValidBeaconPsk(valid), isTrue);
    });

    test('대문자도 받는다', () {
      expect(isValidBeaconPsk(valid.toUpperCase()), isTrue);
    });

    test('길이가 다르면 거부한다', () {
      // 잡아야 할 잘못된 구현: 길이를 안 보고 hex 문자만 확인한다 — 16자
      // 키가 통과하면 페이로드 앞 16바이트가 어긋나 비콘이 거부한다.
      expect(isValidBeaconPsk('00010203040506070809'), isFalse);
      expect(isValidBeaconPsk('${valid}00'), isFalse);
      expect(isValidBeaconPsk(''), isFalse);
    });

    test('16진수가 아닌 문자를 거부한다', () {
      // 잡아야 할 잘못된 구현: `int.parse(radix: 16)`으로 검사한다 — 그
      // 함수는 앞뒤 공백과 부호를 받아들여 `' 1'`, `'-1'`이 통과한다.
      expect(isValidBeaconPsk('000102030405060708090a0b0c0d0e0g'), isFalse);
      expect(isValidBeaconPsk(' 00102030405060708090a0b0c0d0e0f'), isFalse);
      expect(isValidBeaconPsk('-00102030405060708090a0b0c0d0e0f'), isFalse);
    });

    test('하이픈이 섞이면 거부한다', () {
      // UUID처럼 하이픈을 넣어 붙여넣는 실수가 흔하다. 길이는 32를 넘으므로
      // 길이 검사로도 걸리지만, 32자에 맞춰 잘라 넣는 경우까지 막는다.
      expect(isValidBeaconPsk('00010203-0405-0607-0809-0a0b0c0d0e'), isFalse);
    });
  });

  test('형식이 틀리면 저장까지 가지 않고 던진다', () {
    // `FlutterSecureStorage`의 메서드는 플랫폼 채널을 요구해 테스트에서 부를
    // 수 없다 — 검증이 **그 앞에서** 막는다는 사실 자체가 이 테스트의 내용
    // 이다. 검증을 뒤로 옮기면 여기서 채널 오류가 나며 깨진다.
    const store = SecureBeaconPskStore(FlutterSecureStorage());

    expect(() => store.save('too-short'), throwsArgumentError);
  });
}
