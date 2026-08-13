import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';
import '../storage/token_store.dart';
import 'api_client.dart';
import 'auth_interceptor.dart';

final tokenStoreProvider = Provider<TokenStore>((ref) {
  return const SecureTokenStore(FlutterSecureStorage());
});

/// 재발급이 필요해진 순간을 라우터가 구독한다. Task 7에서 사용한다.
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
      store: ref.watch(tokenStoreProvider),
      dio: dio,
      onSessionExpired: () => ref.read(sessionExpiredProvider.notifier).state++,
    ),
  );

  return dio;
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(dioProvider));
});
