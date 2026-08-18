import 'package:beacon_app/core/network/api_client.dart';
import 'package:beacon_app/core/network/api_exception.dart';
import 'package:beacon_app/core/network/error_code.dart';
import 'package:beacon_app/features/club/data/club_settings_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

/// 쿼리·본문은 어댑터 매처에 맡기지 않고 [sent]로 직접 본다 — 매처는
/// 등록해 둔 것과 다르면 "매칭 실패"로 넘어가 버려서, 무엇을 보냈는지
/// 정확히 고정하려면 실제 요청을 붙잡는 편이 확실하다.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late HttpClubSettingsRepository repository;
  late List<RequestOptions> sent;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    sent = [];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          sent.add(options);
          handler.next(options);
        },
      ),
    );
    adapter = DioAdapter(
      dio: dio,
      matcher: const FullHttpRequestMatcher(needsExactBody: true),
    );
    repository = HttpClubSettingsRepository(ApiClient(dio));
  });

  group('동아리 상세', () {
    test('이름과 설명을 읽는다', () async {
      adapter.onGet(
        '/clubs/7',
        (server) => server.reply(200, {
          'success': true,
          'data': {
            'id': 7,
            'clubName': '마모키',
            'clubDescription': '비콘 출석 동아리',
            'createdAt': '2026-03-02T00:00:00Z',
          },
        }),
      );

      final club = await repository.fetchClub(7);

      expect(club.id, 7);
      expect(club.clubName, '마모키');
      expect(club.clubDescription, '비콘 출석 동아리');
      expect(club.createdAt, DateTime.utc(2026, 3, 2));
    });

    test('설명이 없어도 읽힌다', () async {
      // 설명은 선택 항목이다. null을 빈 문자열로 접지 않는다 — "설명이 없음"과
      // "빈 설명을 저장함"은 다르다.
      adapter.onGet(
        '/clubs/7',
        (server) => server.reply(200, {
          'success': true,
          'data': {'id': 7, 'clubName': '마모키'},
        }),
      );

      final club = await repository.fetchClub(7);
      expect(club.clubDescription, isNull);
      expect(club.createdAt, isNull);
    });
  });

  group('동아리 정보 수정', () {
    test('이름과 설명만 PATCH로 보낸다', () async {
      adapter.onPatch(
        '/clubs/7',
        (server) => server.reply(200, {'success': true, 'data': '수정되었습니다'}),
        data: {'clubName': '마모키', 'clubDescription': '새 설명'},
      );

      await expectLater(
        repository.updateClub(clubId: 7, clubName: '마모키', clubDescription: '새 설명'),
        completes,
      );
      expect(sent.single.method, 'PATCH');
      expect(sent.single.data, {'clubName': '마모키', 'clubDescription': '새 설명'});
    });

    test('응답이 문자열이어도 성공으로 다룬다', () async {
      // `PATCH /clubs/{id}`의 `data`는 수정된 동아리가 아니라 **문자열**이다
      // (`RsDataString`). 이걸 객체로 파싱하려 들면 성공한 저장이 실패로 보인다.
      adapter.onPatch(
        '/clubs/7',
        (server) => server.reply(200, {'success': true, 'data': 'OK'}),
        data: {'clubName': 'a', 'clubDescription': 'b'},
      );

      await expectLater(
        repository.updateClub(clubId: 7, clubName: 'a', clubDescription: 'b'),
        completes,
      );
    });
  });

  group('초대코드', () {
    test('유효한 코드를 읽는다', () async {
      adapter.onGet(
        '/clubs/7/invite-code',
        (server) => server.reply(200, {
          'success': true,
          'data': {'inviteCode': 'ABCD1234'},
        }),
      );

      await expectLater(repository.fetchInviteCode(7), completion('ABCD1234'));
    });

    test('코드가 없으면 오류가 아니라 null이다', () async {
      // 서버는 코드가 없을 때 `data: null`이 아니라 **400
      // `INVALID_INVITE_CODE`**로 답한다. 그대로 올리면 "아직 안 만들었다"가
      // 화면에서 오류로 보인다.
      adapter.onGet(
        '/clubs/7/invite-code',
        (server) => server.reply(400, {
          'success': false,
          'data': null,
          'error': {'code': 'INVALID_INVITE_CODE', 'message': '초대코드가 존재하지 않거나 유효하지 않습니다.'},
        }),
      );

      await expectLater(repository.fetchInviteCode(7), completion(isNull));
    });

    test('다른 실패는 그대로 올린다', () async {
      // `INVALID_INVITE_CODE` **하나만** 접는다. 권한 오류나 없는 동아리까지
      // 삼키면 "코드가 없음"과 "못 읽었음"이 화면에서 같아 보인다.
      adapter.onGet(
        '/clubs/7/invite-code',
        (server) => server.reply(403, {
          'success': false,
          'data': null,
          'error': {'code': 'FORBIDDEN', 'message': '권한이 없습니다.'},
        }),
      );

      await expectLater(
        repository.fetchInviteCode(7),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', ErrorCode.forbidden),
        ),
      );
    });

    test('발급은 POST고 새 코드를 돌려준다', () async {
      // 기존 유효 코드는 서버가 자동으로 무효화한다 — "생성"이 아니라 "재발급".
      adapter.onPost(
        '/clubs/7/invite-code',
        (server) => server.reply(200, {
          'success': true,
          'data': {'inviteCode': 'NEW99999'},
        }),
      );

      await expectLater(repository.issueInviteCode(7), completion('NEW99999'));
      expect(sent.single.method, 'POST');
    });

    test('빈 코드를 발급받으면 실패로 다룬다', () async {
      // 빈 코드를 화면에 띄우면 관리자가 그걸 그대로 공유한다.
      adapter.onPost(
        '/clubs/7/invite-code',
        (server) => server.reply(200, {
          'success': true,
          'data': {'inviteCode': ''},
        }),
      );

      await expectLater(repository.issueInviteCode(7), throwsA(isA<ApiException>()));
    });

    test('무효화는 DELETE다', () async {
      adapter.onDelete(
        '/clubs/7/invite-code',
        (server) => server.reply(200, {'success': true, 'data': null}),
      );

      await expectLater(repository.revokeInviteCode(7), completes);
      expect(sent.single.method, 'DELETE');
      expect(sent.single.path, '/clubs/7/invite-code');
    });

    test('이미 코드가 없으면 무효화도 성공으로 다룬다', () async {
      // 원하던 상태에 이미 도달한 것이다. 오류로 보여 주면 관리자는 뭘
      // 고쳐야 하는지 알 수 없다.
      adapter.onDelete(
        '/clubs/7/invite-code',
        (server) => server.reply(400, {
          'success': false,
          'data': null,
          'error': {'code': 'INVALID_INVITE_CODE', 'message': '초대코드가 존재하지 않거나 유효하지 않습니다.'},
        }),
      );

      await expectLater(repository.revokeInviteCode(7), completes);
    });

    test('무효화의 다른 실패는 그대로 올린다', () async {
      adapter.onDelete(
        '/clubs/7/invite-code',
        (server) => server.reply(404, {
          'success': false,
          'data': null,
          'error': {'code': 'CLUB_NOT_FOUND', 'message': '동아리가 존재하지 않습니다.'},
        }),
      );

      await expectLater(
        repository.revokeInviteCode(7),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', ErrorCode.clubNotFound),
        ),
      );
    });
  });
}
