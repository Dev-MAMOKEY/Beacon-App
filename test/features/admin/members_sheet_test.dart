import 'package:beacon_app/features/admin/data/club_member_repository.dart';
import 'package:beacon_app/features/admin/presentation/members_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

ClubMember _member({num? rate, int? count}) => ClubMember(
  memberId: 1,
  name: '강네모',
  stdId: '20250001',
  role: ClubRole.member,
  rate: rate,
  attendanceCount: count,
);

void main() {
  group('출석률·횟수 표시', () {
    test('둘 다 있으면 한 줄로 합친다', () {
      // 웹은 "출석률"과 "출석 횟수" 두 열이지만, 모바일에서 두 줄을 쓸 만큼
      // 중요한 값은 아니다.
      expect(formatMemberAttendance(_member(rate: 100, count: 8)), '100% · 8회');
    });

    test('서버가 주지 않은 값은 지어내지 않는다', () {
      // 잡아야 할 잘못된 구현: 없으면 `0%`/`0회`로 채운다 — 출석을 한 번도
      // 안 한 것처럼 보인다. 모르는 것과 0은 다르다.
      expect(formatMemberAttendance(_member()), '');
      expect(formatMemberAttendance(_member(rate: 75)), '75%');
      expect(formatMemberAttendance(_member(count: 3)), '3회');
    });

    test('0은 없는 값과 구별한다', () {
      // 실제로 0%인 사람은 0%로 보여야 한다.
      expect(formatMemberAttendance(_member(rate: 0, count: 0)), '0% · 0회');
    });

    test('소수점은 필요할 때만 붙인다', () {
      // 100.0을 "100.0%"로 쓰면 자리만 차지한다. 반대로 87.5를 "88%"로
      // 반올림하면 웹 화면과 값이 어긋난다.
      expect(formatMemberAttendance(_member(rate: 100.0)), '100%');
      expect(formatMemberAttendance(_member(rate: 87.5)), '87.5%');
      expect(formatMemberAttendance(_member(rate: 33.33)), '33.3%');
    });
  });
}
