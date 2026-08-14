import 'package:dchs_flutter_beacon/dchs_flutter_beacon.dart' as beacon_lib;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 블루투스가 꺼져 있을 때 홈 화면의 "설정 열기" 버튼이 부르는 동작을
/// Provider로 뽑아둔다 — 위젯 테스트가 실제 플랫폼 채널(`dchs_flutter_beacon`)
/// 을 두드리지 않고도 버튼 렌더링만 검증할 수 있게 하기 위해서다.
final openBluetoothSettingsProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    try {
      await beacon_lib.flutterBeacon.openBluetoothSettings;
    } catch (_) {
      // 설정 화면을 열지 못해도(기기·OS 제약 등) 앱이 죽어서는 안 된다.
    }
  };
});
