import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';
import '../storage/token_store.dart';
import '../storage/token_write_coordinator.dart';
import 'api_client.dart';
import 'auth_interceptor.dart';

final tokenStoreProvider = Provider<TokenStore>((ref) {
  return const SecureTokenStore(FlutterSecureStorage());
});

/// SessionController와 AuthInterceptor가 **같은** 인스턴스를 공유해야 하므로
/// 반드시 프로바이더 하나에서만 만든다. 둘이 각자 만들면 큐도 세대도 갈라져
/// 직렬화 보장이 사라진다. 이 프로바이더는 세션 컨트롤러보다 오래 살아야
/// 한다 — 세대가 invalidate 때마다 0으로 되돌아가면 낡은 쓰기가 다시
/// 최신으로 보인다.
final tokenWriteCoordinatorProvider = Provider<TokenWriteCoordinator>((ref) {
  return TokenWriteCoordinator(ref.watch(tokenStoreProvider));
});

/// 인터셉터가 재발급에 실패해 세션이 만료된 순간을 SessionController가
/// 구독한다(build()가 이 값을 watch해 다시 판별한다).
final sessionExpiredProvider = StateProvider<int>((ref) => 0);

final dioProvider = Provider<Dio>((ref) {
  final options = BaseOptions(
    baseUrl: AppConfig.apiRoot,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    contentType: Headers.jsonContentType,
  );

  final dio = Dio(options);

  // AuthInterceptor는 재발급/재시도용으로 이 dio 자신의 transport를 그대로
  // 빌려 쓰는 인터셉터 없는 인스턴스를 내부에서 만든다 — 별도 Dio를 미리
  // 만들어 넘길 필요가 없다.
  dio.interceptors.add(
    AuthInterceptor(
      tokens: ref.watch(tokenWriteCoordinatorProvider),
      dio: dio,
      onSessionExpired: () => ref.read(sessionExpiredProvider.notifier).state++,
    ),
  );

  return dio;
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(dioProvider));
});
