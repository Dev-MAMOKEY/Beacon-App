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

  // 로그인은 회원가입과 달리 필드별 형식 검증을 하지 않는다 — 학번/비밀번호의
  // 옳고 그름은 서버만 판정하고 화면은 화면 단위 메시지로만 보여준다(명세서
  // 보안 권장 방식). 그래서 버튼도 "완전히 빈 폼"만 막는다: 두 필드 모두
  // 채워야 활성화되도록 AND로 좁히면, 두 번째 필드에 입력하는 동안에는
  // setState가 아직 반영되지 않아 버튼이 눌리지 않는 짧은 순간이 늘 생긴다.
  bool get _canSubmit =>
      (_stdId.text.isNotEmpty || _password.text.isNotEmpty) && !_isSubmitting;

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
