import 'package:beacon_app/core/network/api_client.dart';
import 'package:beacon_app/features/attendance/data/attendance_dto.dart';
import 'package:beacon_app/features/admin/data/attendance_admin_dto.dart';
import 'package:beacon_app/features/admin/data/session_dto.dart';
import 'package:beacon_app/features/admin/data/session_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

/// `needsExactBody: true` — 다른 리포지토리 테스트와 같은 이유. 이 매처는
/// 등록된 쿼리 파라미터 집합이 실제 요청과 **정확히** 일치하는지도 보므로,
/// `page`/`size`가 빠지거나 다른 키가 섞이면 매칭 자체가 실패한다. 기본값
/// (`needsExactBody: false`)으로 두면 본문이 무엇이든 통과해 "무엇을 보내는가"
/// 를 아무것도 고정하지 못한다.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late HttpSessionRepository repository;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    adapter = DioAdapter(
      dio: dio,
      matcher: const FullHttpRequestMatcher(needsExactBody: true),
    );
    repository = HttpSessionRepository(ApiClient(dio));
  });

  group('세션 목록', () {
    test('status 없이 부르면 page/size만 붙이고 content를 파싱한다', () async {
      adapter.onGet(
        '/clubs/7/sessions',
        (server) => server.reply(200, {
          'success': true,
          'data': {
            'content': [
              {
                'sessionId': 4,
                'sessionName': '세션#0004',
                'status': 'ACTIVE',
                'expectStartAt': '2026-04-07T09:00:00Z',
                'expectEndAt': '2026-04-07T11:00:00Z',
                'startAt': '2026-04-07T09:02:00Z',
                'endAt': null,
              },
            ],
            'last': false,
          },
        }),
        queryParameters: {'page': 0, 'size': 20},
      );

      final page = await repository.fetchSessions(clubId: 7);

      expect(page.sessions, hasLength(1));
      final session = page.sessions.single;
      expect(session.sessionId, 4);
      expect(session.sessionName, '세션#0004');
      expect(session.status, SessionStatus.active);
      expect(session.expectStartAt, DateTime.utc(2026, 4, 7, 9));
      expect(session.startAt, DateTime.utc(2026, 4, 7, 9, 2));
      expect(session.endAt, isNull);
      expect(page.isLast, isFalse, reason: '서버가 준 last를 그대로 전한다');
    });

    test('status를 주면 서버 enum 문자열로 보낸다', () async {
      // 잡아야 할 잘못된 구현: Dart enum 이름(`ended`)을 그대로 보낸다 —
      // 서버는 `ENDED`만 안다.
      adapter.onGet(
        '/clubs/7/sessions',
        (server) => server.reply(200, {
          'success': true,
          'data': {'content': <dynamic>[], 'last': true},
        }),
        queryParameters: {'status': 'ENDED', 'page': 0, 'size': 20},
      );

      final page = await repository.fetchSessions(
        clubId: 7,
        status: SessionStatus.ended,
      );

      expect(page.sessions, isEmpty);
      expect(page.isLast, isTrue);
    });

    test('last가 없으면 마지막 페이지로 본다', () async {
      // 잡아야 할 잘못된 구현: 기본값을 false로 둔다 — 다음 페이지를 계속
      // 요청하다 같은 페이지를 반복해 받는다. 멈추는 쪽이 안전한 기본값이다.
      adapter.onGet(
        '/clubs/7/sessions',
        (server) => server.reply(200, {
          'success': true,
          'data': {'content': <dynamic>[]},
        }),
        queryParameters: {'page': 0, 'size': 20},
      );

      final page = await repository.fetchSessions(clubId: 7);

      expect(page.isLast, isTrue);
    });

    test('알 수 없는 status는 조용히 삼키지 않고 던진다', () async {
      // 잡아야 할 잘못된 구현: 모르는 값을 `scheduled` 같은 기본값으로
      // 접는다 — 끝난 세션에 "출석 종료하기" 버튼을 띄우게 된다.
      adapter.onGet(
        '/clubs/7/sessions',
        (server) => server.reply(200, {
          'success': true,
          'data': {
            'content': [
              {'sessionId': 1, 'sessionName': 'x', 'status': 'PAUSED'},
            ],
            'last': true,
          },
        }),
        queryParameters: {'page': 0, 'size': 20},
      );

      await expectLater(repository.fetchSessions(clubId: 7), throwsA(isA<Object>()));
    });
  });

  group('생성·수정', () {
    // 서버 `SessionCreateRequestDto`의 required는 sessionName·expectStartAt·
    // **expectEndAt** 셋이다. 이슈 #14는 "이름, 예정 시간만"이라고 적었지만
    // 종료 예정 시각 없이는 생성이 되지 않는다.
    final draft = SessionDraft(
      sessionName: '정기모임',
      expectStartAt: DateTime.utc(2026, 4, 7, 9),
      expectEndAt: DateTime.utc(2026, 4, 7, 11),
    );

    test('생성은 세 필드를 UTC ISO 8601로 보낸다', () async {
      // 잡아야 할 잘못된 구현: 로컬 시각을 그대로 직렬화한다 — 시간대만큼
      // 어긋난 세션이 만들어진다.
      adapter.onPost(
        '/clubs/7/sessions',
        (server) => server.reply(200, {'success': true, 'data': null}),
        data: {
          'sessionName': '정기모임',
          'expectStartAt': '2026-04-07T09:00:00.000Z',
          'expectEndAt': '2026-04-07T11:00:00.000Z',
        },
      );

      await expectLater(repository.create(clubId: 7, draft: draft), completes);
    });

    test('로컬 시각으로 만든 초안도 UTC로 변환해 보낸다', () async {
      // 같은 순간을 로컬 플래그로 넣는다 — `toUtc()`가 실제로 일하는 경우다.
      final localDraft = SessionDraft(
        sessionName: '정기모임',
        expectStartAt: DateTime.utc(2026, 4, 7, 9).toLocal(),
        expectEndAt: DateTime.utc(2026, 4, 7, 11).toLocal(),
      );
      adapter.onPost(
        '/clubs/7/sessions',
        (server) => server.reply(200, {'success': true, 'data': null}),
        data: {
          'sessionName': '정기모임',
          'expectStartAt': '2026-04-07T09:00:00.000Z',
          'expectEndAt': '2026-04-07T11:00:00.000Z',
        },
      );

      await expectLater(repository.create(clubId: 7, draft: localDraft), completes);
    });

    test('수정은 PATCH로 같은 본문을 보낸다', () async {
      adapter.onPatch(
        '/clubs/7/sessions/4',
        (server) => server.reply(200, {'success': true, 'data': null}),
        data: {
          'sessionName': '정기모임',
          'expectStartAt': '2026-04-07T09:00:00.000Z',
          'expectEndAt': '2026-04-07T11:00:00.000Z',
        },
      );

      await expectLater(
        repository.update(clubId: 7, sessionId: 4, draft: draft),
        completes,
      );
    });
  });

  test('시작은 otpCode와 uuid를 돌려준다', () async {
    // uuid는 #15의 GATT 페이로드 가운데 16바이트가 된다 — 여기서 잘못
    // 읽으면 비콘이 엉뚱한 세션을 광고한다.
    adapter.onPost(
      '/clubs/7/sessions/4/start',
      (server) => server.reply(200, {
        'success': true,
        'data': {
          'otpCode': '7329',
          'uuid': 'f0e0d0c0-b0a0-9080-7060-504030201000',
        },
      }),
    );

    final result = await repository.start(clubId: 7, sessionId: 4);

    expect(result.otpCode, '7329');
    expect(result.uuid, 'f0e0d0c0-b0a0-9080-7060-504030201000');
  });

  group('출석 인원 세기', () {
    test('한 페이지로 끝나면 그 길이를 돌려준다', () async {
      adapter.onGet(
        '/clubs/7/sessions/4/attendance',
        (server) => server.reply(200, {
          'success': true,
          'data': {
            'content': [
              {'recordId': 1},
              {'recordId': 2},
            ],
            'last': true,
          },
        }),
        queryParameters: {'page': 0, 'size': 100},
      );

      expect(await repository.countAttendees(clubId: 7, sessionId: 4), 2);
    });

    test('여러 페이지면 마지막까지 이어 세다', () async {
      // 잡아야 할 잘못된 구현: 첫 페이지만 세고 끝낸다. `SliceAttendanceDto`
      // 에는 `totalElements`가 없어서(Slice다) 페이지를 이어 받는 것 말고는
      // 총원을 알 방법이 없다.
      adapter
        ..onGet(
          '/clubs/7/sessions/4/attendance',
          (server) => server.reply(200, {
            'success': true,
            'data': {
              'content': [
                {'recordId': 1},
                {'recordId': 2},
              ],
              'last': false,
            },
          }),
          queryParameters: {'page': 0, 'size': 100},
        )
        ..onGet(
          '/clubs/7/sessions/4/attendance',
          (server) => server.reply(200, {
            'success': true,
            'data': {
              'content': [
                {'recordId': 3},
              ],
              'last': true,
            },
          }),
          queryParameters: {'page': 1, 'size': 100},
        );

      expect(await repository.countAttendees(clubId: 7, sessionId: 4), 3);
    });
  });

  group('출석 현황', () {
    test('여러 페이지를 이어 받아 하나로 합친다', () async {
      // 잡아야 할 잘못된 구현: 첫 페이지만 받는다. `SliceAttendanceDto`에는
      // `totalElements`가 없어 이어 받는 것 말고는 전체를 알 방법이 없다.
      adapter
        ..onGet(
          '/clubs/7/sessions/4/attendance',
          (server) => server.reply(200, {
            'success': true,
            'data': {
              'content': [
                {
                  'recordId': 1,
                  'memberId': 11,
                  'memberName': '강네모',
                  'stdId': '20251149',
                  'attendanceStatus': 'PRESENT',
                  'checkedAt': '2026-04-07T09:20:00Z',
                  'isManual': false,
                },
              ],
              'last': false,
            },
          }),
          queryParameters: {'page': 0, 'size': 100},
        )
        ..onGet(
          '/clubs/7/sessions/4/attendance',
          (server) => server.reply(200, {
            'success': true,
            'data': {
              'content': [
                {
                  'recordId': 2,
                  'memberId': 12,
                  'memberName': '정세모',
                  'stdId': '20251008',
                  'attendanceStatus': 'ABSENT',
                  'checkedAt': null,
                  'isManual': true,
                  'adminNote': '병결',
                },
              ],
              'last': true,
            },
          }),
          queryParameters: {'page': 1, 'size': 100},
        );

      final records = await repository.fetchAttendance(clubId: 7, sessionId: 4);

      expect(records, hasLength(2));
      expect(records.first.memberName, '강네모');
      expect(records.first.checkedAt, DateTime.utc(2026, 4, 7, 9, 20));
      expect(records.first.isManual, isFalse);
      expect(records.last.attendanceStatus, AttendanceStatus.absent);
      expect(records.last.checkedAt, isNull, reason: '결석은 체크인 자체가 없다');
      expect(records.last.adminNote, '병결');
    });

    test('상태 변경은 서버 enum 문자열로 보낸다', () async {
      // 잡아야 할 잘못된 구현: Dart enum 이름(`late`)을 그대로 보낸다 —
      // 서버는 `LATE`만 안다.
      adapter.onPatch(
        '/clubs/7/sessions/4/attendance/9',
        (server) => server.reply(200, {'success': true, 'data': null}),
        data: {'attendanceStatus': 'LATE'},
      );

      await expectLater(
        repository.updateAttendanceStatus(
          clubId: 7,
          sessionId: 4,
          recordId: 9,
          status: AttendanceStatus.late,
        ),
        completes,
      );
    });

    test('메모가 있으면 함께 보내고, 비어 있으면 키 자체를 넣지 않는다', () async {
      // 잡아야 할 잘못된 구현: 빈 문자열을 그대로 보낸다 — 서버가 기존
      // 메모를 빈 값으로 덮어쓸 수 있다.
      adapter.onPatch(
        '/clubs/7/sessions/4/attendance/9',
        (server) => server.reply(200, {'success': true, 'data': null}),
        data: {'attendanceStatus': 'ETC', 'adminNote': '공결'},
      );
      await expectLater(
        repository.updateAttendanceStatus(
          clubId: 7,
          sessionId: 4,
          recordId: 9,
          status: AttendanceStatus.etc,
          adminNote: '공결',
        ),
        completes,
      );

      adapter.onPatch(
        '/clubs/7/sessions/4/attendance/10',
        (server) => server.reply(200, {'success': true, 'data': null}),
        data: {'attendanceStatus': 'ETC'},
      );
      await expectLater(
        repository.updateAttendanceStatus(
          clubId: 7,
          sessionId: 4,
          recordId: 10,
          status: AttendanceStatus.etc,
          adminNote: '',
        ),
        completes,
      );
    });

    test('수동 출석은 memberId와 상태를 보낸다', () async {
      adapter.onPost(
        '/clubs/7/sessions/4/attendance/manual',
        (server) => server.reply(200, {'success': true, 'data': null}),
        data: {'memberId': 12, 'attendanceStatus': 'PRESENT'},
      );

      await expectLater(
        repository.addManualAttendance(
          clubId: 7,
          sessionId: 4,
          memberId: 12,
          status: AttendanceStatus.present,
        ),
        completes,
      );
    });
  });

  group('출석 요약', () {
    test('목록에서 네 상태를 각각 센다', () {
      // 잡아야 할 잘못된 구현: 하나의 카운터만 쓰거나 상태를 잘못 매핑한다.
      // **네 수를 전부 다르게** 만들어야 어느 칸이 어느 상태인지 구별된다 —
      // 같은 수가 섞이면 매핑이 뒤바뀌어도 통과한다.
      AdminAttendanceRecord record(AttendanceStatus status, int id) => AdminAttendanceRecord(
        recordId: id,
        memberId: id,
        memberName: 'n',
        stdId: 's',
        attendanceStatus: status,
      );

      final summary = AttendanceSummary.of([
        record(AttendanceStatus.present, 1),
        record(AttendanceStatus.present, 2),
        record(AttendanceStatus.present, 3),
        record(AttendanceStatus.present, 4),
        record(AttendanceStatus.present, 5),
        record(AttendanceStatus.late, 6),
        record(AttendanceStatus.absent, 7),
        record(AttendanceStatus.absent, 8),
      ]);

      expect(summary.present, 5);
      expect(summary.late, 1);
      expect(summary.absent, 2);
      expect(summary.etc, 0);
    });
  });

}
