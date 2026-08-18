import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/notification/presentation/fcm_token_registrar.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();

  // Firebase 초기화가 실패해도 앱은 뜬다 — 알림만 못 받는다. 여기서 던지면
  // 설정 파일이 없는 개발 환경에서 앱이 아예 시작하지 않는다
  // (`firebase_options.dart`는 `.gitignore`라 각자 생성한다).
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {
    // 초기화 실패는 `fcmTokenRegistrarProvider`가 토큰을 못 받는 것으로
    // 이어지고, 그쪽이 조용히 넘어간다.
  }

  runApp(const ProviderScope(child: BeaconApp()));
}

class BeaconApp extends ConsumerWidget {
  const BeaconApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 세션이 준비되면 FCM 토큰 등록을 시작한다. Provider가 세션을 구독하고
    // 있어 여기서는 살려 두기만 하면 된다 — 읽지 않으면 생성되지 않는다.
    ref.watch(fcmTokenRegistrarProvider);

    return MaterialApp.router(
      title: '마모키',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
