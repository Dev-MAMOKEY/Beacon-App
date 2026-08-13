import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/dio_provider.dart';
import 'auth_dto.dart';

/// 화면이 실제로 쓰는 것만 노출한다.
abstract interface class AuthRepository {
  Future<TokenResponse> login({required String stdId, required String password});
  Future<void> signup({
    required String stdId,
    required String password,
    required String name,
  });
  Future<TokenResponse> refresh(String refreshToken);
  Future<void> logout();
  Future<MemberProfile> fetchMe();
}

class HttpAuthRepository implements AuthRepository {
  const HttpAuthRepository(this._client);

  final ApiClient _client;

  @override
  Future<TokenResponse> login({
    required String stdId,
    required String password,
  }) {
    return _client.post<TokenResponse>(
      '/auth/login',
      body: {'stdId': stdId, 'password': password},
      parse: (json) => TokenResponse.fromJson(json! as Map<String, dynamic>),
    );
  }

  @override
  Future<void> signup({
    required String stdId,
    required String password,
    required String name,
  }) {
    return _client.post<void>(
      '/auth/signup',
      body: {'stdId': stdId, 'password': password, 'name': name},
      parse: (_) {},
    );
  }

  @override
  Future<TokenResponse> refresh(String refreshToken) {
    return _client.post<TokenResponse>(
      '/auth/refresh',
      body: {'refreshToken': refreshToken},
      parse: (json) => TokenResponse.fromJson(json! as Map<String, dynamic>),
    );
  }

  @override
  Future<void> logout() {
    return _client.post<void>('/auth/logout', parse: (_) {});
  }

  @override
  Future<MemberProfile> fetchMe() {
    return _client.get<MemberProfile>(
      '/members/me',
      parse: (json) => MemberProfile.fromJson(json! as Map<String, dynamic>),
    );
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return HttpAuthRepository(ref.watch(apiClientProvider));
});
