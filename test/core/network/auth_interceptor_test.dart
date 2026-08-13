import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:beacon_app/core/network/auth_interceptor.dart';
import 'package:beacon_app/core/storage/token_store.dart';
import 'package:beacon_app/core/storage/token_write_coordinator.dart';
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

  /// 응답 자체가 오지 않는 상황(연결 끊김, 타임아웃)을 흉내낸다 — 상태
  /// 코드도 바디도 없는 실패다. 실제 Dio 어댑터가 소켓 단계에서 실패하면
  /// 이렇게 `response`가 없는 `DioException`을 던진다.
  void onConnectionError(String method, String path) {
    _rules.add(_Rule(method, path, null, null, null, null));
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
        if (rule.statusCode == null) {
          // 응답이 아예 없는 실패(연결 끊김/타임아웃) — 실제 어댑터가 소켓
          // 단계에서 던지는 것과 같은 모양: response가 없는 DioException.
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: 'Connection failed',
          );
        }
        return ResponseBody.fromString(
          jsonEncode(rule.body!(options)),
          rule.statusCode!,
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
  final int? statusCode;
  final Object? Function(RequestOptions options)? body;
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
  late TokenWriteCoordinator coordinator;
  late Dio dio;
  late _ScriptedAdapter adapter;
  late int expiredCallbackCount;

  setUp(() async {
    store = InMemoryTokenStore();
    await store.save(accessToken: 'old-access', refreshToken: 'refresh-1');

    // 인터셉터는 저장소가 아니라 조정자를 통해서만 토큰을 읽고 쓴다.
    // SessionController도 같은 인스턴스를 공유하므로, 여기서 조정자에 직접
    // beginOperation()/save()/clear()를 부르는 것은 "세션 컨트롤러가 그
    // 순간 로그인/로그아웃을 했다"를 재현하는 것과 같다.
    coordinator = TokenWriteCoordinator(store);

    dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    adapter = _ScriptedAdapter();
    dio.httpClientAdapter = adapter;

    expiredCallbackCount = 0;
    dio.interceptors.add(
      AuthInterceptor(
        tokens: coordinator,
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

  group('재발급 실패의 원인에 따라 세션을 지울지 결정한다 (Task 7 정책과 정렬)', () {
    // 리뷰에서 지적된 정책 모순: Task 5는 "실패하면 무조건 만료"를,
    // Task 7은 "자격 증명 실패만 만료"를 요구했고 이 인터셉터는 Task 5
    // 시절 그대로 남아 있었다. 재발급 도중 네트워크가 끊긴 것뿐인데
    // 세션을 지우고 로그아웃시키는 것이 바로 Task 7이 없애려 했던
    // "오프라인이면 로그아웃되는" 버그다.
    test('재발급이 연결 오류로 실패하면 토큰을 지우지 않고 만료 콜백도 부르지 않는다', () async {
      adapter.onConnectionError('POST', '/auth/refresh');
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

      expect(await store.readAccessToken(), 'old-access', reason: '네트워크 실패는 세션을 지울 근거가 아니다');
      expect(await store.readRefreshToken(), 'refresh-1');
      expect(expiredCallbackCount, 0, reason: '오프라인 한 번으로 로그아웃되면 안 된다');
    });

    test('재발급이 자격-증명-죽음 코드(401)로 실패하면 토큰을 지우고 만료 콜백을 부른다', () async {
      adapter.on(
        'POST',
        '/auth/refresh',
        statusCode: 401,
        body: (_) => {
          'success': false,
          'data': null,
          'error': {'code': 'REFRESH_TOKEN_INVALID', 'message': '형식 오류'},
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

    // 리뷰에서 드러난 정책 어긋남: 인터셉터는 401/403이 아닌 응답을 code를
    // 보기도 전에 일시적 실패로 넘겼는데, 실 백엔드는 MEMBER_NOT_FOUND를
    // **404**로 내려준다(session_controller_test의 같은 코드 목록 참고).
    // 그래서 "리프레시 토큰은 유효한데 서버에서 회원 행이 삭제된" 상황에서
    // 인터셉터가 토큰을 남기고 만료 콜백도 부르지 않아, 사용자가 모든
    // 요청이 실패하는 화면에서 로그인으로 돌아갈 길 없이 갇혔다.
    test('재발급이 404 MEMBER_NOT_FOUND로 실패하면 토큰을 지우고 만료 콜백을 부른다', () async {
      adapter.on(
        'POST',
        '/auth/refresh',
        statusCode: 404,
        body: (_) => {
          'success': false,
          'data': null,
          'error': {'code': 'MEMBER_NOT_FOUND', 'message': '해당 회원이 존재하지 않습니다.'},
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

      expect(await store.readAccessToken(), isNull, reason: '인식된 인증 실패 코드는 상태 코드로 뒤집히지 않는다');
      expect(await store.readRefreshToken(), isNull);
      expect(expiredCallbackCount, 1);
    });

    test('재발급이 401을 냈고 바디가 표준 래퍼가 아니면 상태 코드만으로 자격 증명 실패로 본다', () async {
      // 프록시가 끼어들어 HTML을 돌려주는 경우처럼 code를 읽을 수 없는 응답.
      // 이때는 401 자체가 "자격 증명이 거부됐다"는 충분한 증거다.
      adapter.on(
        'POST',
        '/auth/refresh',
        statusCode: 401,
        body: (_) => '<html><body>401 Unauthorized</body></html>',
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
      expect(expiredCallbackCount, 1);
    });

    test('재발급이 5xx로 실패하면 바디를 읽을 수 없어도 세션을 지우지 않는다', () async {
      adapter.on(
        'POST',
        '/auth/refresh',
        statusCode: 500,
        body: (_) => '<html><body>502 Bad Gateway</body></html>',
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

      expect(await store.readAccessToken(), 'old-access', reason: '서버 오류는 자격 증명을 무효라고 볼 근거가 아니다');
      expect(expiredCallbackCount, 0);
    });
  });

  /// 인터셉터가 [TokenWriteCoordinator]가 아니라 [TokenStore]에 직접 쓰던
  /// 시절에는 아래 두 상황에서 인터셉터가 세션 컨트롤러의 결정을 조용히
  /// 뒤집었다. 세대 가드는 도움이 되지 못했다 — 인터셉터가 세대도 큐도 갖고
  /// 있지 않았기 때문이다.
  group('세션 컨트롤러와 겹치는 토큰 쓰기 — 조정자가 없으면 인터셉터가 결정을 뒤집는다', () {
    test('재발급이 진행 중일 때 로그아웃하면, 회전된 토큰이 뒤늦게 저장되지 않는다', () async {
      final refreshGate = Completer<void>();
      adapter.on(
        'POST',
        '/auth/refresh',
        statusCode: 200,
        holdUntil: refreshGate.future,
        body: (_) => {
          'success': true,
          'data': {'accessToken': 'rotated-access', 'refreshToken': 'rotated-refresh'},
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

      final refreshArrived = adapter.waitForCalls('POST', '/auth/refresh', 1);
      final pending = dio.get<Object?>('/me');
      await refreshArrived; // 재발급 flight가 네트워크에 걸려 있는 상태

      // 이 사이에 사용자가 로그아웃한다 — SessionController.signOut()이 하는
      // 일과 같다(세대를 올리고 큐를 통해 지운다).
      final signOutGeneration = coordinator.beginOperation();
      expect(await coordinator.clear(signOutGeneration), isTrue);

      refreshGate.complete();
      await expectLater(pending, throwsA(isA<DioException>()));

      expect(
        await store.readAccessToken(),
        isNull,
        reason: '로그아웃 뒤에 재발급이 회전된 토큰을 되살리면, 화면은 로그아웃인데 자격 증명은 디스크에 남는다',
      );
      expect(await store.readRefreshToken(), isNull);
    });

    test('옛 재발급이 실패하는 사이 새로 로그인하면, 새 사용자의 토큰을 지우거나 만료시키지 않는다', () async {
      final refreshGate = Completer<void>();
      adapter.on(
        'POST',
        '/auth/refresh',
        statusCode: 401,
        holdUntil: refreshGate.future,
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

      final refreshArrived = adapter.waitForCalls('POST', '/auth/refresh', 1);
      final pending = dio.get<Object?>('/me');
      await refreshArrived;

      // 옛 flight가 실패로 향하는 사이 사용자가 다른 계정으로 새로 로그인한다
      // — SessionController.onAuthenticated()가 하는 일과 같다.
      final loginGeneration = coordinator.beginOperation();
      expect(
        await coordinator.save(
          loginGeneration,
          accessToken: 'new-user-access',
          refreshToken: 'new-user-refresh',
        ),
        isTrue,
      );

      refreshGate.complete();
      await expectLater(pending, throwsA(isA<DioException>()));

      expect(
        await store.readAccessToken(),
        'new-user-access',
        reason: '옛 flight의 정리가 방금 로그인한 사용자의 토큰을 지우면 안 된다',
      );
      expect(await store.readRefreshToken(), 'new-user-refresh');
      expect(
        expiredCallbackCount,
        0,
        reason: '만료 콜백까지 부르면 방금 로그인한 사용자가 곧바로 로그인 화면으로 밀려난다',
      );
    });
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
          tokens: TokenWriteCoordinator(raceStore),
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
