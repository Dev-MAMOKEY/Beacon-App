import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// FCM SDK를 감싼 얇은 계약.
///
/// 이 인터페이스가 있는 이유: `FirebaseMessaging.instance`는 플랫폼 채널을
/// 요구해서 위젯 테스트에서 부를 수 없다. 토큰 등록 로직(언제 보내는지,
/// 실패하면 어떻게 하는지, 갱신을 따라가는지)은 SDK와 무관한 우리 결정이고
/// **그 결정이 틀리면 알림이 조용히 안 온다** — 그 부분만 따로 검증한다.
abstract interface class PushMessaging {
  /// 알림 권한을 요청한다. 거부돼도 앱의 다른 기능은 그대로 동작한다.
  Future<bool> requestPermission();

  /// 지금 토큰. 권한이 없거나 발급 전이면 null이다.
  Future<String?> getToken();

  /// 토큰이 갱신될 때마다 새 값을 흘린다. FCM은 앱 재설치·데이터 삭제·
  /// 장기 미사용 등으로 토큰을 바꾸는데, 그때 서버가 옛 토큰을 들고 있으면
  /// **알림이 조용히 끊긴다** — 화면에는 아무 증상이 없다.
  Stream<String> get onTokenRefresh;

  /// 앱이 열려 있는 동안 도착하는 알림.
  Stream<RemoteMessage> get onForegroundMessage;
}

class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging(this._messaging);

  final FirebaseMessaging _messaging;

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Stream<RemoteMessage> get onForegroundMessage => FirebaseMessaging.onMessage;
}

final pushMessagingProvider = Provider<PushMessaging>((ref) {
  return FirebasePushMessaging(FirebaseMessaging.instance);
});
