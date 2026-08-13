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
/// 경로별 호출 횟수를 센다.
class _ScriptedAdapter implements HttpClientAdapter {
  final List<_Rule> _rules = [];
  final Map<String, int> _callCounts = {};

  void on(
    String method,
    String path, {
    bool Function(RequestOptions options)? when,
    required int statusCode,
    required Object? Function(RequestOptions options) body,
  }) {
    _rules.add(_Rule(method, path, when, statusCode, body));
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
  _Rule(this.method, this.path, this.when, this.statusCode, this.body);

  final String method;
  final String path;
  final bool Function(RequestOptions options)? when;
  final int statusCode;
  final Object? Function(RequestOptions options) body;
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

  test('동시에 여러 요청이 401을 받아도 재발급은 한 번만 일어난다', () async {
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
      body: (_) => {'success': true, 'data': null},
    );

    final responses = await Future.wait([
      dio.get<Object?>('/me'),
      dio.get<Object?>('/me'),
      dio.get<Object?>('/me'),
    ]);

    expect(adapter.callsTo('POST', '/auth/refresh'), 1);
    for (final response in responses) {
      expect((response.data! as Map)['success'], true);
    }
    expect(expiredCallbackCount, 0);
  });
}
