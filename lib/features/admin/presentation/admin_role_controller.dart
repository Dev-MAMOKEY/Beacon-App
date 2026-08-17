import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/session_controller.dart';
import '../data/club_member_repository.dart';

/// 지금 로그인한 사용자가 **현재 동아리의 관리자인지**.
///
/// `GET /members/me`(`MemberProfile`)에는 role이 없다 — role은
/// `GET /clubs/{clubId}/members`의 항목에만 있다. 그리고 그 프로필에는
/// `memberId`도 없어서, 목록에서 나를 찾는 키는 **학번(`stdId`)** 뿐이다.
///
/// 실패하면 `false`다. 관리자 여부를 확인하지 못한 상태에서 관리자 탭을
/// 열어 주면, 부원에게 세션 시작·종료 버튼을 보여준 뒤 서버가 403으로
/// 거절하는 모습이 된다 — 확인되기 전까지는 없는 것으로 다룬다.
final isClubAdminProvider = FutureProvider<bool>((ref) async {
  final session = await ref.watch(sessionControllerProvider.future);
  if (session is! SessionReady) return false;

  final profile = session.profile;
  final clubId = profile.clubIds.firstOrNull;
  if (clubId == null) return false;

  try {
    final members = await ref.watch(clubMemberRepositoryProvider).fetchMembers(clubId);
    final me = members.where((member) => member.stdId == profile.stdId).firstOrNull;
    return me?.role == ClubRole.admin;
  } catch (_) {
    // 조회 실패·파싱 실패 모두 "관리자가 아니다"로 수렴시킨다. 관리자 탭이
    // 잠깐 안 보이는 것이, 부원에게 관리자 화면을 열어 주는 것보다 낫다.
    return false;
  }
});

/// 현재 동아리의 전체 인원 수. 관리자 화면의 "출석인원 14/**15**"에서
/// 분모가 되는 값이다.
///
/// 세션 응답(`SessionResponseDto`)에는 인원 정보가 전혀 없어서 이 목록의
/// 길이가 유일한 출처다.
final clubMemberCountProvider = FutureProvider<int?>((ref) async {
  final session = await ref.watch(sessionControllerProvider.future);
  if (session is! SessionReady) return null;

  final clubId = session.profile.clubIds.firstOrNull;
  if (clubId == null) return null;

  try {
    final members = await ref.watch(clubMemberRepositoryProvider).fetchMembers(clubId);
    return members.length;
  } catch (_) {
    // 분모를 모르면 화면이 "14/-"로 그린다 — 틀린 분모를 지어내지 않는다.
    return null;
  }
});
