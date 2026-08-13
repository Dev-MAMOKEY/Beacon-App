import 'package:beacon_app/core/network/api_client.dart';
import 'package:beacon_app/core/network/api_exception.dart';
import 'package:beacon_app/core/network/error_code.dart';
import 'package:beacon_app/features/auth/data/auth_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

/// 화면 테스트는 전부 `authRepositoryProvider`를 페이크로 override하므로,
/// 실제 `HttpAuthRepository`가 어떤 경로·바디로 요청을 보내는지는 그
/// 테스트들로 전혀 검증되지 않는다. 실제로 확인한 결과 `/auth/login`을
/// `/auth/signin`으로, 바디 키 `stdId`를 `studentId`로 바꿔도 기존 115개
/// 테스트가 전부 통과했다 — 인증 엔드포인트의 경로도, 바디 키도, DTO 필드
/// 이름도 아무것도 고정돼 있지 않았다는 뜻이다. 이 파일이 그 계약을 HTTP
/// 계층에서 직접 고정한다.
///
/// 주의: http_mock_adapter의 기본 매처는 `needsExactBody: false`라서 등록한
/// 키가 실제 바디에 "포함"돼 있기만 하면 매칭에 성공한다 — 실제 바디에 키가
/// 더 있어도 통과한다는 뜻이다. 그래서 `setUp`에서 명시적으로
/// `needsExactBody: true`를 준다(club_repository_test가 같은 함정을 겪고
/// 얻은 결론이다). 이걸 빼면 "이 키들만 보낸다"는 검증이 거짓 보증이 된다.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late HttpAuthRepository repository;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    // needsExactBody: true — 위 파일 상단 주석 참고.
    adapter = DioAdapter(
      dio: dio,
      matcher: const FullHttpRequestMatcher(needsExactBody: true),
    );
    repository = HttpAuthRepository(ApiClient(dio));
  });

  Map<String, Object?> success(Object? data) => {
        'success': true,
        'data': data,
        'error': null,
        'timestamp': '2026-08-13T00:00:00Z',
      };

  group('login', () {
    test('/auth/login에 stdId와 password만 담아 POST하고 토큰을 파싱한다', () async {
      adapter.onPost(
        '/auth/login',
        (server) => server.reply(
          200,
          success({'accessToken': 'access-1', 'refreshToken': 'refresh-1'}),
        ),
        data: {'stdId': '20250101', 'password': 'abcd1234'},
      );

      // needsExactBody: true이므로 경로가 다르거나 바디의 키 집합이 다르면
      // 위 등록과 매칭되지 않고 DioAdapter가 예외를 던진다 — 이 await가
      // 성공한다는 것 자체가 경로와 바디가 정확히 일치했다는 증거다.
      final tokens = await repository.login(stdId: '20250101', password: 'abcd1234');

      expect(tokens.accessToken, 'access-1');
      expect(tokens.refreshToken, 'refresh-1');
    });

    test('INVALID_CREDENTIALS는 ApiException으로 전달된다', () async {
      adapter.onPost(
        '/auth/login',
        (server) => server.reply(401, {
          'success': false,
          'data': null,
          'error': {
            'code': 'INVALID_CREDENTIALS',
            'message': '학번 또는 비밀번호가 올바르지 않습니다.',
          },
          'timestamp': '2026-08-13T00:00:00Z',
        }),
        data: {'stdId': '20250101', 'password': 'wrong'},
      );

      expect(
        () => repository.login(stdId: '20250101', password: 'wrong'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', ErrorCode.invalidCredentials)
              .having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });
  });

  group('signup', () {
    test('/auth/signup에 stdId, password, name만 담아 POST한다', () async {
      adapter.onPost(
        '/auth/signup',
        (server) => server.reply(200, success(null)),
        data: {'stdId': '20250101', 'password': 'abcd1234', 'name': '김민준'},
      );

      await repository.signup(
        stdId: '20250101',
        password: 'abcd1234',
        name: '김민준',
      );
    });

    test('DUPLICATE_STUDENT_ID는 ApiException으로 전달된다', () async {
      adapter.onPost(
        '/auth/signup',
        (server) => server.reply(409, {
          'success': false,
          'data': null,
          'error': {'code': 'DUPLICATE_STUDENT_ID', 'message': '이미 사용 중인 학번입니다.'},
          'timestamp': '2026-08-13T00:00:00Z',
        }),
        data: {'stdId': '20250101', 'password': 'abcd1234', 'name': '김민준'},
      );

      expect(
        () => repository.signup(
          stdId: '20250101',
          password: 'abcd1234',
          name: '김민준',
        ),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', ErrorCode.duplicateStudentId),
        ),
      );
    });
  });

  group('refresh', () {
    test('/auth/refresh에 refreshToken만 담아 POST하고 회전된 토큰을 파싱한다', () async {
      adapter.onPost(
        '/auth/refresh',
        (server) => server.reply(
          200,
          success({'accessToken': 'access-2', 'refreshToken': 'refresh-2'}),
        ),
        data: {'refreshToken': 'refresh-1'},
      );

      final tokens = await repository.refresh('refresh-1');

      expect(tokens.accessToken, 'access-2');
      expect(tokens.refreshToken, 'refresh-2');
    });

    // AuthInterceptor는 이 리포지토리를 거치지 않고 같은 경로·같은 바디 키로
    // 직접 재발급을 호출한다. 둘 중 하나만 바뀌면 인터셉터의 자동 재발급이
    // 조용히 죽으므로, 여기서 고정한 계약이 인터셉터 쪽 계약이기도 하다.
    test('MEMBER_NOT_FOUND(404)도 코드 그대로 ApiException에 실린다', () async {
      adapter.onPost(
        '/auth/refresh',
        (server) => server.reply(404, {
          'success': false,
          'data': null,
          'error': {'code': 'MEMBER_NOT_FOUND', 'message': '해당 회원이 존재하지 않습니다.'},
          'timestamp': '2026-08-13T00:00:00Z',
        }),
        data: {'refreshToken': 'refresh-1'},
      );

      expect(
        () => repository.refresh('refresh-1'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', ErrorCode.memberNotFound)
              .having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });
  });

  test('logout은 /auth/logout에 바디 없이 POST한다', () async {
    adapter.onPost(
      '/auth/logout',
      (server) => server.reply(200, success(null)),
    );

    await repository.logout();
  });

  group('fetchMe', () {
    test('/members/me를 GET하고 프로필을 파싱한다', () async {
      adapter.onGet(
        '/members/me',
        (server) => server.reply(
          200,
          success({
            'name': '김민준',
            'stdId': '20250101',
            'clubIds': [7, 9],
            'pushEnabled': true,
            'title': '회장',
          }),
        ),
      );

      final profile = await repository.fetchMe();

      expect(profile.name, '김민준');
      expect(profile.stdId, '20250101');
      expect(profile.clubIds, [7, 9]);
      expect(profile.pushEnabled, isTrue);
      expect(profile.title, '회장');
      expect(profile.hasClub, isTrue);
      expect(profile.primaryClubId, 7);
    });

    test('clubIds가 비어 있으면 hasClub이 false다', () async {
      adapter.onGet(
        '/members/me',
        (server) => server.reply(
          200,
          success({
            'name': '김민준',
            'stdId': '20250101',
            'clubIds': <int>[],
            'pushEnabled': false,
            'title': null,
          }),
        ),
      );

      final profile = await repository.fetchMe();

      expect(profile.hasClub, isFalse);
      expect(profile.title, isNull);
    });

    // 서버가 아직 이 필드들을 내려주지 않는 단계에서도 화면이 죽지 않아야
    // 한다 — @JsonKey(defaultValue:)가 실제로 적용되는지 고정한다.
    test('clubIds와 pushEnabled가 응답에 없으면 기본값([], false)으로 채운다', () async {
      adapter.onGet(
        '/members/me',
        (server) => server.reply(
          200,
          success({'name': '김민준', 'stdId': '20250101'}),
        ),
      );

      final profile = await repository.fetchMe();

      expect(profile.clubIds, isEmpty);
      expect(profile.pushEnabled, isFalse);
      expect(profile.hasClub, isFalse);
    });

    test('필수 필드가 빠진 응답은 ApiException(unknown)으로 감싸진다', () async {
      adapter.onGet(
        '/members/me',
        (server) => server.reply(200, success({'stdId': '20250101'})),
      );

      expect(
        () => repository.fetchMe(),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ErrorCode.unknown)),
      );
    });
  });
}
