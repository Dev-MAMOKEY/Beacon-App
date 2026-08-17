import 'package:beacon_app/core/network/api_client.dart';
import 'package:beacon_app/features/admin/data/club_member_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

/// `needsExactBody: true` — 등록한 본문이 실제 요청과 **정확히** 일치해야
/// 매칭된다. 기본값으로 두면 무엇을 보내든 통과한다.
///
/// 쿼리 파라미터는 어댑터 매처에 맡기지 **않고** [sent]로 직접 본다.
/// `queryParameters: {}`로 등록해 두어도 `search=`(빈 값)를 실제로 보내는
/// 구현이 그대로 통과했다 — 매처가 빈 쿼리를 엄격히 보지 않는다.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late HttpClubMemberRepository repository;
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
    repository = HttpClubMemberRepository(ApiClient(dio));
  });

  group('역할 변환', () {
    test('서버 문자열을 enum으로 읽는다', () {
      expect(ClubRole.fromWire('ADMIN'), ClubRole.admin);
      expect(ClubRole.fromWire('MEMBER'), ClubRole.member);
    });

    test('모르는 역할은 member로 접지 않고 던진다', () {
      // 조용히 `member`로 접으면, 서버가 새 역할을 추가했을 때 관리자가
      // 자기 화면에 못 들어가고 원인은 앱 어디에도 남지 않는다.
      expect(() => ClubRole.fromWire('OWNER'), throwsFormatException);
      expect(() => ClubRole.fromWire('admin'), throwsFormatException, reason: '대소문자 구분');
    });

    test('enum 이름이 아니라 서버 문자열을 되돌려 보낸다', () {
      // `newRole: 'admin'`을 보내면 서버가 알아듣지 못한다.
      expect(ClubRole.admin.wire, 'ADMIN');
      expect(ClubRole.member.wire, 'MEMBER');
    });
  });

  group('멤버 목록', () {
    test('검색어가 없으면 파라미터 자체를 붙이지 않는다', () async {
      // 빈 문자열을 보내면 서버 구현에 따라 "빈 이름과 일치"로 해석돼
      // 아무도 안 나올 수 있다.
      adapter.onGet(
        '/clubs/7/members',
        (server) => server.reply(200, {
          'success': true,
          'data': [
            {
              'memberId': 3,
              'name': '강네모',
              'stdId': '20250001',
              'role': 'ADMIN',
              'part': '프론트엔드',
              'rate': 100,
              'attendanceCount': 8,
            },
          ],
        }),
        queryParameters: <String, dynamic>{},
      );

      final members = await repository.fetchMembers(7);

      expect(sent.single.queryParameters, isEmpty, reason: 'search= 를 보내면 안 된다');
      expect(members, hasLength(1));
      final member = members.single;
      expect(member.memberId, 3);
      expect(member.name, '강네모');
      expect(member.stdId, '20250001');
      expect(member.role, ClubRole.admin);
      expect(member.part, '프론트엔드');
      expect(member.rate, 100);
      expect(member.attendanceCount, 8);
    });

    test('공백뿐인 검색어도 파라미터를 붙이지 않는다', () async {
      adapter.onGet(
        '/clubs/7/members',
        (server) => server.reply(200, {'success': true, 'data': <dynamic>[]}),
        queryParameters: <String, dynamic>{},
      );

      await expectLater(repository.fetchMembers(7, search: '   '), completion(isEmpty));
      expect(sent.single.queryParameters, isEmpty);
    });

    test('검색어는 다듬어서 서버로 보낸다', () async {
      // 서버가 걸러야 한다 — 클라이언트에서만 거르면 서버가 페이지를 나눠
      // 줄 때 첫 페이지 밖의 사람은 영영 찾지 못한다.
      adapter.onGet(
        '/clubs/7/members',
        (server) => server.reply(200, {'success': true, 'data': <dynamic>[]}),
        queryParameters: {'search': '박신한'},
      );

      await expectLater(repository.fetchMembers(7, search: '  박신한 '), completion(isEmpty));
      expect(sent.single.queryParameters, {'search': '박신한'});
    });

    test('선택 필드가 없어도 읽힌다', () async {
      // 서버가 출석률·횟수·파트를 늘 채워 주지는 않는다.
      adapter.onGet(
        '/clubs/7/members',
        (server) => server.reply(200, {
          'success': true,
          'data': [
            {'memberId': 3, 'name': '강네모', 'stdId': '20250001', 'role': 'MEMBER'},
          ],
        }),
        queryParameters: <String, dynamic>{},
      );

      final member = (await repository.fetchMembers(7)).single;
      expect(sent.single.queryParameters, isEmpty);
      expect(member.part, isNull);
      expect(member.rate, isNull);
      expect(member.attendanceCount, isNull);
    });
  });

  group('역할 변경', () {
    test('경로의 값을 본문에도 함께 보낸다', () async {
      // 경로에 이미 있는 값을 본문에도 요구한다(`RoleUpdateRequest`) —
      // 서버 스키마가 그렇다. 하나라도 빠지면 400이다.
      adapter.onPatch(
        '/clubs/7/members/2/role',
        (server) => server.reply(200, {'success': true, 'data': null}),
        data: {'clubId': 7, 'requesterId': 9, 'targetMemberId': 2, 'newRole': 'ADMIN'},
      );

      await expectLater(
        repository.updateRole(
          clubId: 7,
          requesterId: 9,
          targetMemberId: 2,
          newRole: ClubRole.admin,
        ),
        completes,
      );
      expect(sent.single.method, 'PATCH');
    });

    test('강등은 MEMBER로 보낸다', () async {
      adapter.onPatch(
        '/clubs/7/members/2/role',
        (server) => server.reply(200, {'success': true, 'data': null}),
        data: {'clubId': 7, 'requesterId': 9, 'targetMemberId': 2, 'newRole': 'MEMBER'},
      );

      await expectLater(
        repository.updateRole(
          clubId: 7,
          requesterId: 9,
          targetMemberId: 2,
          newRole: ClubRole.member,
        ),
        completes,
      );
    });
  });

  group('멤버 제외', () {
    test('대상의 memberId로 DELETE한다', () async {
      adapter.onDelete(
        '/clubs/7/members/2',
        (server) => server.reply(200, {'success': true, 'data': null}),
      );

      await expectLater(repository.removeMember(clubId: 7, memberId: 2), completes);
      expect(sent.single.method, 'DELETE');
      expect(sent.single.path, '/clubs/7/members/2');
    });
  });
}
