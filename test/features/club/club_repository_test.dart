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
///
/// 주의: http_mock_adapter의 기본 매처는 `needsExactBody: false`라서 등록한
/// 키가 실제 바디에 "포함"돼 있으면 매칭에 성공한다 — 실제 바디에 clubId
/// 같은 키가 여분으로 더 있어도 통과한다는 뜻이다. 그래서 `setUp`에서
/// 명시적으로 `needsExactBody: true`를 준다. 이걸 빼면 "clubId를 담지
/// 않는다"라는 테스트 이름이 거짓 보증이 된다 — 실제로는 clubId가 섞여
/// 나가도 실패하지 않는다.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late HttpClubRepository repository;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    // needsExactBody: true — 위 파일 상단 주석 참고.
    adapter = DioAdapter(
      dio: dio,
      matcher: const FullHttpRequestMatcher(needsExactBody: true),
    );
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

    // needsExactBody: true이므로 경로가 다르거나, 바디에 키가 하나라도
    // 빠지거나 더 있으면 위 onPost 등록과 매칭되지 않는다 — 그러면
    // DioAdapter가 예외를 던지고, 그 예외는 ApiClient를 거쳐 여기까지
    // 올라온다. 즉 이 await가 성공한다는 것 자체가 경로와 바디의 키 집합이
    // {'inviteCode': 'ABC123'}와 정확히 일치했다는 증거다.
    await repository.joinByInviteCode('ABC123');
  });

  test('clubId를 담지 않는다', () async {
    // needsExactBody: true 덕분에, 실제 바디에 clubId가 어떤 값으로든
    // (null 포함) 섞여 나가면 아래 등록({'inviteCode': ...} 한 키짜리)과
    // 키 집합이 달라져 매칭에 실패하고, joinByInviteCode가 ApiException을
    // 던져 이 테스트가 실패한다.
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
