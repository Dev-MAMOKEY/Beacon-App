import 'package:beacon_app/core/network/api_client.dart';
import 'package:beacon_app/core/network/api_exception.dart';
import 'package:beacon_app/core/network/error_code.dart';
import 'package:beacon_app/features/profile/data/profile_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

/// `needsExactBody: true`가 이 파일의 존재 이유다.
///
/// `http_mock_adapter`의 기본 매처는 등록된 본문이 실제 본문의 **부분집합**
/// 이기만 하면 매칭시킨다. 그 기본값으로는 `{currentPassword, newPassword,
/// confirmNewPassword}`에 `stdId`를 하나 더 실어 보내는 구현도, 토글만 바꾼다며
/// `name`을 빼먹은 구현도(등록 쪽에서 name을 빼면) 그대로 통과한다.
/// `needsExactBody: true`면 키가 하나라도 남거나 모자라면 매칭 자체가 실패해
/// `await`이 던진다.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late HttpProfileRepository repository;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    adapter = DioAdapter(
      dio: dio,
      matcher: const FullHttpRequestMatcher(needsExactBody: true),
    );
    repository = HttpProfileRepository(ApiClient(dio));
  });

  Map<String, Object?> ok() => {
    'success': true,
    'data': null,
    'error': null,
    'timestamp': '2026-08-16T00:00:00Z',
  };

  group('updateProfile', () {
    test('이름만 바꿀 때는 name 하나만 담아 PATCH /members/me로 보낸다', () async {
      // 잡아야 할 잘못된 구현: null인 title/pushEnabled를 값으로 실어
      // 보낸다(`{"name":"김민준","title":null,"pushEnabled":null}`) — 서버는
      // 그걸 "그 필드를 비워달라"로 읽어 알림 설정을 꺼버릴 수 있다.
      // needsExactBody라 키가 하나라도 더 있으면 매칭에 실패한다.
      adapter.onPatch(
        '/members/me',
        (server) => server.reply(200, ok()),
        data: {'name': '김민준'},
      );

      await repository.updateProfile(name: '김민준');
    });

    test('토글을 켤 때는 pushEnabled와 함께 현재 이름도 보낸다', () async {
      // 잡아야 할 잘못된 구현: `{"pushEnabled":true}`만 보낸다 — `name`은
      // 명세서상 필수라 서버가 400을 낸다. 등록 본문에 name이 있는데 실제
      // 요청에 없으면 needsExactBody가 매칭을 거부해 이 await이 던진다.
      adapter.onPatch(
        '/members/me',
        (server) => server.reply(200, ok()),
        data: {'name': '김민준', 'pushEnabled': true},
      );

      await repository.updateProfile(name: '김민준', pushEnabled: true);
    });

    test('토글을 끄면 pushEnabled: false가 그대로 실린다', () async {
      // 잡아야 할 잘못된 구현: `if (pushEnabled == true)` 같은 참-검사로
      // 걸러 false를 아예 안 보낸다 — 알림을 끌 수 없게 된다.
      adapter.onPatch(
        '/members/me',
        (server) => server.reply(200, ok()),
        data: {'name': '김민준', 'pushEnabled': false},
      );

      await repository.updateProfile(name: '김민준', pushEnabled: false);
    });

    test('title을 주면 본문에 함께 실린다', () async {
      adapter.onPatch(
        '/members/me',
        (server) => server.reply(200, ok()),
        data: {'name': '김민준', 'title': '부장'},
      );

      await repository.updateProfile(name: '김민준', title: '부장');
    });
  });

  group('changePassword', () {
    test('세 필드를 정확히 담아 PATCH /members/me/password로 보낸다', () async {
      // 잡아야 할 잘못된 구현: 필드명 오타(`confirmPassword`), 여분 키
      // (`stdId`를 함께 보냄 — Figma가 첫 칸을 "학번 입력"으로 그려 뒀기
      // 때문에 실제로 있을 법한 실수다), 순서가 뒤바뀐 값 대입
      // (`newPassword`에 현재 비밀번호를 넣는다).
      adapter.onPatch(
        '/members/me/password',
        (server) => server.reply(200, ok()),
        data: {
          'currentPassword': 'old-pass1',
          'newPassword': 'new-pass1',
          'confirmNewPassword': 'new-pass1',
        },
      );

      await repository.changePassword(
        currentPassword: 'old-pass1',
        newPassword: 'new-pass1',
        confirmNewPassword: 'new-pass1',
      );
    });

    test('확인값이 새 비밀번호와 달라도 서버가 판정하도록 그대로 보낸다', () async {
      // 잡아야 할 잘못된 구현: 리포지토리가 confirmNewPassword 자리에
      // newPassword를 복사해 넣는다 — 그러면 서버의 일치 검증이 영원히
      // 통과하고, 클라이언트 검증이 뚫리는 순간 사용자가 의도하지 않은
      // 비밀번호로 바뀐다.
      adapter.onPatch(
        '/members/me/password',
        (server) => server.reply(200, ok()),
        data: {
          'currentPassword': 'old-pass1',
          'newPassword': 'new-pass1',
          'confirmNewPassword': 'typo-pass1',
        },
      );

      await repository.changePassword(
        currentPassword: 'old-pass1',
        newPassword: 'new-pass1',
        confirmNewPassword: 'typo-pass1',
      );
    });

    test('현재 비밀번호가 틀리면 INVALID_CREDENTIALS가 ApiException으로 올라온다', () async {
      // 잡아야 할 잘못된 구현: 실패 응답을 삼키고 정상 완료로 돌려준다 —
      // 화면은 "변경되었어요" 토스트를 띄우고 팝업을 닫는다.
      adapter.onPatch(
        '/members/me/password',
        (server) => server.reply(400, {
          'success': false,
          'data': null,
          'error': {'code': 'INVALID_CREDENTIALS', 'message': '비밀번호가 올바르지 않습니다'},
          'timestamp': '2026-08-16T00:00:00Z',
        }),
        data: {
          'currentPassword': 'wrong-pass1',
          'newPassword': 'new-pass1',
          'confirmNewPassword': 'new-pass1',
        },
      );

      await expectLater(
        repository.changePassword(
          currentPassword: 'wrong-pass1',
          newPassword: 'new-pass1',
          confirmNewPassword: 'new-pass1',
        ),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', ErrorCode.invalidCredentials),
        ),
      );
    });
  });
}
