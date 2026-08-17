import 'package:flutter/material.dart';

import '../../../components/ui/input.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../data/club_member_repository.dart';

/// 관리자 멤버 관리.
///
/// **웹 디자인(`356:1627`)을 모바일로 옮긴 것이다.** 웹은 6열 표
/// (이름·학번·역할·출석률·출석 횟수·제외)인데 390px에 들어가지 않는다.
///
/// | 웹 열 | 모바일 |
/// |---|---|
/// | 이름·학번 | 행 왼쪽 위아래 |
/// | 역할 | **파트**(`part`)다 — `role`(ADMIN/MEMBER)과 다른 필드다. 이름 옆 배지 |
/// | 출석률·출석 횟수 | 행 오른쪽 한 줄로 합침 |
/// | 제외 | 행을 탭 → 액션 팝업(역할 변경·제외) |
///
/// 웹의 "제외하기" 버튼을 행마다 두지 않은 이유: 모바일에서 목록을
/// 스크롤하다 실수로 누르면 되돌릴 수 없다. 탭 → 팝업 → 확인 두 단계를 둔다.
class MembersSheetContent extends StatelessWidget {
  const MembersSheetContent({
    super.key,
    required this.members,
    required this.searchController,
    required this.onSearchChanged,
    required this.onTapMember,
    this.isLoading = false,
    this.loadFailed = false,
  });

  final List<ClubMember> members;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<ClubMember> onTapMember;
  final bool isLoading;
  final bool loadFailed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('멤버 관리', style: typography.title4.copyWith(color: colors.gray3)),
        const SizedBox(height: 16),
        AppInput(
          controller: searchController,
          hint: '이름 또는 학번으로 검색',
          onChanged: onSearchChanged,
        ),
        const SizedBox(height: 16),
        if (isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (loadFailed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                '멤버를 불러오지 못했습니다',
                style: typography.body2.copyWith(color: colors.gray2),
              ),
            ),
          )
        else if (members.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                '조건에 맞는 멤버가 없습니다',
                style: typography.body2.copyWith(color: colors.gray2),
              ),
            ),
          )
        else
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: members.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: colors.gray4),
              itemBuilder: (context, index) => _MemberRow(
                member: members[index],
                onTap: () => onTapMember(members[index]),
              ),
            ),
          ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.onTap});

  final ClubMember member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          member.name,
                          style: typography.body2.copyWith(color: colors.gray3),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // 관리자는 눈에 띄어야 한다 — 역할을 바꾸려면 누가
                      // 이미 관리자인지 먼저 보여야 한다.
                      if (member.role == ClubRole.admin) ...[
                        const SizedBox(width: 6),
                        _Badge(label: '관리자', background: colors.bg, foreground: colors.sessionActiveBadge),
                      ],
                      if (member.part != null && member.part!.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _Badge(label: member.part!, background: colors.gray4, foreground: colors.gray2),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(member.stdId, style: typography.body4.copyWith(color: colors.gray2)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              // 출석률과 횟수를 한 줄로 합친다 — 웹은 두 열이지만 모바일에서
              // 두 줄을 쓸 만큼 중요한 값은 아니다.
              formatMemberAttendance(member),
              style: typography.body4.copyWith(color: colors.gray2),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.background, required this.foreground});

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: typography.body4.copyWith(color: foreground)),
    );
  }
}

/// "100% · 8회" — 웹의 "출석률"과 "출석 횟수" 두 열을 한 줄로.
///
/// 서버가 주지 않은 값은 지어내지 않는다. 둘 다 없으면 빈 문자열이라
/// 행에 아무것도 붙지 않는다 — `0%`로 채우면 출석을 한 번도 안 한 것처럼
/// 보인다.
String formatMemberAttendance(ClubMember member) {
  final parts = <String>[];
  final rate = member.rate;
  if (rate != null) {
    // 100.0 같은 값을 "100%"로 — 소수점이 필요 없으면 붙이지 않는다.
    final rounded = rate.toDouble();
    final text = rounded == rounded.roundToDouble()
        ? rounded.round().toString()
        : rounded.toStringAsFixed(1);
    parts.add('$text%');
  }
  final count = member.attendanceCount;
  if (count != null) parts.add('$count회');
  return parts.join(' · ');
}
