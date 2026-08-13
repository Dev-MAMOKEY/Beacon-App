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
/// 둘 수 있다 — 동시성 테스트를 타이밍 운에 맡기지 않기 위해서다.
class _ScriptedAdapter implements HttpClientAdapter {
  final List<_Rule> _rules = [];
  final Map<String, int> _callCounts = {};

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

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key = '${options.method} ${options.path}';
    _callCounts[key] = (_callCounts[key] ?? 0) + 1;

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

/// `readRefreshToken()` 호출이 시작되는 시점의 값을 먼저 캡처해두고, [gate]가
/// 완료될 때까지 그 값을 붙들고 있다가 반환한다. 실제 저장소에서 느린 읽기가
/// 동시에 벌어지는 쓰기와 경합할 때, 읽기가 "시작된" 시점의 스냅샷을 나중에
/// 돌려주는 상황(트랜잭션 격리가 없는 저장소에서 실제로 벌어질 수 있다)을
/// 결정적으로 재현하기 위한 테스트 더블이다.
class _RaceableTokenStore implements TokenStore {
  _RaceableTokenStore(this._inner);

  final InMemoryTokenStore _inner;
  Future<void>? _armedGate;

  /// 다음 `readRefreshToken()` 호출을 [gate]가 완료될 때까지 붙잡아 둔다.
  void delayNextRefreshRead(Future<void> gate) {
    _armedGate = gate;
  }

  @override
  Future<String?> readAccessToken() => _inner.readAccessToken();

  @override
  Future<String?> readRefreshToken() async {
    final snapshot = await _inner.readRefreshToken();
    final gate = _armedGate;
    _armedGate = null;
    if (gate != null) {
      await gate;
    }
    return snapshot;
  }

  @override
  Future<void> save({required String accessToken, required String refreshToken}) =>
      _inner.save(accessToken: accessToken, refreshToken: refreshToken);

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
  });

  test('동시에 여러 요청이 401을 받아도 재발급은 한 번만 일어난다', () async {
    // refresh 응답을 게이트가 열릴 때까지 붙들어 둔다 — 그래야 "먼저 끝난
    // 요청이 저장을 마쳐서 나머지가 토큰 비교만으로 통과했다"는 우연이 아니라,
    // 세 요청 모두가 재발급 결정 지점에 도달한 상태에서도 실제 네트워크
    // 호출은 하나만 나갔다는 것을 증명할 수 있다.
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

    final responsesFuture = Future.wait([
      dio.get<Object?>('/me'),
      dio.get<Object?>('/me'),
      dio.get<Object?>('/me'),
    ]);

    // 세 요청 모두 401을 받고 onError를 거쳐 재발급 여부를 결정하는
    // 지점까지 진행되도록 이벤트 큐를 완전히 비운다. refresh 응답이 여전히
    // 게이트에 막혀 있으므로, 이 시점에 이미 실제로 나간 재발급 호출
    // 수만으로 중복 여부를 판별할 수 있다.
    await pumpEventQueue();
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
    '다른 flight가 이미 토큰을 회전시킨 뒤에도 낡은 refresh token으로 재발급을 또 시도하지 않는다',
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
      // refresh-1은 딱 한 번만 성공해야 한다 — 서버가 refresh token을
      // 회전시키는 것을 흉내낸다. 이미 소진된 refresh-1로 또 요청이 오면
      // 거부한다.
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
            'error': {'code': 'REFRESH_TOKEN_REVOKED', 'message': '이미 사용된 토큰'},
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
      raceStore.delayNextRefreshRead(gate.future);

      // B를 먼저 시작한다 — B는 refresh token 읽기를 시작하자마자 게이트에서
      // 멈춘다(값은 이 시점의 스냅샷인 'refresh-1'로 이미 캡처됐다).
      final futureB = localDio.get<Object?>('/b');
      await pumpEventQueue();

      // 이제 A를 시작한다. 이 시점엔 아직 아무도 실제로 재발급을 완료하지
      // 않았다 — 새 구현이라면 A는 B의 flight에 합류하고, 옛 구현이라면
      // B가 아직 `_inFlight`를 건드리기 전이라 A가 독자적으로 재발급을
      // 마친다.
      final futureA = localDio.get<Object?>('/a');
      await pumpEventQueue();

      // B의 지연된 읽기를 이제서야 풀어준다 — 이미 (옛 구현이라면) 토큰이
      // 회전된 뒤일 수 있다.
      gate.complete();

      final aOutcome = await futureA.then<Object?>((r) => r, onError: (Object e) => e);
      final bOutcome = await futureB.then<Object?>((r) => r, onError: (Object e) => e);

      expect(
        rejectedRefreshAttempts,
        0,
        reason: '이미 회전된(rotated) refresh token으로 재발급을 시도해서는 안 된다',
      );
      expect(
        localExpired,
        0,
        reason: '유효하게 갱신된 세션이 있는데 만료 콜백이 불려서는 안 된다',
      );
      expect(await raceStore.readAccessToken(), 'new-access');
      expect(await raceStore.readRefreshToken(), 'refresh-2');
      // 최소 한쪽은 재시도까지 성공해야 한다(두 응답 모두 DioException이면
      // 애초에 재발급 자체가 실패한 것이므로 위 assertion들과 모순된다).
      expect(
        aOutcome is Response || bOutcome is Response,
        true,
        reason: 'A 또는 B 중 적어도 하나는 새 토큰으로 재시도에 성공해야 한다',
      );
    },
  );
}
