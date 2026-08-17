import 'package:beacon_app/features/beacon/domain/beacon_command_payload.dart';
import 'package:flutter_test/flutter_test.dart';

/// 34바이트 중 하나만 어긋나도 비콘이 광고를 시작하지 않고, 그 실패는
/// 현장에서 "출석이 안 된다"로만 나타난다 — 원인을 짚을 단서가 앱에는
/// 남지 않는다. 그래서 각 구간을 따로, 그리고 **서로 구별되는 값**으로
/// 고정한다.
void main() {
  // 세 구간이 전부 다른 바이트로 채워지는 픽스처. 같은 값을 쓰면 구간이
  // 뒤바뀐 구현(PSK와 UUID 자리를 바꾼 것 등)을 잡지 못한다.
  const psk = '000102030405060708090a0b0c0d0e0f';
  const uuid = 'f0e0d0c0-b0a0-9080-7060-504030201000';

  test('정확히 34바이트다', () {
    // 잡아야 할 잘못된 구현: 길이를 32나 36으로 만든다. 펌웨어는 정확히
    // 34바이트만 받는다.
    final payload = encodeBeaconStartCommand(psk: psk, sessionUuid: uuid);
    expect(payload, hasLength(34));
    expect(beaconCommandPayloadLength, 34);
  });

  test('PSK가 앞 16바이트에 그대로 들어간다', () {
    // 잡아야 할 잘못된 구현: PSK와 UUID의 자리를 바꾼다.
    final payload = encodeBeaconStartCommand(psk: psk, sessionUuid: uuid);
    expect(
      payload.sublist(0, 16),
      [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    );
  });

  test('세션 UUID는 하이픈을 빼고 16바이트로 들어간다', () {
    // 잡아야 할 잘못된 구현: 하이픈을 그대로 두고 ASCII로 넣거나, 하이픈만
    // 빼고 hex 디코딩을 하지 않는다(그러면 32바이트가 된다).
    final payload = encodeBeaconStartCommand(psk: psk, sessionUuid: uuid);
    expect(
      payload.sublist(16, 32),
      [0xf0, 0xe0, 0xd0, 0xc0, 0xb0, 0xa0, 0x90, 0x80, 0x70, 0x60, 0x50, 0x40, 0x30, 0x20, 0x10, 0x00],
    );
  });

  test('하이픈이 없는 UUID도 같은 결과를 낸다', () {
    final withHyphen = encodeBeaconStartCommand(psk: psk, sessionUuid: uuid);
    final withoutHyphen = encodeBeaconStartCommand(
      psk: psk,
      sessionUuid: uuid.replaceAll('-', ''),
    );
    expect(withoutHyphen, withHyphen);
  });

  test('대문자 hex도 같은 결과를 낸다', () {
    final lower = encodeBeaconStartCommand(psk: psk, sessionUuid: uuid);
    final upper = encodeBeaconStartCommand(
      psk: psk.toUpperCase(),
      sessionUuid: uuid.toUpperCase(),
    );
    expect(upper, lower);
  });

  test('기본 60초는 리틀엔디안 0x3C 0x00이다', () {
    // 잡아야 할 잘못된 구현: 빅엔디안으로 쓴다 — 그러면 펌웨어가 60초를
    // 15360초(4시간 16분)로 읽는다.
    final payload = encodeBeaconStartCommand(psk: psk, sessionUuid: uuid);
    expect(payload.sublist(32), [0x3C, 0x00]);
    expect(defaultBeaconAdvertiseDuration, const Duration(seconds: 60));
  });

  test('두 바이트가 모두 쓰이는 값에서도 리틀엔디안이다', () {
    // 60초만으로는 상위 바이트가 늘 0이라 엔디안을 구별하지 못한다 —
    // 상위·하위가 서로 다른 값이어야 갈린다.
    final payload = encodeBeaconStartCommand(
      psk: psk,
      sessionUuid: uuid,
      duration: const Duration(seconds: 0x1234),
    );
    expect(payload.sublist(32), [0x34, 0x12], reason: '하위 바이트가 먼저다');
  });

  group('거부해야 하는 입력', () {
    test('PSK 길이가 32자가 아니면 던진다', () {
      expect(
        () => encodeBeaconStartCommand(psk: '00', sessionUuid: uuid),
        throwsArgumentError,
      );
    });

    test('PSK에 16진수가 아닌 문자가 있으면 던진다', () {
      // 잡아야 할 잘못된 구현: `int.parse(radix: 16)`으로 디코딩한다 —
      // 그 함수는 공백과 부호를 받아들여 `' 1'`, `'-1'`이 조용히 통과한다.
      expect(
        () => encodeBeaconStartCommand(
          psk: '000102030405060708090a0b0c0d0e0g',
          sessionUuid: uuid,
        ),
        throwsArgumentError,
      );
      expect(
        () => encodeBeaconStartCommand(
          psk: ' 0102030405060708090a0b0c0d0e0f0',
          sessionUuid: uuid,
        ),
        throwsArgumentError,
      );
    });

    test('UUID가 하이픈 제거 후 32자가 아니면 던진다', () {
      expect(
        () => encodeBeaconStartCommand(psk: psk, sessionUuid: 'abc'),
        throwsArgumentError,
      );
    });

    test('지속 시간이 2바이트를 넘거나 0 이하면 던진다', () {
      for (final bad in [Duration.zero, const Duration(seconds: 0x10000)]) {
        expect(
          () => encodeBeaconStartCommand(psk: psk, sessionUuid: uuid, duration: bad),
          throwsArgumentError,
          reason: '$bad',
        );
      }
    });

    test('초 단위가 아닌 지속 시간은 던진다', () {
      // 잡아야 할 잘못된 구현: `inSeconds`로 조용히 잘라낸다 — 호출자가
      // 의도한 값과 실제 전송값이 달라진다.
      expect(
        () => encodeBeaconStartCommand(
          psk: psk,
          sessionUuid: uuid,
          duration: const Duration(milliseconds: 1500),
        ),
        throwsArgumentError,
      );
    });
  });
}
