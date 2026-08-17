import 'package:beacon_app/features/notification/data/push_messaging.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

/// 앱이 열려 있는 동안에는 OS가 알림 배너를 그려 주지 않는다 — 우리가
/// 보여주지 않으면 **사용자는 알림이 온 줄도 모른다.** 무엇을 띄울지 고르는
/// 규칙만 순수 함수로 뽑아 Firebase 없이 고정한다.
RemoteMessage _message({String? title, String? body}) => RemoteMessage(
  notification: (title == null && body == null)
      ? null
      : RemoteNotification(title: title, body: body),
);

void main() {
  test('본문이 있으면 본문을 띄운다', () {
    // 제목은 "출석 알림"처럼 분류에 가깝고 실제 내용은 본문에 있다.
    expect(
      foregroundToastText(_message(title: '출석 알림', body: '정기모임 출석이 시작되었습니다')),
      '정기모임 출석이 시작되었습니다',
    );
  });

  test('본문이 없으면 제목을 띄운다', () {
    expect(foregroundToastText(_message(title: '출석이 시작되었습니다')), '출석이 시작되었습니다');
  });

  test('데이터만 있는 무음 메시지는 아무것도 띄우지 않는다', () {
    // 잡아야 할 잘못된 구현: 빈 문자열을 띄운다 — 사용자가 무슨 일이
    // 일어났는지 모른 채 빈 토스트만 본다.
    expect(foregroundToastText(_message()), isNull);
  });

  test('공백뿐인 문구는 띄우지 않는다', () {
    // 잡아야 할 잘못된 구현: `isNotEmpty`만 보고 공백을 통과시킨다.
    expect(foregroundToastText(_message(title: '   ', body: '  ')), isNull);
  });

  test('본문이 공백뿐이면 제목으로 넘어간다', () {
    expect(foregroundToastText(_message(title: '출석 알림', body: '   ')), '출석 알림');
  });
}
