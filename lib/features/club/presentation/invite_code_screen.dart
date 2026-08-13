import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../components/ui/button.dart';
import '../../../components/ui/input.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/error_code.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/presentation/session_controller.dart';
import '../data/club_repository.dart';

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
      // 프로필을 다시 읽으면 clubIds가 채워져 라우터가 홈으로 보낸다.
      await ref.read(sessionControllerProvider.notifier).refreshProfile();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _code.clear();
        _error = error.code == ErrorCode.invalidInviteCode
            ? '유효하지 않은 초대코드입니다. 관리자에게 다시 확인해주세요'
            : error.message;
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // 대문자 자동 변환과 지난 제출의 에러 지우기를 함께 처리한다. 프로그램적
  // 대문자 변환(_code.value = ...)이 이 콜백을 다시 부르든 안 부르든 결과가
  // 같도록, 매 호출마다 무조건 _error를 지운다 — 사용자가 코드를 고치기
  // 시작하면 지난 실패 메시지가 더 이상 유효하지 않기 때문이다.
  void _onCodeChanged(String value) {
    final upper = value.toUpperCase();
    if (upper != value) {
      _code.value = TextEditingValue(
        text: upper,
        selection: TextSelection.collapsed(offset: upper.length),
      );
    }
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
