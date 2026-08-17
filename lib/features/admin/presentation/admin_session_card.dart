import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/time/kst.dart';
import '../data/session_dto.dart';

/// "2026. 04. 07. 오후 6시" — Figma 실측(`353:2155`) 형식.
///
/// KST로 옮겨서 읽는다. 기기 시계를 그대로 쓰면 해외에 있는 관리자에게
/// 세션 시각이 어긋나 보인다(`kst.dart`의 제품 규칙, #43이 홈 화면에서
/// 같은 결함을 고쳤다).
@visibleForTesting
String formatSessionMoment(DateTime value) {
  final kst = toKst(value);
  final month = kst.month.toString().padLeft(2, '0');
  final day = kst.day.toString().padLeft(2, '0');
  final isAfternoon = kst.hour >= 12;
  // 12시는 "오후 12시", 0시는 "오전 12시"다 — `% 12`만 쓰면 둘 다 0이 된다.
  final hour12 = kst.hour % 12 == 0 ? 12 : kst.hour % 12;
  final period = isAfternoon ? '오후' : '오전';
  final minute = kst.minute == 0 ? '' : ' ${kst.minute}분';
  return '${kst.year}. $month. $day. $period $hour12시$minute';
}

/// 진행 중인 세션 카드(Figma `353:2149`).
///
/// 종료된 세션 카드와 배경·강조가 정반대다 — 진행 중은 흰 카드에 출석코드를
/// 크게 띄우고, 종료는 회색 카드에 인원만 남긴다.
class ActiveSessionCard extends StatelessWidget {
  const ActiveSessionCard({
    super.key,
    required this.session,
    required this.otpCode,
    required this.attendeeCount,
    required this.memberCount,
    required this.onEnd,
    this.isEnding = false,
  });

  final AdminSession session;

  /// 세션 시작 응답으로 받은 출석 코드. 아직 못 받았으면 null이다 — 화면을
  /// 다시 열면 서버가 코드를 다시 주지 않으므로(시작은 한 번뿐이다) 그
  /// 경우를 표시로 구분해야 한다.
  final String? otpCode;

  /// 출석으로 기록된 인원. 세는 중이거나 실패하면 null이다.
  final int? attendeeCount;

  /// 동아리 전체 인원. 모르면 null이다.
  final int? memberCount;

  final VoidCallback onEnd;
  final bool isEnding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SessionHeader(
            session: session,
            badgeLabel: '진행 중',
            badgeBackground: colors.bg,
            badgeForeground: colors.sessionActiveBadge,
            badgeStyle: typography.title7,
          ),
          const SizedBox(height: 18),
          _CodeAndAttendance(
            otpCode: otpCode,
            attendeeCount: attendeeCount,
            memberCount: memberCount,
          ),
          const SizedBox(height: 18),
          _EndButton(onPressed: onEnd, isLoading: isEnding),
        ],
      ),
    );
  }
}

/// 종료된 세션 카드(Figma `353:2459`).
class EndedSessionCard extends StatelessWidget {
  const EndedSessionCard({
    super.key,
    required this.session,
    required this.onTap,
    this.onStart,
    this.isStarting = false,
  });

  final AdminSession session;
  final VoidCallback onTap;

  /// 아직 시작하지 않은 세션에만 준다. Figma에는 예정 세션 카드가 없어서
  /// (모바일 디자인은 진행 중·종료 두 종류뿐이다) 종료 카드 모양에 시작
  /// 버튼만 얹었다 — 시작 경로가 없으면 세션을 만들어도 쓸 수 없다.
  final VoidCallback? onStart;

  final bool isStarting;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colors.gray4,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SessionHeader(
              session: session,
              badgeLabel: session.status == SessionStatus.ended ? '종료' : '예정',
              badgeBackground: colors.white,
              badgeForeground: colors.gray2,
              badgeStyle: typography.body3,
            ),
            // 출석인원 자리는 **비워 둔다.** `SessionResponseDto`에 인원이
            // 없고, 세는 유일한 방법(`GET .../attendance`)을 카드마다 부르면
            // 목록 하나에 요청이 N번 나간다. 진행 중 세션만 센다(#14 판정).
            if (onStart != null) ...[
              const SizedBox(height: 16),
              _StartButton(onPressed: onStart!, isLoading: isStarting),
            ],
          ],
        ),
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({required this.onPressed, required this.isLoading});

  final VoidCallback onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return GestureDetector(
      onTap: isLoading ? null : onPressed,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.main,
          borderRadius: BorderRadius.circular(20),
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.white),
                ),
              )
            : Text('출석 시작하기', style: typography.title6.copyWith(color: colors.bg)),
      ),
    );
  }
}

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({
    required this.session,
    required this.badgeLabel,
    required this.badgeBackground,
    required this.badgeForeground,
    required this.badgeStyle,
  });

  final AdminSession session;
  final String badgeLabel;
  final Color badgeBackground;
  final Color badgeForeground;
  final TextStyle badgeStyle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;
    final moment = session.expectStartAt ?? session.startAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                session.sessionName,
                style: typography.title4.copyWith(color: colors.gray3),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: badgeBackground,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(badgeLabel, style: badgeStyle.copyWith(color: badgeForeground)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          // 예정 시각도 실제 시작 시각도 없으면 자리만 비운다 — 임의의
          // 시각을 지어내지 않는다.
          moment == null ? '시간 미정' : formatSessionMoment(moment),
          style: typography.body2.copyWith(color: colors.gray2),
        ),
      ],
    );
  }
}

class _CodeAndAttendance extends StatelessWidget {
  const _CodeAndAttendance({
    required this.otpCode,
    required this.attendeeCount,
    required this.memberCount,
  });

  final String? otpCode;
  final int? attendeeCount;
  final int? memberCount;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(left: 20, right: 20, top: 18, bottom: 26),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('출석코드', style: typography.title7.copyWith(color: colors.gray2)),
              const SizedBox(height: 10),
              Text(
                // 코드를 못 받았으면 대시다. 시작은 한 번뿐이라 화면을 다시
                // 열면 서버가 코드를 다시 주지 않는다.
                otpCode ?? '----',
                style: typography.title3.copyWith(
                  color: colors.main,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 5.5,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('출석인원', style: typography.title7.copyWith(color: colors.gray2)),
              const SizedBox(height: 6),
              Text(
                '${attendeeCount ?? '-'}/${memberCount ?? '-'}',
                style: typography.title3.copyWith(color: colors.gray3),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EndButton extends StatelessWidget {
  const _EndButton({required this.onPressed, required this.isLoading});

  final VoidCallback onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return GestureDetector(
      onTap: isLoading ? null : onPressed,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // 실측(`353:2418`)이 `#FF5D5D`이고 `AppColors.red`와 같은 값이다.
          color: colors.red,
          borderRadius: BorderRadius.circular(20),
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.white),
                ),
              )
            : Text(
                '출석 종료하기',
                style: typography.title6.copyWith(color: colors.white),
              ),
      ),
    );
  }
}
