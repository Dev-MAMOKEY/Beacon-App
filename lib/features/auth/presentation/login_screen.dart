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
    setState(() {
      _isSubmitting = true;
      _formError = null;
    });

    try {
      final tokens = await ref.read(authRepositoryProvider).login(
            stdId: _stdId.text.trim(),
            password: _password.text,
          );
      await ref.read(sessionControllerProvider.notifier).onAuthenticated(tokens);
    } on ApiException catch (error) {
      // 명세서: 어느 필드가 틀렸는지 노출하지 않는다.
      if (mounted) setState(() => _formError = error.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
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
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),
              AppPasswordInput(
                controller: _password,
                label: '비밀번호',
                hint: '비밀번호를 입력해주세요',
                onChanged: (_) => setState(() {}),
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
