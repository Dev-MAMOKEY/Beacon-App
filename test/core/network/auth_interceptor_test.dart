import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:beacon_app/core/network/auth_interceptor.dart';
import 'package:beacon_app/core/storage/token_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// `http_mock_adapter`의 `onGet`/`onPost` 콜백은 요청마다가 아니라 등록 시점에
/// 딱 한 번만 실행되기 때문에 "1차 실패, 2차 성공" 같은 순서 의존 시나리오를
/// 표현할 수 없다. 이 파일은 순서·동시성 검증이 필요하므로, 직접 만든 이
/// 소형 어댑터로 대체한다. 요청 내용(헤더 등)을 조건으로 응답을 고르고,
/// 경로별 호출 횟수를 센다. `holdUntil`을 주면 응답을 특정 시점까지 붙들어
/// 둘 수 있고, `waitForCalls`로 "몇 번째 호출이 도착했는가"를 타이밍 운
/// 없이 기다릴 수 있다 — 동시성 테스트를 스케줄링 우연에 맡기지 않기
/// 위해서다.
class _ScriptedAdapter implements HttpClientAdapter {
  final List<_Rule> _rules = [];
  final Map<String, int> _callCounts = {};
  final Map<String, List<MapEntry<int, Completer<void>>>> _callWaiters = {};

  void on(
    String method,
    String path, {
    bool Function(RequestOptions options)? when,
    required int statusCode,
    required Object? Function(RequestOptions options) body,
    Future<void>? holdUntil,
  }) {
    _rules.add(_Rule(method, path, when, statusCode, body, holdUntil));
  }

  int callsTo(String method, String path) => _callCounts['$method $path'] ?? 0;

  /// [count]번째 `method path` 호출이 어댑터에 "도착"하는 순간(응답을
  /// 만들거나 `holdUntil`을 기다리기 전) 완료되는 Future를 돌려준다.
  Future<void> waitForCalls(String method, String path, int count) {
    final key = '$method $path';
    if ((_callCounts[key] ?? 0) >= count) return Future.value();
    final completer = Completer<void>();
    _callWaiters.putIfAbsent(key, () => []).add(MapEntry(count, completer));
    return completer.future;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key = '${options.method} ${options.path}';
    final newCount = (_callCounts[key] ?? 0) + 1;
    _callCounts[key] = newCount;
    final waiters = _callWaiters[key];
    if (waiters != null) {
      waiters.removeWhere((entry) {
        if (newCount >= entry.key) {
          entry.value.complete();
          return true;
        }
        return false;
      });
    }

    for (final rule in _rules) {
      final matches = rule.method == options.method &&
          rule.path == options.path &&
          (rule.when?.call(options) ?? true);
      if (matches) {
        if (rule.holdUntil != null) {
          await rule.holdUntil;
        }
        return ResponseBody.fromString(
          jsonEncode(rule.body(options)),
          rule.statusCode,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
    }
    throw StateError('No scripted response for $key');
  }

  @override
  void close({bool force = false}) {}
}

class _Rule {
  _Rule(this.method, this.path, this.when, this.statusCode, this.body, this.holdUntil);

  final String method;
  final String path;
  final bool Function(RequestOptions options)? when;
  final int statusCode;
  final Object? Function(RequestOptions options) body;
  final Future<void>? holdUntil;
}

/// [callNumber]번째(1-indexed) `readAccessToken()` 호출을 지정한 게이트가
/// 완료될 때까지 붙잡아 둔다. 값 자체는 그 호출이 "시작되는" 시점에 캡처된
/// 스냅샷이다 — 트랜잭션 격리가 없는 실제 저장소에서 느린 읽기가 동시
/// 쓰기와 경합할 때, 읽기가 시작된 시점의 값을 나중에 돌려주는 상황을
/// 결정적으로 재현하기 위한 테스트 더블이다. `save()` 완료 시점도 신호로
/// 노출한다 — 테스트가 "다른 flight가 실제로 저장까지 마쳤다"를 추측이
/// 아니라 사실로 기다릴 수 있게 한다.
class _RaceableTokenStore implements TokenStore {
  _RaceableTokenStore(this._inner);

  final InMemoryTokenStore _inner;

  int _accessReadCount = 0;
  int? _delayAt;
  Future<void>? _gate;
  Completer<void>? _readStarted;

  Completer<void>? _nextSaveSignal;

  /// [callNumber]번째 `readAccessToken()` 호출을 [gate]로 지연시킨다.
  /// 반환하는 Future는 그 호출이 스냅샷을 캡처하고 게이트를 기다리기
  /// 시작하는 순간에 완료된다.
  Future<void> delayAccessReadCall(int callNumber, Future<void> gate) {
    _delayAt = callNumber;
    _gate = gate;
    final started = Completer<void>();
    _readStarted = started;
    return started.future;
  }

  /// 다음 `save()` 호출이 끝나면 완료되는 Future를 돌려준다.
  Future<void> waitForNextSave() {
    final completer = Completer<void>();
    _nextSaveSignal = completer;
    return completer.future;
  }

  @override
  Future<String?> readAccessToken() async {
    _accessReadCount++;
    final snapshot = await _inner.readAccessToken();
    if (_accessReadCount == _delayAt) {
      final gate = _gate!;
      _delayAt = null;
      _gate = null;
      _readStarted?.complete();
      _readStarted = null;
      await gate;
    }
    return snapshot;
  }

  @override
  Future<String?> readRefreshToken() => _inner.readRefreshToken();

  @override
  Future<void> save({required String accessToken, required String refreshToken}) async {
    await _inner.save(accessToken: accessToken, refreshToken: refreshToken);
    _nextSaveSignal?.complete();
    _nextSaveSignal = null;
  }

  @override
  Future<void> clear() => _inner.clear();
}

void main() {
  late InMemoryTokenStore store;
  late Dio dio;
  late _ScriptedAdapter adapter;
  late int expiredCallbackCount;

  setUp(() async {
    store = InMemoryTokenStore();
    await store.save(accessToken: 'old-access', refreshToken: 'refresh-1');

    dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    adapter = _ScriptedAdapter();
    dio.httpClientAdapter = adapter;

    expiredCallbackCount = 0;
    dio.interceptors.add(
      AuthInterceptor(
        store: store,
        dio: dio,
        onSessionExpired: () => expiredCallbackCount++,
      ),
    );
  });

  test('요청에 Authorization 헤더를 붙인다', () async {
    adapter.on('GET', '/me', statusCode: 200, body: (_) => {'success': true, 'data': null});

    final response = await dio.get<Object?>('/me');

    expect(response.requestOptions.headers['Authorization'], 'Bearer old-access');
  });

  test('401을 받으면 재발급 후 원요청을 새 토큰으로 재시도한다', () async {
    adapter.on(
      'POST',
      '/auth/refresh',
      statusCode: 200,
      body: (_) => {
        'success': true,
        'data': {'accessToken': 'new-access', 'refreshToken': 'refresh-2'},
      },
    );
    adapter.on(
      'GET',
      '/me',
      when: (o) => o.headers['Authorization'] == 'Bearer old-access',
      statusCode: 401,
      body: (_) => {
        'success': false,
        'data': null,
        'error': {'code': 'TOKEN_EXPIRED', 'message': '만료'},
      },
    );
    adapter.on(
      'GET',
      '/me',
      when: (o) => o.headers['Authorization'] == 'Bearer new-access',
      statusCode: 200,
      body: (_) => {'success': true, 'data': {'name': '김민준'}},
    );

    final response = await dio.get<Object?>('/me');

    expect((response.data! as Map)['success'], true);
    expect(await store.readAccessToken(), 'new-access');
    expect(await store.readRefreshToken(), 'refresh-2');
    expect(expiredCallbackCount, 0);
    expect(adapter.callsTo('GET', '/me'), 2);
    expect(adapter.callsTo('POST', '/auth/refresh'), 1);
  });

  test('재발급이 실패하면 토큰을 지우고 만료 콜백을 부른다', () async {
    adapter.on(
      'POST',
      '/auth/refresh',
      statusCode: 401,
      body: (_) => {
        'success': false,
        'data': null,
        'error': {'code': 'REFRESH_TOKEN_REVOKED', 'message': '무효화됨'},
      },
    );
    adapter.on(
      'GET',
      '/me',
      statusCode: 401,
      body: (_) => {
        'success': false,
        'data': null,
        'error': {'code': 'TOKEN_EXPIRED', 'message': '만료'},
      },
    );

    await expectLater(dio.get<Object?>('/me'), throwsA(isA<DioException>()));

    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
    expect(expiredCallbackCount, 1);
  });

  test('저장된 refresh token이 없으면 재발급을 시도하지 않는다', () async {
    await store.clear();
    adapter.on(
      'GET',
      '/me',
      statusCode: 401,
      body: (_) => {
        'success': false,
        'data': null,
        'error': {'code': 'TOKEN_MISSING', 'message': '없음'},
      },
    );

    await expectLater(dio.get<Object?>('/me'), throwsA(isA<DioException>()));

    expect(expiredCallbackCount, 1);
    expect(adapter.callsTo('POST', '/auth/refresh'), 0);
  });

  test('auth 엔드포인트 판별은 경로의 마지막 두 세그먼트를 정확히 비교한다', () async {
    // '/auth/login'을 부분 문자열로 포함하지만 실제 auth 엔드포인트가 아닌
    // 경로는 예외 대상이 아니어야 한다 — 401을 받으면 정상적으로 재발급을
    // 시도해야 한다.
    adapter.on(
      'GET',
      '/reports/auth/login-attempts',
      when: (o) => o.headers['Authorization'] == 'Bearer old-access',
      statusCode: 401,
      body: (_) => {
        'success': false,
        'data': null,
        'error': {'code': 'TOKEN_EXPIRED', 'message': '만료'},
      },
    );
    adapter.on(
      'GET',
      '/reports/auth/login-attempts',
      when: (o) => o.headers['Authorization'] == 'Bearer new-access',
      statusCode: 200,
      body: (_) => {'success': true, 'data': null},
    );
    adapter.on(
      'POST',
      '/auth/refresh',
      statusCode: 200,
      body: (_) => {
        'success': true,
        'data': {'accessToken': 'new-access', 'refreshToken': 'refresh-2'},
      },
    );

    final response = await dio.get<Object?>('/reports/auth/login-attempts');

    expect((response.data! as Map)['success'], true);
    expect(adapter.callsTo('POST', '/auth/refresh'), 1);

    // 진짜 auth 엔드포인트는 401을 받아도 재발급을 시도하지 않고 에러를
    // 그대로 던진다.
    adapter.on(
      'POST',
      '/auth/login',
      statusCode: 401,
      body: (_) => {
        'success': false,
        'data': null,
        'error': {'code': 'INVALID_CREDENTIALS', 'message': '틀림'},
      },
    );

    await expectLater(dio.post<Object?>('/auth/login', data: {}), throwsA(isA<DioException>()));

    expect(
      adapter.callsTo('POST', '/auth/refresh'),
      1,
      reason: 'login 실패는 재발급을 유발하면 안 된다',
    );

    // 앞에 '/'가 없는 상대 경로도 똑같이 진짜 auth 엔드포인트로 인식해야
    // 한다 — Uri.parse의 pathSegments는 선행 슬래시 유무와 무관하게 같은
    // 세그먼트를 만들어준다.
    adapter.on(
      'POST',
      'auth/login',
      statusCode: 401,
      body: (_) => {
        'success': false,
        'data': null,
        'error': {'code': 'INVALID_CREDENTIALS', 'message': '틀림'},
      },
    );

    await expectLater(dio.post<Object?>('auth/login', data: {}), throwsA(isA<DioException>()));

    expect(
      adapter.callsTo('POST', '/auth/refresh'),
      1,
      reason: '선행 슬래시가 없는 auth/login도 재발급을 유발하면 안 된다',
    );
  });

  test('동시에 여러 요청이 401을 받아도 재발급은 한 번만 일어난다', () async {
    // refresh 응답을 게이트가 열릴 때까지 붙들어 둔다. "세 요청 모두가
    // 재발급 여부를 결정하는 지점(= old-access로 /me를 두드려 401을 받는
    // 지점)에 도달했다"와 "재발급 호출이 실제로 나갔다"를 각각
    // `waitForCalls`로 명시적으로 확인한 뒤에만 게이트를 연다 — 이벤트
    // 큐를 몇 바퀴 돌리면 다 끝났을 거라는 추측(pumpEventQueue는 "완전히
    // 비웠다"를 보장하지 않는다)에 기대지 않는다.
    final refreshGate = Completer<void>();
    adapter.on(
      'POST',
      '/auth/refresh',
      statusCode: 200,
      holdUntil: refreshGate.future,
      body: (_) => {
        'success': true,
        'data': {'accessToken': 'new-access', 'refreshToken': 'refresh-2'},
      },
    );
    adapter.on(
      'GET',
      '/me',
      when: (o) => o.headers['Authorization'] == 'Bearer old-access',
      statusCode: 401,
      body: (_) => {
        'success': false,
        'data': null,
        'error': {'code': 'TOKEN_EXPIRED', 'message': '만료'},
      },
    );
    adapter.on(
      'GET',
      '/me',
      when: (o) => o.headers['Authorization'] == 'Bearer new-access',
      statusCode: 200,
      body: (_) => {'success': true, 'data': null},
    );

    final threeReached401 = adapter.waitForCalls('GET', '/me', 3);
    final refreshArrived = adapter.waitForCalls('POST', '/auth/refresh', 1);

    final responsesFuture = Future.wait([
      dio.get<Object?>('/me'),
      dio.get<Object?>('/me'),
      dio.get<Object?>('/me'),
    ]);

    await Future.wait([threeReached401, refreshArrived]);
    expect(
      adapter.callsTo('POST', '/auth/refresh'),
      1,
      reason: '세 요청 모두 결정 지점에 도달했는데도 실제 재발급 호출은 하나여야 한다',
    );

    refreshGate.complete();
    final responses = await responsesFuture;

    expect(adapter.callsTo('POST', '/auth/refresh'), 1);
    for (final response in responses) {
      expect((response.data! as Map)['success'], true);
    }
    expect(expiredCallbackCount, 0);
  });

  test(
    '경쟁으로 불필요한 재발급 flight가 새로 시작돼도, 이미 회전된 토큰을 발견하면 네트워크를 타지 않고 즉시 반환한다',
    () async {
      final inner = InMemoryTokenStore();
      await inner.save(accessToken: 'old-access', refreshToken: 'refresh-1');
      final raceStore = _RaceableTokenStore(inner);

      final localDio = Dio(BaseOptions(baseUrl: 'http://test.local'));
      final localAdapter = _ScriptedAdapter();
      localDio.httpClientAdapter = localAdapter;
      var localExpired = 0;
      localDio.interceptors.add(
        AuthInterceptor(
          store: raceStore,
          dio: localDio,
          onSessionExpired: () => localExpired++,
        ),
      );

      var refresh1Used = false;
      var rejectedRefreshAttempts = 0;
      // refresh-1은 딱 한 번만 성공해야 한다 — 서버가 토큰을 회전시키는
      // 것을 흉내낸다. 그 외의 모든 재발급 시도(예: 이미 회전된 refresh-2로
      // 또 시도하는 것)는 "일시적인 서버 문제"를 흉내내 실패시킨다 — 그런
      // 불필요한 재시도가 애초에 나가지 않아야 한다는 것이 이 테스트의
      // 요지다.
      localAdapter.on(
        'POST',
        '/auth/refresh',
        when: (o) => (o.data as Map)['refreshToken'] == 'refresh-1' && !refresh1Used,
        statusCode: 200,
        body: (_) {
          refresh1Used = true;
          return {
            'success': true,
            'data': {'accessToken': 'new-access', 'refreshToken': 'refresh-2'},
          };
        },
      );
      localAdapter.on(
        'POST',
        '/auth/refresh',
        statusCode: 401,
        body: (_) {
          rejectedRefreshAttempts++;
          return {
            'success': false,
            'data': null,
            'error': {'code': 'SERVER_HICCUP', 'message': '일시적 오류'},
          };
        },
      );
      for (final path in ['/a', '/b']) {
        localAdapter.on(
          'GET',
          path,
          when: (o) => o.headers['Authorization'] == 'Bearer old-access',
          statusCode: 401,
          body: (_) => {
            'success': false,
            'data': null,
            'error': {'code': 'TOKEN_EXPIRED', 'message': '만료'},
          },
        );
        localAdapter.on(
          'GET',
          path,
          when: (o) => o.headers['Authorization'] == 'Bearer new-access',
          statusCode: 200,
          body: (_) => {'success': true, 'data': null},
        );
      }

      final gate = Completer<void>();
      final saved = raceStore.waitForNextSave();
      // B 요청의 onError 안에서 이뤄지는 currentToken 비교 읽기를
      // 지연시킨다 — 이 요청의 2번째 readAccessToken 호출이다(1번째는
      // onRequest의 헤더 주입).
      final readStarted = raceStore.delayAccessReadCall(2, gate.future);

      final futureB = localDio.get<Object?>('/b');
      await readStarted; // B가 currentToken을 읽기 시작 -> 게이트에서 멈춤(스냅샷은 'old-access')

      final futureA = localDio.get<Object?>('/a');
      await saved; // A가 실제로 재발급을 마치고 저장까지 끝냈다 -> 스토어는 new-access/refresh-2

      gate.complete(); // B의 지연된 읽기를 이제서야 풀어준다

      final responseA = await futureA;
      final responseB = await futureB;

      expect((responseA.data! as Map)['success'], true);
      expect((responseB.data! as Map)['success'], true);
      expect(
        rejectedRefreshAttempts,
        0,
        reason: '이미 회전된 토큰으로 불필요한 재발급을 시도해서는 안 된다',
      );
      expect(
        localExpired,
        0,
        reason: '유효하게 갱신된 세션이 있는데 만료 콜백이 불려서는 안 된다',
      );
      expect(await raceStore.readAccessToken(), 'new-access');
      expect(await raceStore.readRefreshToken(), 'refresh-2');
    },
  );
}
