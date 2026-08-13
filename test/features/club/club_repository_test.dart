import 'package:beacon_app/core/network/api_client.dart';
import 'package:beacon_app/core/network/api_exception.dart';
import 'package:beacon_app/core/network/error_code.dart';
import 'package:beacon_app/features/club/data/club_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

/// 위젯 테스트는 전부 `clubRepositoryProvider`를 페이크로 override하므로,
/// 실제 `HttpClubRepository`가 어떤 경로·바디로 요청을 보내는지는 그
/// 테스트들로 전혀 검증되지 않는다 — 엔드포인트가 `/club/join`으로
/// 바뀌거나 바디 키가 `code`로 바뀌어도 위젯 테스트는 계속 초록색이다.
/// 이 테스트는 실제 HTTP 계층을 대상으로 경로와 바디를 고정한다.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late HttpClubRepository repository;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    adapter = DioAdapter(dio: dio);
    repository = HttpClubRepository(ApiClient(dio));
  });

  test('joinByInviteCode는 /clubs/join에 inviteCode만 담아 POST한다', () async {
    adapter.onPost(
      '/clubs/join',
      (server) => server.reply(200, {
        'success': true,
        'data': null,
        'error': null,
        'timestamp': '2026-08-13T00:00:00Z',
      }),
      data: {'inviteCode': 'ABC123'},
    );

    // 경로나 바디 키가 조금이라도 다르면 위 onPost 등록과 매칭되지 않아
    // DioAdapter가 예외를 던지고, 그 예외는 ApiClient를 거쳐 여기까지
    // 올라온다 — 즉 이 await가 성공한다는 것 자체가 경로와 바디가 정확히
    // 일치했다는 증거다.
    await repository.joinByInviteCode('ABC123');
  });

  test('clubId를 담지 않는다', () async {
    // clubId가 조금이라도 섞여 나가면(예: null로라도) 아래 매처가 요구하는
    // 정확히 {'inviteCode': ...} 한 키짜리 바디와 일치하지 않아 실패한다.
    adapter.onPost(
      '/clubs/join',
      (server) => server.reply(200, {
        'success': true,
        'data': null,
        'error': null,
        'timestamp': '2026-08-13T00:00:00Z',
      }),
      data: {'inviteCode': 'XYZ999'},
    );

    await repository.joinByInviteCode('XYZ999');
  });

  test('서버가 INVALID_INVITE_CODE를 응답하면 ApiException으로 전달된다', () async {
    adapter.onPost(
      '/clubs/join',
      (server) => server.reply(200, {
        'success': false,
        'data': null,
        'error': {
          'code': 'INVALID_INVITE_CODE',
          'message': '초대코드가 존재하지 않거나 유효하지 않습니다.',
        },
        'timestamp': '2026-08-13T00:00:00Z',
      }),
      data: {'inviteCode': 'ABC123'},
    );

    expect(
      () => repository.joinByInviteCode('ABC123'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', ErrorCode.invalidInviteCode)),
    );
  });
}
