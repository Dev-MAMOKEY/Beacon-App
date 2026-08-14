import 'package:beacon_app/core/network/api_client.dart';
import 'package:beacon_app/core/network/api_exception.dart';
import 'package:beacon_app/features/attendance/data/attendance_dto.dart';
import 'package:beacon_app/features/records/data/records_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

/// needsExactBody: true — club_repository_test.dart와 동일한 이유. 이
/// 매처는 등록된 쿼리 파라미터 집합이 실제 요청과 정확히 일치하는지도
/// 검사하므로, `?year=&month=`가 빠지거나 다른 키가 섞이면 매칭 자체가
/// 실패한다.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late HttpRecordsRepository repository;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    adapter = DioAdapter(
      dio: dio,
      matcher: const FullHttpRequestMatcher(needsExactBody: true),
    );
    repository = HttpRecordsRepository(ApiClient(dio));
  });

  test('fetch는 ?year=&month=를 정확히 붙이고 요약 4종·목록을 파싱한다', () async {
    // 잡아야 할 잘못된 구현: 쿼리 파라미터를 아예 안 붙이거나(year/month
    // 누락), 응답의 status.present/absent/late/etc 같은 필드명을 오타로
    // 읽는다. needsExactBody: true라 쿼리 파라미터가 하나라도 빠지거나
    // 더 있으면 onGet 등록과 매칭되지 않아 이 await 자체가 실패한다.
    adapter.onGet(
      '/clubs/7/members/me/records',
      (server) => server.reply(200, {
        'success': true,
        'data': {
          'year': 2026,
          'month': 8,
          'records': [
            {
              'sessionId': 1,
              'sessionName': '정기모임',
              'date': '2026-08-01T00:00:00Z',
              'status': 'PRESENT',
              'checkedAt': '2026-08-01T10:05:00Z',
              'adminNote': null,
            },
            {
              'sessionId': 2,
              'sessionName': '스터디',
              'date': '2026-08-08T00:00:00Z',
              'status': 'LATE',
              'checkedAt': '2026-08-08T10:12:00Z',
              'adminNote': null,
            },
          ],
          'status': {'present': 10, 'absent': 1, 'late': 2, 'etc': 0},
          'attendanceRate': 83.3,
        },
        'error': null,
        'timestamp': '2026-08-14T00:00:00Z',
      }),
      queryParameters: {'year': 2026, 'month': 8},
    );

    final records = await repository.fetch(clubId: 7, year: 2026, month: 8);

    expect(records.year, 2026);
    expect(records.month, 8);
    expect(records.present, 10);
    expect(records.absent, 1);
    expect(records.late, 2);
    expect(records.etc, 0);
    expect(records.attendanceRate, 83.3);
    expect(records.records, hasLength(2));
    expect(records.records.first.sessionId, 1);
    expect(records.records.first.sessionName, '정기모임');
    expect(records.records.first.status, AttendanceStatus.present);
    expect(records.records[1].status, AttendanceStatus.late);
  });

  test('다른 clubId/year/month 조합도 쿼리에 그대로 반영한다', () async {
    adapter.onGet(
      '/clubs/9/members/me/records',
      (server) => server.reply(200, {
        'success': true,
        'data': {
          'year': 2025,
          'month': 3,
          'records': <Map<String, dynamic>>[],
          'status': {'present': 0, 'absent': 0, 'late': 0, 'etc': 0},
          'attendanceRate': 0.0,
        },
        'error': null,
        'timestamp': '2026-08-14T00:00:00Z',
      }),
      queryParameters: {'year': 2025, 'month': 3},
    );

    final records = await repository.fetch(clubId: 9, year: 2025, month: 3);

    expect(records.year, 2025);
    expect(records.month, 3);
    expect(records.records, isEmpty);
  });

  test('status 필드가 객체가 아니면 ApiException으로 올라온다', () async {
    adapter.onGet(
      '/clubs/7/members/me/records',
      (server) => server.reply(200, {
        'success': true,
        'data': {
          'year': 2026,
          'month': 8,
          'records': <Map<String, dynamic>>[],
          'status': 'PRESENT', // 객체가 아니라 문자열 — 형식 오류
          'attendanceRate': 0.0,
        },
        'error': null,
        'timestamp': '2026-08-14T00:00:00Z',
      }),
      queryParameters: {'year': 2026, 'month': 8},
    );

    await expectLater(
      repository.fetch(clubId: 7, year: 2026, month: 8),
      throwsA(isA<ApiException>()),
    );
  });
}
