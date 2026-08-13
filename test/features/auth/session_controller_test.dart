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
  FakeAuthRepository({
    this.profile,
    this.refreshFails = false,
    this.refreshError,
    this.fetchMeError,
    this.logoutFails = false,
  });

  MemberProfile? profile;
  bool refreshFails;
  ApiException? refreshError;
  ApiException? fetchMeError;
  bool logoutFails;
  int logoutCalls = 0;
  int refreshCalls = 0;
  int fetchMeCalls = 0;

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
    refreshCalls++;
    if (refreshError != null) throw refreshError!;
    if (refreshFails) {
      throw const ApiException(ErrorCode.refreshTokenRevoked, '무효화됨');
    }
    return const TokenResponse(accessToken: 'a2', refreshToken: 'r2');
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    if (logoutFails) {
      throw const ApiException(ErrorCode.unknown, '로그아웃 실패');
    }
  }

  @override
  Future<MemberProfile> fetchMe() async {
    fetchMeCalls++;
    if (fetchMeError != null) throw fetchMeError!;
    final value = profile;
    if (value == null) {
      throw const ApiException(ErrorCode.tokenInvalid, '토큰 없음');
    }
    return value;
  }
}

/// `readRefreshToken`/`readAccessToken`이 던지는 저장소 — 깨진 키체인/
/// 키스토어를 흉내낸다.
class ThrowingReadTokenStore implements TokenStore {
  @override
  Future<String?> readAccessToken() async => throw Exception('keystore read failed');

  @override
  Future<String?> readRefreshToken() async => throw Exception('keystore read failed');

  @override
  Future<void> save({required String accessToken, required String refreshToken}) async {}

  @override
  Future<void> clear() async {}
}

/// `clear()`만 던지는 저장소. 나머지는 내부의 [InMemoryTokenStore]에 위임한다.
class ClearFailsTokenStore implements TokenStore {
  ClearFailsTokenStore(this._inner);

  final InMemoryTokenStore _inner;

  @override
  Future<String?> readAccessToken() => _inner.readAccessToken();

  @override
  Future<String?> readRefreshToken() => _inner.readRefreshToken();

  @override
  Future<void> save({required String accessToken, required String refreshToken}) =>
      _inner.save(accessToken: accessToken, refreshToken: refreshToken);

  @override
  Future<void> clear() async => throw Exception('keystore clear failed');
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

const _profileWithClub = MemberProfile(
  name: '김민준',
  stdId: '20250101',
  clubIds: [7],
  pushEnabled: true,
);

const _profileNoClub = MemberProfile(
  name: '김민준',
  stdId: '20250101',
  clubIds: [],
  pushEnabled: true,
);

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
      repository: FakeAuthRepository(profile: _profileWithClub),
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
      repository: FakeAuthRepository(profile: _profileNoClub),
      store: store,
    );

    final state = await container.read(sessionControllerProvider.future);

    expect(state, isA<SessionNeedsClub>());
  });

  test('토큰이 있으나 재발급이 실패(자격 증명 오류)하면 SignedOut이 되고 토큰이 지워진다', () async {
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
    final repository = FakeAuthRepository(profile: _profileWithClub);

    final container = _container(repository: repository, store: store);
    await container.read(sessionControllerProvider.future);

    await container.read(sessionControllerProvider.notifier).signOut();

    expect(repository.logoutCalls, 1);
    expect(await store.readRefreshToken(), isNull);
    expect(container.read(sessionControllerProvider).value, isA<SessionSignedOut>());
  });

  group('오류 분류 — 자격 증명 오류 vs 일시적 실패', () {
    test('인증 관련 오류(TOKEN_INVALID)는 토큰을 지우고 SignedOut이 된다', () async {
      final store = InMemoryTokenStore();
      await store.save(accessToken: 'a', refreshToken: 'r');
      final container = _container(
        repository: FakeAuthRepository(
          refreshError: const ApiException(ErrorCode.tokenInvalid, '토큰 무효'),
        ),
        store: store,
      );

      final state = await container.read(sessionControllerProvider.future);

      expect(state, isA<SessionSignedOut>());
      expect(await store.readRefreshToken(), isNull);
    });

    test('네트워크 오류는 토큰을 지우지 않고 SessionUnavailable이 된다', () async {
      final store = InMemoryTokenStore();
      await store.save(accessToken: 'a', refreshToken: 'r');
      final container = _container(
        repository: FakeAuthRepository(
          refreshError: const ApiException(ErrorCode.network, '연결 실패'),
        ),
        store: store,
      );

      final state = await container.read(sessionControllerProvider.future);

      expect(state, isA<SessionUnavailable>());
      expect(await store.readRefreshToken(), 'r');
      expect(await store.readAccessToken(), 'a');
    });

    test('refresh는 성공했지만 fetchMe가 서버 오류(5xx)면 새로 저장된 토큰을 지우지 않는다', () async {
      final store = InMemoryTokenStore();
      await store.save(accessToken: 'a', refreshToken: 'r');
      final container = _container(
        repository: FakeAuthRepository(
          fetchMeError: const ApiException(ErrorCode.unknown, '서버 오류', statusCode: 500),
        ),
        store: store,
      );

      final state = await container.read(sessionControllerProvider.future);

      expect(state, isA<SessionUnavailable>());
      // refresh 자체는 성공했으므로 새 토큰(a2/r2)이 저장돼 있어야 한다.
      expect(await store.readAccessToken(), 'a2');
      expect(await store.readRefreshToken(), 'r2');
    });

    test('토큰 저장소 읽기가 예외를 던져도 build()는 실패하지 않고 SessionUnavailable로 알린다', () async {
      final container = _container(
        repository: FakeAuthRepository(),
        store: ThrowingReadTokenStore(),
      );

      final state = await container.read(sessionControllerProvider.future);

      expect(state, isA<SessionUnavailable>());
      expect(container.read(sessionControllerProvider).hasError, isFalse);
    });
  });

  group('onAuthenticated', () {
    test('토큰을 저장하고 동아리가 있으면 Ready가 된다', () async {
      final store = InMemoryTokenStore();
      final repository = FakeAuthRepository(profile: _profileWithClub);
      final container = _container(repository: repository, store: store);
      await container.read(sessionControllerProvider.future);

      await container
          .read(sessionControllerProvider.notifier)
          .onAuthenticated(const TokenResponse(accessToken: 'a', refreshToken: 'r'));

      final state = container.read(sessionControllerProvider).value;
      expect(state, isA<SessionReady>());
      expect(await store.readAccessToken(), 'a');
      expect(await store.readRefreshToken(), 'r');
    });

    test('동아리가 없으면 NeedsClub이 된다', () async {
      final store = InMemoryTokenStore();
      final repository = FakeAuthRepository(profile: _profileNoClub);
      final container = _container(repository: repository, store: store);
      await container.read(sessionControllerProvider.future);

      await container
          .read(sessionControllerProvider.notifier)
          .onAuthenticated(const TokenResponse(accessToken: 'a', refreshToken: 'r'));

      expect(container.read(sessionControllerProvider).value, isA<SessionNeedsClub>());
    });

    test('토큰 저장 후 fetchMe가 실패해도 저장된 토큰은 유지되고 SessionUnavailable이 된다', () async {
      final store = InMemoryTokenStore();
      final repository = FakeAuthRepository(
        fetchMeError: const ApiException(ErrorCode.unknown, '서버 오류', statusCode: 500),
      );
      final container = _container(repository: repository, store: store);
      await container.read(sessionControllerProvider.future);

      await container
          .read(sessionControllerProvider.notifier)
          .onAuthenticated(const TokenResponse(accessToken: 'a', refreshToken: 'r'));

      expect(container.read(sessionControllerProvider).value, isA<SessionUnavailable>());
      expect(await store.readAccessToken(), 'a');
    });
  });

  test('refreshProfile은 최신 프로필로 상태를 갱신한다', () async {
    final store = InMemoryTokenStore();
    await store.save(accessToken: 'a', refreshToken: 'r');
    final repository = FakeAuthRepository(profile: _profileNoClub);
    final container = _container(repository: repository, store: store);

    final initial = await container.read(sessionControllerProvider.future);
    expect(initial, isA<SessionNeedsClub>());

    repository.profile = _profileWithClub;
    await container.read(sessionControllerProvider.notifier).refreshProfile();

    final state = container.read(sessionControllerProvider).value;
    expect(state, isA<SessionReady>());
    expect((state as SessionReady).clubId, 7);
  });

  group('signOut의 부분 실패', () {
    test('서버 로그아웃이 실패해도 로컬 세션은 정리된다', () async {
      final store = InMemoryTokenStore();
      await store.save(accessToken: 'a', refreshToken: 'r');
      final repository = FakeAuthRepository(profile: _profileWithClub, logoutFails: true);
      final container = _container(repository: repository, store: store);
      await container.read(sessionControllerProvider.future);

      await container.read(sessionControllerProvider.notifier).signOut();

      expect(repository.logoutCalls, 1);
      expect(await store.readRefreshToken(), isNull);
      expect(container.read(sessionControllerProvider).value, isA<SessionSignedOut>());
    });

    test('토큰 저장소 정리가 실패해도 상태는 SignedOut으로 반영된다', () async {
      final store = InMemoryTokenStore();
      await store.save(accessToken: 'a', refreshToken: 'r');
      final failingStore = ClearFailsTokenStore(store);
      final repository = FakeAuthRepository(profile: _profileWithClub);
      final container = _container(repository: repository, store: failingStore);
      await container.read(sessionControllerProvider.future);

      await container.read(sessionControllerProvider.notifier).signOut();

      expect(container.read(sessionControllerProvider).value, isA<SessionSignedOut>());
    });
  });

  test('sessionExpiredProvider가 증가하면 세션을 다시 판별한다', () async {
    final store = InMemoryTokenStore();
    await store.save(accessToken: 'a', refreshToken: 'r');
    final repository = FakeAuthRepository(profile: _profileWithClub);
    final container = _container(repository: repository, store: store);

    await container.read(sessionControllerProvider.future);
    expect(repository.refreshCalls, 1);

    container.read(sessionExpiredProvider.notifier).state++;
    await container.read(sessionControllerProvider.future);

    expect(repository.refreshCalls, 2);
  });
}
