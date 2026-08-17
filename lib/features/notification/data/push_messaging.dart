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

/// 포그라운드에서 도착한 알림을 흘리는 스트림.
///
/// `AppShell`이 이걸 듣고 토스트로 띄운다 — 앱이 열려 있는 동안에는 OS가
/// 알림 배너를 그려 주지 않으므로, 우리가 보여주지 않으면 **사용자는 알림이
/// 온 줄도 모른다.**
final foregroundMessageProvider = StreamProvider<RemoteMessage>((ref) {
  return ref.watch(pushMessagingProvider).onForegroundMessage;
});

/// 알림에서 토스트에 띄울 한 줄을 고른다. 띄울 게 없으면 null.
///
/// `body`를 먼저 보는 이유: 제목은 "출석 알림"처럼 분류에 가깝고 실제 내용은
/// 본문에 있다. 데이터만 있는 알림(`notification`이 없는 무음 메시지)은
/// **아무것도 띄우지 않는다** — 빈 토스트가 뜨면 사용자는 무슨 일이
/// 일어났는지 모른 채 놀라기만 한다.
///
/// `AppShell`이 부르므로 `@visibleForTesting`이 아니다 — 순수 함수라
/// 테스트가 Firebase 없이 그대로 검증한다.
String? foregroundToastText(RemoteMessage message) {
  final notification = message.notification;
  final body = notification?.body?.trim();
  if (body != null && body.isNotEmpty) return body;
  final title = notification?.title?.trim();
  if (title != null && title.isNotEmpty) return title;
  return null;
}
