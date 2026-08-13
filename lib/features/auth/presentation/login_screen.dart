import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../components/ui/button.dart';
import '../../../components/ui/input.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../data/auth_repository.dart';
import 'session_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _stdId = TextEditingController();
  final TextEditingController _password = TextEditingController();

  String? _formError;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _stdId.dispose();
    _password.dispose();
    super.dispose();
  }

  // 명세서: 로그인 버튼을 탭하면 두 필드 모두 값이 있는지 확인 후 API를
  // 호출한다. 한쪽만 채워진 채로 호출하면 서버가 INVALID_CREDENTIALS로
  // 응답하고, 화면은 그걸 그대로 보여준다 — 실제로는 "폼이 미완성"인데
  // "자격 증명이 틀렸다"는 오해를 주게 되므로 두 필드를 모두 요구한다.
  bool get _canSubmit =>
      _stdId.text.isNotEmpty && _password.text.isNotEmpty && !_isSubmitting;

  Future<void> _submit() async {
    if (_isSubmitting) return; // 재진입 방지: 프레임이 갱신되기 전에 두 번 눌리면 중복 호출된다.

    setState(() {
      _isSubmitting = true;
      _formError = null;
    });

    try {
      final tokens = await ref.read(authRepositoryProvider).login(
            stdId: _stdId.text.trim(),
            password: _password.text,
          );
      // await 이후에는 화면이 이미 사라졌을 수 있다(예: 사용자가 뒤로 가기).
      // 이미 사라진 화면을 대신해 세션을 바꾸거나 이후 콜백에서 그 화면의
      // context/컨트롤러를 건드리지 않도록, ref를 다시 쓰기 전에 반드시
      // mounted를 확인한다.
      if (!mounted) return;
      await ref.read(sessionControllerProvider.notifier).onAuthenticated(tokens);
    } on ApiException catch (error) {
      // 명세서: 어느 필드가 틀렸는지 노출하지 않는다.
      if (mounted) setState(() => _formError = error.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // 두 필드 onChanged가 공유한다: _canSubmit이 매 입력마다 다시 계산되도록
  // 항상 rebuild를 트리거하고, 동시에 지난 제출의 화면 단위 에러가 남아있지
  // 않도록 지운다 — 안 그러면 실패 메시지가 다음 입력이 있어도 사라지지
  // 않고 다음 제출 전까지 그대로 남는다.
  void _onFieldChanged(String _) {
    setState(() => _formError = null);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              Text('Beacon', style: typography.title3.copyWith(color: colors.main)),
              const SizedBox(height: 40),
              AppInput(
                controller: _stdId,
                label: '학번',
                hint: '학번을 입력해주세요',
                onChanged: _onFieldChanged,
              ),
              const SizedBox(height: 20),
              AppPasswordInput(
                controller: _password,
                label: '비밀번호',
                hint: '비밀번호를 입력해주세요',
                onChanged: _onFieldChanged,
              ),
              if (_formError != null) ...[
                const SizedBox(height: 16),
                Text(
                  _formError!,
                  style: typography.body3.copyWith(color: colors.red),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 32),
              AppButton(
                label: '로그인',
                isLoading: _isSubmitting,
                onPressed: _canSubmit ? _submit : null,
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => context.push(AppRoutes.signup),
                child: Text(
                  '회원가입',
                  textAlign: TextAlign.center,
                  style: typography.body3.copyWith(color: colors.gray2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
