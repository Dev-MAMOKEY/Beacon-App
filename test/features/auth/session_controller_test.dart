import 'dart:async';

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

  /// 설정되면 `refresh()`가 이 Completer가 완료될 때까지 멈춘다 — 실제
  /// 경쟁 상태(진행 중인 판별)를 재현하기 위한 용도.
  Completer<TokenResponse>? refreshGate;

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
    final gate = refreshGate;
    if (gate != null) return gate.future;
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

/// 가장 먼저 들어온 `save()` 호출만 [firstSaveGate]가 완료될 때까지 멈춘다.
/// 이후 호출은 즉시 진행한다 — "먼저 시작했지만 늦게 끝나는 쓰기"를
/// 재현하기 위한 용도. 나머지는 내부의 [InMemoryTokenStore]에 위임한다.
class FirstSaveGatedTokenStore implements TokenStore {
  FirstSaveGatedTokenStore(this._inner, this.firstSaveGate);

  final InMemoryTokenStore _inner;
  final Future<void> firstSaveGate;
  int _saveCalls = 0;

  @override
  Future<String?> readAccessToken() => _inner.readAccessToken();

  @override
  Future<String?> readRefreshToken() => _inner.readRefreshToken();

  @override
  Future<void> save({required String accessToken, required String refreshToken}) async {
    _saveCalls++;
    if (_saveCalls == 1) {
      await firstSaveGate;
    }
    await _inner.save(accessToken: accessToken, refreshToken: refreshToken);
  }

  @override
  Future<void> clear() => _inner.clear();
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

    // 실 백엔드(/v3/api-docs)에서 확인한 /auth/refresh의 세 401 코드와
    // MEMBER_NOT_FOUND(404) 각각을 개별로 핀 고정한다 — authFailureCodes에서
    // 하나라도 빠지면(오타·실수로 삭제) 이 중 하나가 조용히 SessionUnavailable로
    // 새면서 사용자가 재시도해도 절대 풀리지 않는 화면에 갇힌다.
    for (final code in [
      ErrorCode.refreshTokenExpired,
      ErrorCode.refreshTokenInvalid,
      ErrorCode.refreshTokenRevoked,
      ErrorCode.memberNotFound,
    ]) {
      test('리프레시가 ${code.wire}로 실패하면 SignedOut이 되고 토큰이 지워진다', () async {
        final store = InMemoryTokenStore();
        await store.save(accessToken: 'a', refreshToken: 'r');
        final container = _container(
          repository: FakeAuthRepository(
            refreshError: ApiException(code, '실패: ${code.wire}'),
          ),
          store: store,
        );

        final state = await container.read(sessionControllerProvider.future);

        expect(state, isA<SessionSignedOut>());
        expect(await store.readAccessToken(), isNull);
        expect(await store.readRefreshToken(), isNull);
      });
    }

    // 실 백엔드는 MEMBER_NOT_FOUND를 404로 내려준다. 컨트롤러와 인터셉터가
    // 같은 판정(isAuthFailure)을 쓰는지 양쪽에서 각각 고정한다 — 인터셉터
    // 쪽 짝은 auth_interceptor_test의 '재발급이 404 MEMBER_NOT_FOUND로
    // 실패하면...' 이다.
    test('리프레시가 404 MEMBER_NOT_FOUND로 실패해도 SignedOut이 되고 토큰이 지워진다', () async {
      final store = InMemoryTokenStore();
      await store.save(accessToken: 'a', refreshToken: 'r');
      final container = _container(
        repository: FakeAuthRepository(
          refreshError: const ApiException(
            ErrorCode.memberNotFound,
            '해당 회원이 존재하지 않습니다.',
            statusCode: 404,
          ),
        ),
        store: store,
      );

      final state = await container.read(sessionControllerProvider.future);

      expect(state, isA<SessionSignedOut>());
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    });

    test('code를 읽지 못한 401 응답은 상태 코드만으로 SignedOut이 된다', () async {
      // ApiClient는 래퍼가 아닌 바디(프록시 HTML 등)를 ErrorCode.unknown +
      // statusCode로 감싸 올려보낸다. 코드를 읽을 수 없을 때 401 자체는
      // "자격 증명이 거부됐다"는 충분한 증거이고, 인터셉터도 같은 판정을
      // 한다 — 여기서 SessionUnavailable로 두면 두 곳이 어긋난다.
      final store = InMemoryTokenStore();
      await store.save(accessToken: 'a', refreshToken: 'r');
      final container = _container(
        repository: FakeAuthRepository(
          refreshError: const ApiException(
            ErrorCode.unknown,
            '서버 응답을 처리하지 못했습니다.',
            statusCode: 401,
          ),
        ),
        store: store,
      );

      final state = await container.read(sessionControllerProvider.future);

      expect(state, isA<SessionSignedOut>());
      expect(await store.readRefreshToken(), isNull);
    });

    test('code를 읽지 못한 500 응답은 SessionUnavailable로 남고 토큰을 지우지 않는다', () async {
      final store = InMemoryTokenStore();
      await store.save(accessToken: 'a', refreshToken: 'r');
      final container = _container(
        repository: FakeAuthRepository(
          refreshError: const ApiException(
            ErrorCode.unknown,
            '서버 응답을 처리하지 못했습니다.',
            statusCode: 500,
          ),
        ),
        store: store,
      );

      final state = await container.read(sessionControllerProvider.future);

      expect(state, isA<SessionUnavailable>());
      expect(await store.readRefreshToken(), 'r');
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

    // 리뷰에서 뒤집힌 결정: 로그인 직후라도 fetchMe가 자격-증명-죽음 코드로
    // 실패하면(MEMBER_NOT_FOUND 등) 재시도로 절대 복구되지 않는다 — 방금
    // 발급된 토큰이 만료됐을 리 없고, 그 계정 자체가 없다는 뜻이기 때문이다.
    // SessionUnavailable로 두면 사용자를 영원히 풀리지 않는 재시도 화면에
    // 가둔다. _resolve()/refreshProfile()과 같은 분류를 적용해야 한다.
    test('fetchMe가 자격-증명-죽음 오류(MEMBER_NOT_FOUND)면 토큰을 지우고 SignedOut이 된다', () async {
      final store = InMemoryTokenStore();
      final repository = FakeAuthRepository(
        fetchMeError: const ApiException(ErrorCode.memberNotFound, '해당 회원이 존재하지 않습니다.'),
      );
      final container = _container(repository: repository, store: store);
      await container.read(sessionControllerProvider.future);

      await container
          .read(sessionControllerProvider.notifier)
          .onAuthenticated(const TokenResponse(accessToken: 'a', refreshToken: 'r'));

      expect(container.read(sessionControllerProvider).value, isA<SessionSignedOut>());
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
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

  group('실제 경쟁 상태 — Completer로 겹치는 순서를 직접 재현한다', () {
    test('진행 중인 판별이 있어도 signOut이 이기고, 뒤늦게 끝난 판별은 토큰을 되살리지 않는다', () async {
      final store = InMemoryTokenStore();
      await store.save(accessToken: 'a', refreshToken: 'r');
      final refreshGate = Completer<TokenResponse>();
      final repository = FakeAuthRepository(profile: _profileWithClub)
        ..refreshGate = refreshGate;
      final container = _container(repository: repository, store: store);

      // build()를 시작만 시킨다 — refresh()가 게이트에 걸려 끝나지 않는다.
      container.read(sessionControllerProvider);
      await Future<void>.delayed(Duration.zero);
      expect(repository.refreshCalls, 1, reason: '판별이 refresh() 호출까지는 진행돼 있어야 한다');
      expect(container.read(sessionControllerProvider).isLoading, isTrue);

      // 판별이 진행 중인 상태에서 로그아웃한다.
      await container.read(sessionControllerProvider.notifier).signOut();

      expect(container.read(sessionControllerProvider).value, isA<SessionSignedOut>());
      expect(await store.readRefreshToken(), isNull);
      expect(await store.readAccessToken(), isNull);

      // 이제 막혀 있던 refresh()를 풀어 낡은 판별이 뒤늦게 끝나게 한다.
      refreshGate.complete(const TokenResponse(accessToken: 'stale-a', refreshToken: 'stale-r'));
      // 낡은 _resolve()가 이어서(원래대로라면 save→fetchMe→_settle까지) 완전히
      // 흘러갈 시간을 준다.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // 낡은 판별이 토큰을 되살리지 않았어야 한다.
      expect(await store.readRefreshToken(), isNull);
      expect(await store.readAccessToken(), isNull);
      // 낡은 판별이 SessionReady를 다시 발행하지 않았어야 한다.
      expect(container.read(sessionControllerProvider).value, isA<SessionSignedOut>());
    });

    test('연속 로그인 — 먼저 시작했지만 늦게 끝나는 저장이 나중 로그인의 토큰을 덮어쓰지 않는다', () async {
      final store = InMemoryTokenStore();
      final firstSaveGate = Completer<void>();
      final gatedStore = FirstSaveGatedTokenStore(store, firstSaveGate.future);
      final repository = FakeAuthRepository(profile: _profileWithClub);
      final container = _container(repository: repository, store: gatedStore);
      await container.read(sessionControllerProvider.future); // 초기 SignedOut 판별

      final notifier = container.read(sessionControllerProvider.notifier);

      // 첫 번째 로그인 — save()가 게이트에 걸려 끝나지 않는다.
      final first = notifier.onAuthenticated(
        const TokenResponse(accessToken: 'first-a', refreshToken: 'first-r'),
      );
      await Future<void>.delayed(Duration.zero); // 첫 save() 호출이 시작되도록 양보

      // 두 번째 로그인 — 첫 번째가 아직 끝나지 않은 상태에서 겹쳐 들어온다.
      final second = notifier.onAuthenticated(
        const TokenResponse(accessToken: 'second-a', refreshToken: 'second-r'),
      );

      // 첫 번째 저장을 풀어준다. 큐가 없다면(수정 전) 첫 번째 save()가
      // 두 번째 것보다 늦게 저장소에 닿아 second의 토큰을 덮어쓸 수 있다.
      firstSaveGate.complete();

      await first;
      await second;

      expect(await store.readAccessToken(), 'second-a');
      expect(await store.readRefreshToken(), 'second-r');
      expect(container.read(sessionControllerProvider).value, isA<SessionReady>());
    });
  });
}
