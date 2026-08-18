import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:beacon_app/features/attendance/data/attendance_dto.dart';
import 'package:beacon_app/features/records/data/records_dto.dart';
import 'package:beacon_app/features/records/presentation/records_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AttendanceRecordItem _record(int day, AttendanceStatus status) => AttendanceRecordItem(
  sessionId: day,
  sessionName: '정기모임',
  date: DateTime.utc(2026, 8, day),
  status: status,
);

void main() {
  // 하루에 세션이 여럿일 때의 우선순위는 Figma에도 명세서에도 없는 규칙이라
  // 구현이 정한 것이다(`mostSevereStatus`의 주석 참고). 위젯 테스트는 인접
  // 쌍을 픽스처로 태우지만, 여기서는 **모든 쌍을 두 순서로** 전부 돌린다 —
  // 우선순위 표의 값 하나만 바꿔도 걸린다.
  test('mostSevereStatus는 결석 > 지각 > 기타 > 출석을 순서와 무관하게 지킨다', () {
    // 잡아야 할 잘못된 구현: 우선순위 표에서 두 상태의 값을 같게 만든다
    // (예: 지각과 기타를 둘 다 1로) — 그러면 결과가 인자 순서에 좌우된다.
    const ascending = <AttendanceStatus>[
      AttendanceStatus.present,
      AttendanceStatus.etc,
      AttendanceStatus.late,
      AttendanceStatus.absent,
    ];

    for (var i = 0; i < ascending.length; i++) {
      for (var j = 0; j < ascending.length; j++) {
        final expected = ascending[i > j ? i : j];
        expect(
          mostSevereStatus([ascending[i], ascending[j]]),
          expected,
          reason: '${ascending[i]} 다음에 ${ascending[j]}',
        );
      }
    }

    // 셋 이상이어도 같다 — `reduce`가 두 개짜리에만 맞게 짜였는지도 본다.
    expect(
      mostSevereStatus(const [
        AttendanceStatus.present,
        AttendanceStatus.etc,
        AttendanceStatus.absent,
        AttendanceStatus.late,
      ]),
      AttendanceStatus.absent,
    );
  });

  testWidgets('기록이 없거나 빈 목록인 날짜는 탭해도 onDayTap이 불리지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: 모든 칸에 `onDayTap`을 그냥 연결한다.
    //
    // 화면 쪽에도 같은 취지의 가드가 있어서, 둘 중 **하나씩만** 지우면
    // 기록 화면 테스트는 전부 통과한다(리뷰 Minor 2). 그래서 캘린더를 따로
    // 세워 이 가드만 단독으로 검사한다. 빈 목록(`[]`)도 함께 태우는 이유는
    // "키가 있으면 기록이 있다"고 보는 구현이 실제로 빈 시트를 열기
    // 때문이다.
    final tapped = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: RecordsCalendar(
            year: 2026,
            month: 8,
            recordsByDay: {
              3: [_record(3, AttendanceStatus.present)],
              4: const <AttendanceRecordItem>[],
            },
            onPreviousMonth: () {},
            onNextMonth: null,
            onDayTap: tapped.add,
          ),
        ),
      ),
    );

    // 키 자체가 없는 날.
    await tester.tap(find.text('7'));
    await tester.pumpAndSettle();
    expect(tapped, isEmpty);

    // 키는 있지만 목록이 빈 날.
    await tester.tap(find.text('4'));
    await tester.pumpAndSettle();
    expect(tapped, isEmpty, reason: '빈 목록도 "기록 없음"이다 — 열면 빈 시트가 뜬다');

    // 대조군 — 기록이 있는 날은 실제로 콜백이 온다(둘 다 안 오면 이 테스트는
    // 아무것도 보증하지 않는다).
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    expect(tapped, [3]);
  });
}
