import 'package:beacon_app/core/network/api_client.dart';
import 'package:beacon_app/core/network/api_exception.dart';
import 'package:beacon_app/core/network/error_code.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late ApiClient client;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    adapter = DioAdapter(dio: dio);
    client = ApiClient(dio);
  });

  test('success 응답에서 data만 꺼내 파싱한다', () async {
    adapter.onGet('/ping', (server) {
      server.reply(200, {
        'success': true,
        'data': {'name': '김민준'},
        'error': null,
        'timestamp': '2026-08-13T00:00:00Z',
      });
    });

    final name = await client.get<String>(
      '/ping',
      parse: (json) => (json! as Map<String, dynamic>)['name'] as String,
    );

    expect(name, '김민준');
  });

  test('success:false 응답을 ApiException으로 변환한다', () async {
    adapter.onGet('/ping', (server) {
      server.reply(200, {
        'success': false,
        'data': null,
        'error': {
          'code': 'INVALID_CREDENTIALS',
          'message': '학번 또는 비밀번호가 올바르지 않습니다.',
        },
        'timestamp': '2026-08-13T00:00:00Z',
      });
    });

    expect(
      () => client.get<void>('/ping', parse: (_) {}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', ErrorCode.invalidCredentials)
            .having((e) => e.message, 'message', '학번 또는 비밀번호가 올바르지 않습니다.'),
      ),
    );
  });

  test('모르는 에러 코드는 unknown으로 흡수한다', () async {
    adapter.onGet('/ping', (server) {
      server.reply(200, {
        'success': false,
        'data': null,
        'error': {'code': 'SOMETHING_NEW', 'message': '무언가 잘못됐습니다.'},
        'timestamp': '2026-08-13T00:00:00Z',
      });
    });

    expect(
      () => client.get<void>('/ping', parse: (_) {}),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', ErrorCode.unknown)),
    );
  });

  test('HTTP 4xx 본문이 래퍼 형식이면 그 에러 코드를 쓴다', () async {
    adapter.onGet('/ping', (server) {
      server.reply(404, {
        'success': false,
        'data': null,
        'error': {'code': 'SESSION_NOT_FOUND', 'message': '세션이 존재하지 않습니다.'},
        'timestamp': '2026-08-13T00:00:00Z',
      });
    });

    expect(
      () => client.get<void>('/ping', parse: (_) {}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', ErrorCode.sessionNotFound)
            .having((e) => e.statusCode, 'statusCode', 404),
      ),
    );
  });

  test('연결 실패는 network 코드로 변환한다', () async {
    adapter.onGet('/ping', (server) {
      server.throws(
        0,
        DioException.connectionError(
          requestOptions: RequestOptions(path: '/ping'),
          reason: 'no route',
        ),
      );
    });

    expect(
      () => client.get<void>('/ping', parse: (_) {}),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', ErrorCode.network)),
    );
  });

  test('error.code가 문자열이 아니면 unknown으로 흡수하고 message는 그대로 쓴다', () async {
    adapter.onGet('/ping', (server) {
      server.reply(200, {
        'success': false,
        'data': null,
        'error': {'code': 123, 'message': 'bad'},
        'timestamp': '2026-08-13T00:00:00Z',
      });
    });

    expect(
      () => client.get<void>('/ping', parse: (_) {}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', ErrorCode.unknown)
            .having((e) => e.message, 'message', 'bad'),
      ),
    );
  });

  test('error.message가 없거나 문자열이 아니면 기본 메시지를 쓴다', () async {
    adapter.onGet('/ping', (server) {
      server.reply(200, {
        'success': false,
        'data': null,
        'error': {'code': 'INVALID_CREDENTIALS'},
        'timestamp': '2026-08-13T00:00:00Z',
      });
    });

    expect(
      () => client.get<void>('/ping', parse: (_) {}),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          '알 수 없는 오류가 발생했습니다.',
        ),
      ),
    );
  });

  test('success:true인데 data 키가 없으면 파서 실패를 ApiException으로 감싼다', () async {
    adapter.onGet('/ping', (server) {
      server.reply(200, {
        'success': true,
        'error': null,
        'timestamp': '2026-08-13T00:00:00Z',
      });
    });

    expect(
      () => client.get<String>(
        '/ping',
        parse: (json) => (json! as Map<String, dynamic>)['x'] as String,
      ),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', ErrorCode.unknown)
            .having(
              (e) => e.message,
              'message',
              '응답 데이터를 해석하지 못했습니다.',
            ),
      ),
    );
  });

  test('502 응답이 래퍼가 아닌 HTML이면 unknown으로 흡수한다 (network 아님)', () async {
    adapter.onGet('/ping', (server) {
      server.reply(502, '<html>502 Bad Gateway</html>');
    });

    expect(
      () => client.get<void>('/ping', parse: (_) {}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', ErrorCode.unknown)
            .having((e) => e.statusCode, 'statusCode', 502),
      ),
    );
  });

  // AuthInterceptor는 onRequest에서 토큰 저장소를 읽는다. 기기의 키체인/
  // 키스토어 접근이 깨지면 그 PlatformException이 응답 없는 DioException으로
  // 감싸여 여기까지 오는데, 예전에는 그것도 전부 "서버에 연결하지
  // 못했습니다"로 나갔다 — 네트워크는 멀쩡한데 사용자는 와이파이를 껐다
  // 켜게 된다.
  test('저장소 PlatformException은 네트워크 실패와 구분해서 안내한다', () async {
    final localDio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    localDio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          throw PlatformException(code: 'Keychain', message: 'read failed');
        },
      ),
    );

    expect(
      () => ApiClient(localDio).get<void>('/ping', parse: (_) {}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', ErrorCode.unknown)
            .having((e) => e.message, 'message', '기기에 저장된 로그인 정보를 읽지 못했습니다.'),
      ),
    );
  });

  test('연결 자체가 실패하면 network 코드로 올라온다', () async {
    final localDio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    localDio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: 'Connection failed',
          );
        },
      ),
    );

    expect(
      () => ApiClient(localDio).get<void>('/ping', parse: (_) {}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', ErrorCode.network)
            .having((e) => e.message, 'message', '서버에 연결하지 못했습니다.'),
      ),
    );
  });

  test('본문이 JSON 배열이면 unknown으로 흡수한다', () async {
    adapter.onGet('/ping', (server) {
      server.reply(200, [1, 2, 3]);
    });

    expect(
      () => client.get<void>('/ping', parse: (_) {}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', ErrorCode.unknown)
            .having(
              (e) => e.message,
              'message',
              '응답 형식이 올바르지 않습니다.',
            ),
      ),
    );
  });
}
