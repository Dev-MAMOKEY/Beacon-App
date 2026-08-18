import 'dart:async';

import 'package:beacon_app/features/notification/data/push_messaging.dart';
import 'package:beacon_app/features/notification/presentation/fcm_token_registrar.dart';
import 'package:beacon_app/features/profile/data/profile_repository.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

/// **이 로직의 실패는 화면에 아무 증상도 남기지 않는다.** 토큰이 등록되지
/// 않으면 알림만 안 오고, 사용자는 "원래 안 오나 보다"라고 생각한다. 앱
/// 어디에도 단서가 없으므로 등록 조건·재시도·갱신 추적을 전부 여기서 고정한다.
class _FakeMessaging implements PushMessaging {
  String? token = 'token-1';
  bool permissionGranted = true;
  int permissionRequests = 0;
  int tokenReads = 0;

  final StreamController<String> refresh = StreamController<String>.broadcast();

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permissionGranted;
  }

  @override
  Future<String?> getToken() async {
    tokenReads++;
    return token;
  }

  @override
  Stream<String> get onTokenRefresh => refresh.stream;

  @override
  Stream<RemoteMessage> get onForegroundMessage => const Stream.empty();
}

class _RecordingProfileRepository implements ProfileRepository {
  final List<String> tokens = [];
  bool throws = false;

  @override
  Future<void> updateFcmToken(String token) async {
    tokens.add(token);
    if (throws) throw Exception('등록 실패');
  }

  @override
  Future<void> updateProfile({
    required String name,
    String? title,
    bool? pushEnabled,
  }) async {}

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmNewPassword,
  }) async {}
}

void main() {
  late _FakeMessaging messaging;
  late _RecordingProfileRepository profile;
  late FcmTokenRegistrar registrar;

  setUp(() {
    messaging = _FakeMessaging();
    profile = _RecordingProfileRepository();
    registrar = FcmTokenRegistrar(messaging: messaging, profile: profile);
  });

  tearDown(() async {
    await registrar.stop();
    await messaging.refresh.close();
  });

  test('시작하면 권한을 묻고 토큰을 등록한다', () async {
    await registrar.start();

    expect(messaging.permissionRequests, 1);
    expect(profile.tokens, ['token-1']);
  });

  test('권한이 거부돼도 토큰이 있으면 등록한다', () async {
    // 잡아야 할 잘못된 구현: 권한이 없으면 등록을 건너뛴다. Android는 알림
    // 표시만 막힐 뿐 토큰은 유효해서, 사용자가 나중에 설정에서 허용하면
    // 바로 받아야 한다 — 그때 서버에 토큰이 없으면 영영 안 온다.
    messaging.permissionGranted = false;

    await registrar.start();

    expect(profile.tokens, ['token-1']);
  });

  test('토큰이 없으면 등록하지 않는다', () async {
    messaging.token = null;

    await registrar.start();

    expect(profile.tokens, isEmpty);
  });

  test('토큰이 갱신되면 새 값을 등록한다', () async {
    // 잡아야 할 잘못된 구현: 시작 시 한 번만 등록하고 갱신을 구독하지
    // 않는다. FCM은 재설치·데이터 삭제·장기 미사용으로 토큰을 바꾸는데,
    // 그때 서버가 옛 토큰을 들고 있으면 **알림이 조용히 끊긴다.**
    await registrar.start();

    messaging.refresh.add('token-2');
    await pumpEventQueue();

    expect(profile.tokens, ['token-1', 'token-2']);
  });

  test('같은 토큰은 다시 보내지 않는다', () async {
    await registrar.start();

    messaging.refresh.add('token-1');
    await pumpEventQueue();

    expect(profile.tokens, ['token-1'], reason: '바뀐 게 없으면 요청도 없다');
  });

  test('등록에 실패하면 성공으로 기억하지 않고 다음에 다시 시도한다', () async {
    // 잡아야 할 잘못된 구현: 실패해도 `_registeredToken`을 채운다 — 그러면
    // 같은 토큰에 대해 **영영 재시도하지 않아** 알림이 계속 안 온다.
    profile.throws = true;
    await registrar.start();
    expect(profile.tokens, ['token-1']);

    profile.throws = false;
    messaging.refresh.add('token-1');
    await pumpEventQueue();

    expect(profile.tokens, ['token-1', 'token-1'], reason: '실패한 토큰은 다시 보낸다');
  });

  test('등록 실패가 밖으로 새지 않는다', () async {
    // fire-and-forget으로 불리므로 예외가 새면 처리되지 않은 비동기 오류가
    // 되고, 로그인 흐름이 그 위에서 깨질 수 있다.
    profile.throws = true;

    await expectLater(registrar.start(), completes);
  });

  test('멈추면 갱신을 더는 따라가지 않는다', () async {
    await registrar.start();
    await registrar.stop();

    messaging.refresh.add('token-2');
    await pumpEventQueue();

    expect(profile.tokens, ['token-1'], reason: '로그아웃 뒤에는 등록하지 않는다');
  });

  test('멈춘 뒤 다시 시작하면 같은 토큰도 다시 등록한다', () async {
    // 잡아야 할 잘못된 구현: `stop()`에서 확인된 토큰 기억을 지우지 않는다.
    // 다른 계정으로 로그인했을 때 "같은 토큰"이라는 이유로 등록을 건너뛰면,
    // **그 기기의 알림이 이전 계정에 묶인 채로 남는다.**
    await registrar.start();
    await registrar.stop();
    await registrar.start();

    expect(profile.tokens, ['token-1', 'token-1']);
  });

  test('다시 시작해도 갱신 구독이 하나만 남는다', () async {
    // 잡아야 할 잘못된 구현: 이전 구독을 취소하지 않고 새로 건다 — 갱신
    // 한 번에 등록 요청이 두 번 나간다.
    await registrar.start();
    await registrar.start();
    profile.tokens.clear();

    messaging.refresh.add('token-9');
    await pumpEventQueue();

    expect(profile.tokens, ['token-9']);
  });
}
