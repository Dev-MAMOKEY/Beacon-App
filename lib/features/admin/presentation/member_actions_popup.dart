import 'package:flutter/material.dart';

import '../../../components/ui/button.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../data/club_member_repository.dart';

/// 멤버 한 명에 대한 역할 변경·제외.
///
/// 웹(`356:1627`)은 행마다 "제외하기" 버튼을 두지만, 모바일에서 목록을
/// 스크롤하다 실수로 누르면 **되돌릴 수 없다.** 탭 → 이 팝업 → 확인의 두
/// 단계를 둔다.
class MemberActionsPopupContent extends StatelessWidget {
  const MemberActionsPopupContent({
    super.key,
    required this.member,
    required this.isSelf,
    required this.onToggleRole,
    required this.onRemove,
    required this.onCancel,
  });

  final ClubMember member;

  /// 자기 자신인지. 관리자가 스스로를 강등하거나 제외하면 그 동아리에
  /// 관리자가 없어질 수 있고, 되돌릴 방법이 앱 안에 없다.
  final bool isSelf;

  final VoidCallback onToggleRole;
  final VoidCallback onRemove;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;
    final isAdmin = member.role == ClubRole.admin;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          member.name,
          textAlign: TextAlign.center,
          style: typography.title4.copyWith(color: colors.gray3),
        ),
        const SizedBox(height: 4),
        Text(
          member.stdId,
          textAlign: TextAlign.center,
          style: typography.body3.copyWith(color: colors.gray2),
        ),
        const SizedBox(height: 24),
        if (isSelf)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '자기 자신의 역할은 바꾸거나 제외할 수 없습니다.',
              textAlign: TextAlign.center,
              style: typography.body3.copyWith(color: colors.gray2),
            ),
          )
        else ...[
          AppButton(
            label: isAdmin ? '일반 부원으로' : '관리자로',
            size: ButtonSize.md,
            onPressed: onToggleRole,
          ),
          const SizedBox(height: 12),
          AppButton.destructive(label: '동아리에서 제외', size: ButtonSize.md, onPressed: onRemove),
          const SizedBox(height: 12),
        ],
        AppButton.cancel(label: '닫기', size: ButtonSize.md, onPressed: onCancel),
      ],
    );
  }
}

/// 제외 확인. 확인 없이 지우면 되돌릴 방법이 없다.
class MemberRemoveConfirmContent extends StatelessWidget {
  const MemberRemoveConfirmContent({
    super.key,
    required this.member,
    required this.onConfirm,
    required this.onCancel,
  });

  final ClubMember member;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '멤버 제외',
          textAlign: TextAlign.center,
          style: typography.title4.copyWith(color: colors.gray3),
        ),
        const SizedBox(height: 12),
        Text(
          '${member.name}님을 동아리에서 제외할까요?\n출석 기록도 함께 사라지며 되돌릴 수 없습니다.',
          textAlign: TextAlign.center,
          style: typography.body3.copyWith(color: colors.gray2),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: AppButton.cancel(label: '취소', size: ButtonSize.md, onPressed: onCancel),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppButton.destructive(
                label: '제외',
                size: ButtonSize.md,
                onPressed: onConfirm,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
