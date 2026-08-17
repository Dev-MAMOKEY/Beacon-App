import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../components/ui/button.dart';
import '../../../components/ui/input.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/error_code.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/presentation/auth_form_validator.dart';
import '../data/profile_repository.dart';

/// 세 입력 칸을 테스트가 **개별적으로** 지목할 수 있게 하는 키.
///
/// 요구사항 7("현재 비밀번호 불일치는 그 필드 하단에 인라인")은 "메시지가
/// 어딘가에 보인다"로는 검증되지 않는다 — 화면 단위 메시지도, 토스트도,
/// 새 비밀번호 칸 아래에 붙인 것도 전부 그 검사를 통과한다. 메시지가
/// **이 키를 가진 위젯의 자손**인지를 봐야 그 셋을 구분할 수 있다.
const Key passwordChangeCurrentFieldKey = Key('password_change_current');
const Key passwordChangeNewFieldKey = Key('password_change_new');
const Key passwordChangeConfirmFieldKey = Key('password_change_confirm');

/// 비밀번호 변경 팝업(Figma `353:1661` "비밀번호 변경 팝업", 342×478).
///
/// **이것은 화면이 아니라 팝업이다.** 계획서는 `/profile/password` 라우트의
/// 별도 화면을 상정했지만 Figma에는 그런 프레임이 없다 — 파일 전체에서
/// 390×844 모바일 프레임은 온보딩/로그인/회원가입/초대코드/홈×2/기록/
/// 마이×2/관리자뿐이고, 비밀번호 변경은 `이름 변경 팝업`(`353:1646`)·
/// `출석코드 팝업창`(`339:1683`)과 같은 줄에 놓인 342폭 카드다. 모서리
/// 반경 32·패딩 32도 `AppPopupCard`(=다른 팝업들)와 정확히 같고, 화면이라면
/// 있을 수 없는 `취소` 버튼이 `변경하기`와 나란히 있다.
///
/// 자기 상태(입력값·에러·제출 중)를 스스로 들고 있다. 홈 화면의 출석코드
/// 팝업이 `ChangeNotifier` + `ListenableBuilder`를 쓴 이유는 **호출 화면의**
/// 상태가 팝업을 움직여야 했기 때문인데, 이 팝업은 그럴 필요가 없다 —
/// 다이얼로그 라우트 안의 이 위젯 자신이 상태의 주인이라 `setState`가 그대로
/// 듣는다. 반대로 닫기는 스스로 하지 않는다: 라우트 객체를 소유한
/// `ProfileScreen`이 정체성으로 닫는다([onCancel]/[onChanged]).
class PasswordChangePopupContent extends ConsumerStatefulWidget {
  const PasswordChangePopupContent({
    super.key,
    required this.onCancel,
    required this.onChanged,
  });

  /// 취소를 눌렀다. 호출자가 이 팝업 라우트를 닫는다.
  final VoidCallback onCancel;

  /// 서버가 변경을 확정했다. 호출자가 팝업을 닫고 토스트를 띄운다.
  final VoidCallback onChanged;

  @override
  ConsumerState<PasswordChangePopupContent> createState() =>
      _PasswordChangePopupContentState();
}

class _PasswordChangePopupContentState
    extends ConsumerState<PasswordChangePopupContent> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  String? _currentError;
  String? _nextError;
  String? _confirmError;

  /// 어느 칸에도 귀속되지 않는 서버 오류(네트워크 단절, 5xx 등). 토스트가
  /// 아니라 팝업 안에 두는 이유는 팝업의 스크림이 화면을 덮고 있어 그 아래
  /// 뜨는 `SnackBar`가 가려지기 때문이다.
  String? _formError;

  bool _submitting = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // 재진입 방지 — 버튼의 로딩 상태는 다음 프레임에야 반영되므로 그 사이에
    // 두 번 눌릴 수 있다(`login_screen.dart`와 같은 이유).
    if (_submitting) return;

    final current = _current.text;
    final next = _next.text;
    final confirm = _confirm.text;

    // 새 비밀번호 규칙은 Phase 1의 `AuthFormValidator`가 정본이다 — 여기서
    // 다시 쓰지 않는다. 현재 비밀번호에는 그 규칙을 **적용하지 않는다**:
    // 규칙이 생기기 전에 만들어진 계정의 비밀번호가 규칙을 만족하지 않을 수
    // 있고, 그러면 정작 바꾸려는 사람을 클라이언트가 막아버린다. 맞는지는
    // 서버만 안다.
    final currentError = current.isEmpty ? '현재 비밀번호를 입력해주세요' : null;
    final nextError = AuthFormValidator.password(next);
    final confirmError = AuthFormValidator.passwordConfirm(next, confirm);

    setState(() {
      _currentError = currentError;
      _nextError = nextError;
      _confirmError = confirmError;
      _formError = null;
    });
    if (currentError != null || nextError != null || confirmError != null) {
      return;
    }

    setState(() => _submitting = true);

    try {
      await ref
          .read(profileRepositoryProvider)
          .changePassword(
            currentPassword: current,
            newPassword: next,
            confirmNewPassword: confirm,
          );
    } catch (error) {
      // `await` 뒤에는 이 팝업이 이미 닫혔을 수 있다(탭 전환으로 호출 화면이
      // 팝업을 회수하는 경로가 실제로 있다).
      //
      // `on ApiException`만 잡으면 그 밖의 예외(파싱 실패 등)가 새어
      // `_submitting`이 참으로 굳는다. 이 팝업은 `barrierDismissible: false`라
      // 확인은 로딩, 취소는 비활성인 채로 **닫을 수 없는 팝업**이 된다
      // (리뷰 Important 3).
      if (!mounted) return;
      setState(() {
        _submitting = false;
        if (error is! ApiException) {
          _formError = '비밀번호를 바꾸지 못했어요.';
        } else if (error.code == ErrorCode.invalidCredentials) {
          // 요구사항 7 — 해당 칸 아래 인라인이다.
          //
          // 서버 문구를 그대로 쓰지 않는 이유: `INVALID_CREDENTIALS`는
          // 로그인이 쓰는 코드이기도 해서 그 메시지가 "학번 또는 비밀번호가
          // 올바르지 않습니다" 계열이다 — 학번을 입력한 적도 없는 이 팝업에
          // 그대로 띄우면 사용자가 엉뚱한 곳을 고치려 든다.
          _currentError = '현재 비밀번호가 올바르지 않습니다';
        } else {
          _formError = error.message;
        }
      });
      return;
    }

    if (!mounted) return;
    setState(() => _submitting = false);
    widget.onChanged();
  }

  /// 입력이 바뀌면 그 칸의 에러만 지운다 — 고치는 중인 칸에 옛 메시지가
  /// 붙어 있으면 무엇이 문제인지 알 수 없다.
  void _clearError(void Function() clear) {
    setState(() {
      clear();
      _formError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    // 제출 중에는 시스템 뒤로가기로도 닫히지 않아야 한다. 취소 버튼은 이미
    // 비활성이지만 안드로이드 뒤로가기는 그대로 통했고, 그렇게 빠져나가면
    // 팝업 콘텐츠가 dispose돼 `await` 뒤 `mounted` 가드에 막혀 `onChanged`가
    // 불리지 않는다 — **서버는 바뀌었는데 아무 확인도 못 받는다**
    // (리뷰 Important 2).
    return PopScope(
      canPop: !_submitting,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '비밀번호 변경',
              textAlign: TextAlign.center,
              style: typography.title4.copyWith(color: colors.gray3),
            ),
            const SizedBox(height: 24),
            AppPasswordInput(
              key: passwordChangeCurrentFieldKey,
              controller: _current,
              // Figma는 이 칸의 라벨/플레이스홀더를 "학번 입력"/"학번을
              // 입력하세요"로 그려 뒀지만, 그 칸의 아이콘은 `id-card-line`이
              // 아니라 나머지 둘과 같은 `lock-line`이고(아이콘 컴포넌트
              // `317:1461`에 `id-card-line`이 따로 있는데도 쓰지 않았다),
              // `PATCH /members/me/password`의 본문에는 학번 필드 자체가 없다
              // (`{currentPassword, newPassword, confirmNewPassword}`).
              // 로그인 화면의 입력 칸을 복제해 만들고 문구만 안 고친 흔적이라
              // 판단해 의미대로 옮겼다 — 2·3번 칸이 둘 다 "비밀번호 입력"으로
              // 똑같은 것도 같은 흔적이다. **조정자 판정 대상으로 보고했다.**
              label: '현재 비밀번호',
              hint: '현재 비밀번호를 입력하세요',
              errorText: _currentError,
              prefix: _LockIcon(color: colors.gray1),
              onChanged: (_) => _clearError(() => _currentError = null),
            ),
            const SizedBox(height: 24),
            AppPasswordInput(
              key: passwordChangeNewFieldKey,
              controller: _next,
              label: '새 비밀번호',
              hint: '새 비밀번호를 입력하세요',
              errorText: _nextError,
              prefix: _LockIcon(color: colors.gray1),
              onChanged: (_) => _clearError(() => _nextError = null),
            ),
            const SizedBox(height: 24),
            AppPasswordInput(
              key: passwordChangeConfirmFieldKey,
              controller: _confirm,
              label: '새 비밀번호 확인',
              hint: '새 비밀번호를 다시 입력하세요',
              errorText: _confirmError,
              prefix: _LockIcon(color: colors.gray1),
              onChanged: (_) => _clearError(() => _confirmError = null),
            ),
            if (_formError != null) ...[
              const SizedBox(height: 16),
              Text(
                _formError!,
                textAlign: TextAlign.center,
                style: typography.body3.copyWith(color: colors.red),
              ),
            ],
            const SizedBox(height: 24),
            PopupActionButtons(
              cancelLabel: '취소',
              confirmLabel: '변경하기',
              onCancel: _submitting ? null : widget.onCancel,
              onConfirm: _submit,
              isLoading: _submitting,
            ),
          ],
        ),
      ),
    );
  }
}

/// 입력 칸 왼쪽의 자물쇠(Figma `317:1444` `lock-line`). 실측 색은
/// `#B4B4B5`(=`gray1`)다.
class _LockIcon extends StatelessWidget {
  const _LockIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/icons/lock-line.svg',
      width: 24,
      height: 24,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

/// 팝업 아래쪽의 취소/실행 2단 버튼(Figma `353:1907` "수정 취소 버튼",
/// `353:1685` "변경 취소 버튼"). 두 팝업이 같은 구성을 쓴다 — 폭 비율
/// 0.40 : 0.60, 사이 12.
class PopupActionButtons extends StatelessWidget {
  const PopupActionButtons({
    super.key,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
    this.isLoading = false,
  });

  final String cancelLabel;
  final String confirmLabel;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 40,
          child: AppButton.cancel(label: cancelLabel, onPressed: onCancel),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 60,
          child: AppButton(
            label: confirmLabel,
            isLoading: isLoading,
            onPressed: onConfirm,
          ),
        ),
      ],
    );
  }
}
