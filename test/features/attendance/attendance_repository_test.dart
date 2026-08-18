import 'package:beacon_app/core/network/api_client.dart';
import 'package:beacon_app/core/network/api_exception.dart';
import 'package:beacon_app/core/network/error_code.dart';
import 'package:beacon_app/features/attendance/data/attendance_dto.dart';
import 'package:beacon_app/features/attendance/data/attendance_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

/// club_repository_test.dart·beacon_config_repository_test.dart와 같은
/// 스타일 — needsExactBody: true로 여분의 키가 섞여 나가지 않는지까지
/// 고정한다.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late HttpAttendanceRepository repository;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    adapter = DioAdapter(
      dio: dio,
      matcher: const FullHttpRequestMatcher(needsExactBody: true),
    );
    repository = HttpAttendanceRepository(ApiClient(dio));
  });

  group('fetchActiveSession', () {
    test('/clubs/{id}/sessions/active를 호출해 활성 세션을 파싱한다', () async {
      adapter.onGet(
        '/clubs/7/sessions/active',
        (server) => server.reply(200, {
          'success': true,
          'data': {
            'sessionId': 42,
            'sessionName': '정기모임',
            'status': 'ACTIVE',
            'startAt': '2026-08-14T10:00:00Z',
          },
          'error': null,
          'timestamp': '2026-08-14T00:00:00Z',
        }),
      );

      final session = await repository.fetchActiveSession(7);

      expect(session, isNotNull);
      expect(session!.sessionId, 42);
      expect(session.sessionName, '정기모임');
      expect(session.status, 'ACTIVE');
      expect(session.startAt, DateTime.parse('2026-08-14T10:00:00Z'));
    });

    test('data가 null이면 null을 돌려준다(활성 세션 없음)', () async {
      adapter.onGet(
        '/clubs/7/sessions/active',
        (server) => server.reply(200, {
          'success': true,
          'data': null,
          'error': null,
          'timestamp': '2026-08-14T00:00:00Z',
        }),
      );

      expect(await repository.fetchActiveSession(7), isNull);
    });

    test('SESSION_NOT_FOUND 에러도 null(활성 세션 없음)로 취급한다', () async {
      adapter.onGet(
        '/clubs/7/sessions/active',
        (server) => server.reply(200, {
          'success': false,
          'data': null,
          'error': {'code': 'SESSION_NOT_FOUND', 'message': '진행 중인 세션이 없습니다.'},
          'timestamp': '2026-08-14T00:00:00Z',
        }),
      );

      expect(await repository.fetchActiveSession(7), isNull);
    });

    test('그 외 에러는 그대로 ApiException으로 전달된다', () async {
      adapter.onGet(
        '/clubs/7/sessions/active',
        (server) => server.reply(200, {
          'success': false,
          'data': null,
          'error': {'code': 'FORBIDDEN', 'message': '권한이 없습니다.'},
          'timestamp': '2026-08-14T00:00:00Z',
        }),
      );

      expect(
        () => repository.fetchActiveSession(7),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ErrorCode.forbidden)),
      );
    });
  });

  group('checkIn', () {
    test('/clubs/{id}/sessions/{sid}/attendance에 otpCode만 담아 POST한다', () async {
      adapter.onPost(
        '/clubs/7/sessions/42/attendance',
        (server) => server.reply(200, {
          'success': true,
          'data': {'status': 'PRESENT'},
          'error': null,
          'timestamp': '2026-08-14T00:00:00Z',
        }),
        data: {'otpCode': '7329'},
      );

      final status = await repository.checkIn(clubId: 7, sessionId: 42, otpCode: '7329');

      expect(status, AttendanceStatus.present);
    });

    test('서버가 LATE를 돌려주면 AttendanceStatus.late로 파싱한다', () async {
      adapter.onPost(
        '/clubs/7/sessions/42/attendance',
        (server) => server.reply(200, {
          'success': true,
          'data': {'status': 'LATE'},
          'error': null,
          'timestamp': '2026-08-14T00:00:00Z',
        }),
        data: {'otpCode': '1111'},
      );

      final status = await repository.checkIn(clubId: 7, sessionId: 42, otpCode: '1111');

      expect(status, AttendanceStatus.late);
    });

    test('INVALID_ATTENDANCE_CODE는 ApiException으로 전달된다', () async {
      adapter.onPost(
        '/clubs/7/sessions/42/attendance',
        (server) => server.reply(200, {
          'success': false,
          'data': null,
          'error': {'code': 'INVALID_ATTENDANCE_CODE', 'message': '비밀번호가 올바르지 않습니다.'},
          'timestamp': '2026-08-14T00:00:00Z',
        }),
        data: {'otpCode': '0000'},
      );

      expect(
        () => repository.checkIn(clubId: 7, sessionId: 42, otpCode: '0000'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', ErrorCode.invalidAttendanceCode),
        ),
      );
    });
  });
}
