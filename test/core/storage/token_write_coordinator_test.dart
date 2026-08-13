import 'dart:async';

import 'package:beacon_app/core/storage/token_store.dart';
import 'package:beacon_app/core/storage/token_write_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

/// [gate]가 완료될 때까지 첫 번째 `save()` 호출만 붙잡아 둔다 — "먼저
/// 시작했지만 늦게 끝나는 쓰기"를 결정적으로 재현하기 위한 용도.
class _FirstSaveGatedStore implements TokenStore {
  _FirstSaveGatedStore(this._inner, this.gate);

  final InMemoryTokenStore _inner;
  final Future<void> gate;
  int _saveCalls = 0;

  @override
  Future<String?> readAccessToken() => _inner.readAccessToken();

  @override
  Future<String?> readRefreshToken() => _inner.readRefreshToken();

  @override
  Future<void> save({required String accessToken, required String refreshToken}) async {
    _saveCalls++;
    if (_saveCalls == 1) await gate;
    await _inner.save(accessToken: accessToken, refreshToken: refreshToken);
  }

  @override
  Future<void> clear() => _inner.clear();
}

/// 지정한 순번의 `save()`만 실패시킨다 — 실패한 쓰기가 큐 자체를 막지
/// 않는지 확인하기 위한 용도.
class _NthSaveFailsStore implements TokenStore {
  _NthSaveFailsStore(this._inner, this.failingCall);

  final InMemoryTokenStore _inner;
  final int failingCall;
  int _saveCalls = 0;

  @override
  Future<String?> readAccessToken() => _inner.readAccessToken();

  @override
  Future<String?> readRefreshToken() => _inner.readRefreshToken();

  @override
  Future<void> save({required String accessToken, required String refreshToken}) async {
    _saveCalls++;
    if (_saveCalls == failingCall) throw Exception('keystore write failed');
    await _inner.save(accessToken: accessToken, refreshToken: refreshToken);
  }

  @override
  Future<void> clear() => _inner.clear();
}

void main() {
  test('beginOperation은 세대를 하나씩 올리고 그 값을 돌려준다', () {
    final coordinator = TokenWriteCoordinator(InMemoryTokenStore());

    expect(coordinator.generation, 0);
    expect(coordinator.beginOperation(), 1);
    expect(coordinator.generation, 1);
    expect(coordinator.beginOperation(), 2);
    expect(coordinator.generation, 2);
  });

  // 큐 안의 세대 재확인이 이 파일에서 유일하게 검증되는 지점이다. 큐에
  // 들어가기 전에 한 번 확인하는 것만으로는 부족하다 — 아래처럼 앞선 쓰기를
  // 기다리는 사이에 더 최신 작업이 시작될 수 있고, 그때 이 쓰기는 이미 남의
  // 세션에 대한 것이 된다.
  test('큐에서 자기 차례가 왔을 때 세대가 이미 바뀌었으면 쓰지 않는다', () async {
    final inner = InMemoryTokenStore();
    final gate = Completer<void>();
    final coordinator = TokenWriteCoordinator(_FirstSaveGatedStore(inner, gate.future));

    final first = coordinator.beginOperation();
    final firstWrite = coordinator.save(
      first,
      accessToken: 'first-a',
      refreshToken: 'first-r',
    );
    // 첫 쓰기가 실제로 저장소에 진입해 게이트에 걸리도록 한 박자 양보한다.
    await Future<void>.delayed(Duration.zero);

    // 두 번째 작업의 쓰기는 첫 쓰기 뒤에서 대기한다.
    final second = coordinator.beginOperation();
    final secondWrite = coordinator.save(
      second,
      accessToken: 'second-a',
      refreshToken: 'second-r',
    );

    // 세 번째 작업이 시작된다 — 아직 쓰기는 없지만(예: 프로필 재조회처럼
    // 토큰을 건드리지 않는 커맨드) 세대는 이미 올라간다. 이 시점에서 큐에
    // 대기 중인 두 번째 쓰기는 낡은 것이 된다.
    coordinator.beginOperation();

    gate.complete();

    expect(await firstWrite, isTrue, reason: '자기 차례에 최신이었던 쓰기는 실제로 저장된다');
    expect(await secondWrite, isFalse, reason: '차례가 왔을 때 낡았으면 건너뛰어야 한다');
    expect(await inner.readAccessToken(), 'first-a');
    expect(await inner.readRefreshToken(), 'first-r');
  });

  test('먼저 시작했지만 늦게 끝나는 쓰기가 나중 쓰기를 덮어쓰지 않는다', () async {
    final inner = InMemoryTokenStore();
    final gate = Completer<void>();
    final coordinator = TokenWriteCoordinator(_FirstSaveGatedStore(inner, gate.future));

    // 같은 세대의 연속된 두 쓰기 — 세대 검사로는 아무것도 걸러지지 않으므로
    // 순서를 보장하는 것은 오직 큐다.
    final generation = coordinator.beginOperation();
    final firstWrite = coordinator.save(
      generation,
      accessToken: 'first-a',
      refreshToken: 'first-r',
    );
    await Future<void>.delayed(Duration.zero);
    final secondWrite = coordinator.save(
      generation,
      accessToken: 'second-a',
      refreshToken: 'second-r',
    );

    gate.complete();
    await firstWrite;
    await secondWrite;

    // 큐가 없으면 게이트에 걸렸던 첫 쓰기가 두 번째 뒤에 저장소에 닿아
    // 'first-a'가 최종값이 된다.
    expect(await inner.readAccessToken(), 'second-a');
    expect(await inner.readRefreshToken(), 'second-r');
  });

  test('쓰기 하나가 실패해도 큐가 막히지 않고 다음 쓰기가 진행된다', () async {
    final inner = InMemoryTokenStore();
    final coordinator = TokenWriteCoordinator(_NthSaveFailsStore(inner, 1));

    final failing = coordinator.beginOperation();
    await expectLater(
      coordinator.save(failing, accessToken: 'boom-a', refreshToken: 'boom-r'),
      throwsA(isA<Exception>()),
    );

    final next = coordinator.beginOperation();
    expect(
      await coordinator.save(next, accessToken: 'ok-a', refreshToken: 'ok-r'),
      isTrue,
    );
    expect(await inner.readAccessToken(), 'ok-a');
  });

  test('clear도 같은 큐와 세대 검사를 지난다', () async {
    final inner = InMemoryTokenStore();
    await inner.save(accessToken: 'a', refreshToken: 'r');
    final coordinator = TokenWriteCoordinator(inner);

    final stale = coordinator.beginOperation();
    coordinator.beginOperation();

    expect(await coordinator.clear(stale), isFalse);
    expect(await inner.readAccessToken(), 'a', reason: '낡은 clear는 지우지 않는다');

    expect(await coordinator.clear(coordinator.generation), isTrue);
    expect(await inner.readAccessToken(), isNull);
  });

  test('읽기는 저장소에 그대로 위임한다', () async {
    final inner = InMemoryTokenStore();
    await inner.save(accessToken: 'a', refreshToken: 'r');
    final coordinator = TokenWriteCoordinator(inner);

    expect(await coordinator.readAccessToken(), 'a');
    expect(await coordinator.readRefreshToken(), 'r');
  });
}
