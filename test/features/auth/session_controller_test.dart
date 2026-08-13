import 'package:beacon_app/core/network/api_exception.dart';
import 'package:beacon_app/core/network/dio_provider.dart';
import 'package:beacon_app/core/network/error_code.dart';
import 'package:beacon_app/core/storage/token_store.dart';
import 'package:beacon_app/features/auth/data/auth_dto.dart';
import 'package:beacon_app/features/auth/data/auth_repository.dart';
import 'package:beacon_app/features/auth/presentation/session_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.profile, this.refreshFails = false});

  MemberProfile? profile;
  bool refreshFails;
  int logoutCalls = 0;

  @override
  Future<TokenResponse> login({required String stdId, required String password}) async {
    return const TokenResponse(accessToken: 'a', refreshToken: 'r');
  }

  @override
  Future<void> signup({
    required String stdId,
    required String password,
    required String name,
  }) async {}

  @override
  Future<TokenResponse> refresh(String refreshToken) async {
    if (refreshFails) {
      throw const ApiException(ErrorCode.refreshTokenRevoked, '무효화됨');
    }
    return const TokenResponse(accessToken: 'a2', refreshToken: 'r2');
  }

  @override
  Future<void> logout() async => logoutCalls++;

  @override
  Future<MemberProfile> fetchMe() async {
    final value = profile;
    if (value == null) {
      throw const ApiException(ErrorCode.tokenInvalid, '토큰 없음');
    }
    return value;
  }
}

ProviderContainer _container({
  required AuthRepository repository,
  required TokenStore store,
}) {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(repository),
      tokenStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('저장된 토큰이 없으면 SignedOut', () async {
    final container = _container(
      repository: FakeAuthRepository(),
      store: InMemoryTokenStore(),
    );

    final state = await container.read(sessionControllerProvider.future);

    expect(state, isA<SessionSignedOut>());
  });

  test('토큰이 있고 동아리가 있으면 Ready', () async {
    final store = InMemoryTokenStore();
    await store.save(accessToken: 'a', refreshToken: 'r');

    final container = _container(
      repository: FakeAuthRepository(
        profile: const MemberProfile(
          name: '김민준',
          stdId: '20250101',
          clubIds: [7],
          pushEnabled: true,
        ),
      ),
      store: store,
    );

    final state = await container.read(sessionControllerProvider.future);

    expect(state, isA<SessionReady>());
    expect((state as SessionReady).clubId, 7);
    expect(state.profile.name, '김민준');
  });

  test('토큰이 있으나 동아리가 없으면 NeedsClub', () async {
    final store = InMemoryTokenStore();
    await store.save(accessToken: 'a', refreshToken: 'r');

    final container = _container(
      repository: FakeAuthRepository(
        profile: const MemberProfile(
          name: '김민준',
          stdId: '20250101',
          clubIds: [],
          pushEnabled: true,
        ),
      ),
      store: store,
    );

    final state = await container.read(sessionControllerProvider.future);

    expect(state, isA<SessionNeedsClub>());
  });

  test('토큰이 있으나 재발급이 실패하면 SignedOut이 되고 토큰이 지워진다', () async {
    final store = InMemoryTokenStore();
    await store.save(accessToken: 'a', refreshToken: 'r');

    final container = _container(
      repository: FakeAuthRepository(refreshFails: true),
      store: store,
    );

    final state = await container.read(sessionControllerProvider.future);

    expect(state, isA<SessionSignedOut>());
    expect(await store.readAccessToken(), isNull);
  });

  test('signOut은 서버 로그아웃 후 토큰을 지운다', () async {
    final store = InMemoryTokenStore();
    await store.save(accessToken: 'a', refreshToken: 'r');
    final repository = FakeAuthRepository(
      profile: const MemberProfile(
        name: '김민준',
        stdId: '20250101',
        clubIds: [7],
        pushEnabled: true,
      ),
    );

    final container = _container(repository: repository, store: store);
    await container.read(sessionControllerProvider.future);

    await container.read(sessionControllerProvider.notifier).signOut();

    expect(repository.logoutCalls, 1);
    expect(await store.readRefreshToken(), isNull);
    expect(container.read(sessionControllerProvider).value, isA<SessionSignedOut>());
  });
}
