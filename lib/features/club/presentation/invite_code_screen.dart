import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../components/ui/button.dart';
import '../../../components/ui/input.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/error_code.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/presentation/session_controller.dart';
import '../data/club_repository.dart';

/// 대문자로 바꾸되 선택 영역과 IME 조합(composing) 구간은 그대로 보존한다.
/// `TextEditingController.value`를 직접 새로 만들어 덮어쓰면 캐럿이 항상
/// 끝으로 튀고 조합 중이던 글자가 끊기므로, 포매터 체인 안에서 텍스트만
/// 바꾼다. 이 포매터보다 먼저 적용되는 `FilteringTextInputFormatter.allow`가
/// A-Z/a-z/0-9만 남기므로 여기서 하는 `toUpperCase()`는 항상 길이를
/// 보존한다(독일어 ß→SS처럼 길이가 늘어나는 대소문자 변환은 애초에 입력에
/// 남아있는 문자 범위 밖이라 들어올 수 없다) — 그래서 원래 selection/
/// composing 오프셋을 그대로 재사용해도 안전하다.
class _UpperCaseTextFormatter extends TextInputFormatter {
  const _UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
      composing: newValue.composing,
    );
  }
}

/// 명세서: 스킵 불가 화면. 동아리 소속이 없으면 여기서 막힌다.
class InviteCodeScreen extends ConsumerStatefulWidget {
  const InviteCodeScreen({super.key});

  static const int codeLength = 6;

  @override
  ConsumerState<InviteCodeScreen> createState() => _InviteCodeScreenState();
}

class _InviteCodeScreenState extends ConsumerState<InviteCodeScreen> {
  final TextEditingController _code = TextEditingController();

  String? _error;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _code.text.length == InviteCodeScreen.codeLength && !_isSubmitting;

  Future<void> _submit() async {
    // 재진입 방지: _isSubmitting은 다음 프레임에 가서야 버튼의 disabled에
    // 반영된다. 그 전에 두 번 탭하면(같은 프레임 안에서) 가입 요청이 중복
    // 전송될 수 있으므로 함수 진입 시점에 한 번 더 막는다.
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await ref.read(clubRepositoryProvider).joinByInviteCode(_code.text);
      // await 이후에는 화면이 이미 사라졌을 수 있다(예: 세션이 다른 경로로
      // 이미 갱신되어 라우터가 이 화면을 밀어냈다). 이미 사라진 화면을
      // 대신해 세션을 바꾸지 않도록, ref를 다시 쓰기 전에 반드시 mounted를
      // 확인한다.
      if (!mounted) return;
      await _advanceAfterJoin();
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == ErrorCode.alreadyClubMember) {
        // 이미 그 동아리의 멤버라는 응답은 가입이 실제로는 이뤄졌다는
        // 긍정적 증거다 — 예를 들어 서버는 가입을 커밋했는데 응답이 유실돼
        // 클라이언트가 실패로 보고, 사용자가 같은 코드로 재시도한 경우다.
        // 성공 경로와 동일하게 처리해 세션을 다시 읽어 홈으로 보낸다.
        await _advanceAfterJoin();
        return;
      }
      setState(() {
        // 코드 자체가 잘못됐을 때만 입력을 비운다. 그 외 에러(네트워크
        // 단절, 서버 오류 등)에서 입력을 지우면 사용자가 처음부터 다시
        // 타이핑해야 하는데, 방금 입력한 코드가 실제로는 맞는 코드였을 수
        // 있다 — 지우는 건 적대적이다.
        if (error.code == ErrorCode.invalidInviteCode) {
          _code.clear();
        }
        _error = error.code == ErrorCode.invalidInviteCode
            ? '유효하지 않은 초대코드입니다. 관리자에게 다시 확인해주세요'
            : error.message;
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// 가입 성공, 또는 ALREADY_CLUB_MEMBER처럼 성공과 동등하게 취급하는
  /// 경우의 공통 후속 처리. 프로필을 다시 읽으면 clubIds가 채워져 라우터가
  /// 홈으로 보낸다.
  Future<void> _advanceAfterJoin() {
    return ref.read(sessionControllerProvider.notifier).refreshProfile();
  }

  // 대문자 변환은 이제 TextInputFormatter(_UpperCaseTextFormatter)가 맡는다
  // — 선택 영역과 IME 조합 구간을 보존하기 위해서다. 여기서는 지난 제출의
  // 에러 메시지만 지운다 — 사용자가 코드를 고치기 시작하면 지난 실패
  // 메시지는 더 이상 유효하지 않다.
  void _onCodeChanged(String value) {
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 80),
              Text(
                '관리자에게 받은\n초대코드를 입력해주세요',
                style: typography.title3.copyWith(color: colors.gray3),
              ),
              const SizedBox(height: 40),
              AppInput(
                controller: _code,
                hint: '초대코드 6자리',
                errorText: _error,
                maxLength: InviteCodeScreen.codeLength,
                textCapitalization: TextCapitalization.characters,
                // 순서가 중요하다: 먼저 영문/숫자만 남기고(그래야 이모지·공백처럼
                // UTF-16 길이와 사용자 체감 글자 수가 어긋나는 입력이 애초에
                // 들어오지 못한다 — 6자리 판정은 String.length를 쓴다), 그다음
                // 대문자로 바꾼다. FilteringTextInputFormatter는 SDK 제공
                // 구현이라 걸러낸 만큼 선택 영역을 알아서 맞춰준다.
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                  const _UpperCaseTextFormatter(),
                ],
                onChanged: _onCodeChanged,
              ),
              const Spacer(),
              AppButton(
                label: '확인',
                isLoading: _isSubmitting,
                onPressed: _canSubmit ? _submit : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
