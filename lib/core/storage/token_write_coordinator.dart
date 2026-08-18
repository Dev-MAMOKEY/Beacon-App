import 'token_store.dart';

/// 토큰 저장소에 대한 **모든** 쓰기가 지나가는 한 곳. `SessionController`와
/// `AuthInterceptor`가 같은 인스턴스를 공유하므로 "모든 토큰 쓰기는
/// 직렬화되고 세대 검사를 거친다"가 관례가 아니라 구조로 보장된다.
///
/// 예전에는 큐와 세대 카운터가 SessionController 안에만 있었고
/// AuthInterceptor는 [TokenStore]를 직접 붙잡고 save/clear를 불렀다. 그래서
/// 두 가지가 실제로 깨졌다:
/// - 재발급이 진행 중일 때 로그아웃하면, 로그아웃이 지운 자리에 재발급이
///   회전된 토큰을 뒤늦게 덮어썼다 — 화면은 로그아웃인데 자격 증명은
///   디스크에 남았다.
/// - 옛 재발급 flight가 실패하는 사이 사용자가 새로 로그인하면, 옛 flight의
///   clear()가 새 사용자의 토큰을 지우고 만료 콜백까지 불러 방금 로그인한
///   사용자를 다시 로그인 화면으로 밀어냈다.
///
/// 읽기까지 여기서 위임하는 이유는, 그래야 인터셉터가 [TokenStore] 자체를
/// 들고 있지 않게 되고 큐를 우회하는 쓰기 경로가 애초에 존재하지 않기
/// 때문이다.
class TokenWriteCoordinator {
  TokenWriteCoordinator(this._store);

  final TokenStore _store;

  int _generation = 0;
  Future<void> _queue = Future<void>.value();

  /// 지금 유효한 세대. 재발급 flight처럼 "새 작업을 시작하는 것은 아니지만
  /// 자기가 시작된 시점을 기억해야 하는" 쪽이 이 값을 캡처해 뒀다가
  /// [save]/[clear]에 그대로 넘긴다.
  int get generation => _generation;

  /// 새 세션 작업(판별/로그인/프로필 갱신/로그아웃)의 시작을 알리고 그
  /// 세대를 돌려준다. 이 호출 이전에 시작된 작업의 쓰기는 큐에서 자기 차례가
  /// 와도 건너뛰어진다.
  int beginOperation() => ++_generation;

  Future<String?> readAccessToken() => _store.readAccessToken();

  Future<String?> readRefreshToken() => _store.readRefreshToken();

  /// [generation]이 자기 차례에도 여전히 최신일 때만 실제로 저장한다.
  /// 저장했으면 true, 이미 낡아서 건너뛰었으면 false.
  Future<bool> save(
    int generation, {
    required String accessToken,
    required String refreshToken,
  }) {
    return _enqueue(
      generation,
      () => _store.save(accessToken: accessToken, refreshToken: refreshToken),
    );
  }

  /// [generation]이 자기 차례에도 여전히 최신일 때만 실제로 지운다.
  /// 지웠으면 true, 이미 낡아서 건너뛰었으면 false.
  Future<bool> clear(int generation) => _enqueue(generation, _store.clear);

  /// [write]를 큐에 이어붙인다. 앞선 쓰기가 전부 끝나고 자기 차례가 됐을 때
  /// 세대를 **다시** 확인한다 — 큐에 넣기 전에 한 번 확인하는 것만으로는
  /// 부족하다. 기다리는 동안 더 최신 작업이 시작될 수 있고, 그러면 이 쓰기는
  /// 이미 남의 세션에 대한 것이 되기 때문이다. 세대 검사만 있고 큐가 없으면
  /// 반대로 "호출은 막지 못하고 결과 반영만 막는" 반쪽 방어가 된다 — 늦게
  /// 시작한 쓰기가 먼저 끝나고 먼저 시작한 쓰기가 나중에 끝나 저장소를 조용히
  /// 되돌릴 수 있다. 둘이 함께 있어야 "나중에 큐에 들어온 쓰기가 항상
  /// 마지막에 저장소에 닿는다"가 성립한다.
  ///
  /// 개별 쓰기가 실패해도 큐 자체는 막히지 않도록, 다음 쓰기가 이어붙을
  /// 채널은 항상 정상 완료 상태로 유지한다.
  Future<bool> _enqueue(int generation, Future<void> Function() write) {
    final scheduled = _queue.then((_) async {
      if (generation != _generation) return false;
      await write();
      return true;
    });
    _queue = scheduled.then((_) {}, onError: (_) {});
    return scheduled;
  }
}
