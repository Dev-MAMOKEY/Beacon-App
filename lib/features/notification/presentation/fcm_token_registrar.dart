import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/session_controller.dart';
import '../../profile/data/profile_repository.dart';
import '../data/push_messaging.dart';

/// 로그인한 동안 FCM 토큰을 서버에 등록해 두는 일을 맡는다.
///
/// **이 클래스의 실패는 화면에 아무 증상도 남기지 않는다.** 토큰이 등록되지
/// 않으면 알림만 안 올 뿐 앱의 다른 기능은 멀쩡하고, 사용자는 "알림이 원래
/// 안 오나 보다"라고 생각한다. 그래서 등록 조건·재시도·갱신 추적을 전부
/// 테스트로 고정한다 — 여기서 조용히 틀리면 알아챌 방법이 없다.
class FcmTokenRegistrar {
  FcmTokenRegistrar({required this.messaging, required this.profile});

  final PushMessaging messaging;
  final ProfileRepository profile;

  StreamSubscription<String>? _refreshSub;

  /// 마지막으로 **서버가 받았다고 확인된** 토큰. 같은 값을 다시 보내지 않기
  /// 위한 것이지, 실패한 값을 성공으로 기억하면 안 된다 — 그래서 등록이
  /// 끝난 뒤에만 채운다.
  String? _registeredToken;

  /// 로그인 직후 한 번 부른다. 권한을 묻고, 토큰을 받아 등록하고,
  /// 갱신 구독을 건다.
  Future<void> start() async {
    // 권한이 거부돼도 계속 진행한다. iOS는 거부 시 토큰을 주지 않지만
    // Android는 알림 표시만 막힐 뿐 토큰은 유효하다 — 등록해 두면 사용자가
    // 나중에 설정에서 허용했을 때 바로 받는다.
    await messaging.requestPermission();

    final token = await messaging.getToken();
    if (token != null) await _register(token);

    await _refreshSub?.cancel();
    // 갱신을 놓치면 서버가 죽은 토큰을 들고 있게 되고 알림이 조용히 끊긴다.
    _refreshSub = messaging.onTokenRefresh.listen(_register);
  }

  Future<void> stop() async {
    await _refreshSub?.cancel();
    _refreshSub = null;
    // 로그아웃하면 "확인된 토큰" 기억도 지운다 — 다른 계정으로 로그인했을
    // 때 같은 토큰이라는 이유로 등록을 건너뛰면, 그 기기의 알림이 이전
    // 계정에 묶인 채로 남는다.
    _registeredToken = null;
  }

  Future<void> _register(String token) async {
    if (token == _registeredToken) return;
    try {
      await profile.updateFcmToken(token);
      _registeredToken = token;
    } catch (_) {
      // 실패를 삼키되 **기억하지 않는다** — 다음 기회(재로그인·토큰 갱신)에
      // 다시 시도한다. 여기서 `_registeredToken`을 채우면 영영 재시도하지
      // 않는다.
    }
  }
}

/// 세션이 준비되면 등록을 시작하고, 로그아웃하면 멈춘다.
final fcmTokenRegistrarProvider = Provider<FcmTokenRegistrar>((ref) {
  final registrar = FcmTokenRegistrar(
    messaging: ref.watch(pushMessagingProvider),
    profile: ref.watch(profileRepositoryProvider),
  );
  ref.onDispose(() => unawaited(registrar.stop()));

  ref.listen(sessionControllerProvider, (previous, next) {
    final state = next.value;
    if (state is SessionReady) {
      unawaited(registrar.start());
    } else {
      unawaited(registrar.stop());
    }
  }, fireImmediately: true);

  return registrar;
});
