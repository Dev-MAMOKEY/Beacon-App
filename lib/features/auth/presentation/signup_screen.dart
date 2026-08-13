import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../components/ui/button.dart';
import '../../../components/ui/input.dart';
import '../../../components/ui/toast.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/error_code.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../data/auth_repository.dart';
import 'auth_form_validator.dart';
import 'session_controller.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final TextEditingController _stdId = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _passwordConfirm = TextEditingController();

  String? _stdIdError;
  String? _nameError;
  String? _passwordError;
  String? _passwordConfirmError;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _stdId.dispose();
    _name.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    super.dispose();
  }

  bool _validate() {
    setState(() {
      _stdIdError = AuthFormValidator.stdId(_stdId.text.trim());
      _nameError = AuthFormValidator.name(_name.text.trim());
      _passwordError = AuthFormValidator.password(_password.text);
      _passwordConfirmError = AuthFormValidator.passwordConfirm(
        _password.text,
        _passwordConfirm.text,
      );
    });
    return _stdIdError == null &&
        _nameError == null &&
        _passwordError == null &&
        _passwordConfirmError == null;
  }

  Future<void> _submit() async {
    if (!_validate()) return;

    setState(() => _isSubmitting = true);
    final repository = ref.read(authRepositoryProvider);

    try {
      await repository.signup(
        stdId: _stdId.text.trim(),
        password: _password.text,
        name: _name.text.trim(),
      );
      // 명세서: 성공하면 자동 로그인 처리 후 초대코드 화면으로.
      // onAuthenticated는 세션 상태를 갱신할 뿐 예외를 밖으로 던지지 않는다
      // (SessionUnavailable로 흡수한다) — 이후 화면 전환은 라우터의 redirect가
      // 세션 상태 변화를 구독해 알아서 처리하므로, 여기서 직접 context.pop() 등
      // 내비게이션을 호출하지 않는다. 라우터가 이미 다른 곳으로 옮겨버린 뒤에
      // 이 화면이 스스로 내비게이션을 시도하면 경합이 생길 수 있다.
      final tokens = await repository.login(
        stdId: _stdId.text.trim(),
        password: _password.text,
      );
      await ref.read(sessionControllerProvider.notifier).onAuthenticated(tokens);
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == ErrorCode.duplicateStudentId) {
        setState(() => _stdIdError = '이미 사용 중인 학번입니다');
      } else {
        showAppToast(context, error.message);
      }
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
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.gray3),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('회원가입', style: typography.title3.copyWith(color: colors.gray3)),
              const SizedBox(height: 32),
              AppInput(
                controller: _stdId,
                label: '학번',
                hint: '학번을 입력해주세요',
                errorText: _stdIdError,
              ),
              const SizedBox(height: 20),
              AppInput(
                controller: _name,
                label: '이름',
                hint: '이름을 입력해주세요',
                errorText: _nameError,
              ),
              const SizedBox(height: 20),
              AppPasswordInput(
                controller: _password,
                label: '비밀번호',
                hint: '영문과 숫자를 포함해 8자 이상',
                errorText: _passwordError,
              ),
              const SizedBox(height: 20),
              AppPasswordInput(
                controller: _passwordConfirm,
                label: '비밀번호 확인',
                hint: '비밀번호를 한 번 더 입력해주세요',
                errorText: _passwordConfirmError,
              ),
              const SizedBox(height: 32),
              AppButton(
                label: '회원가입',
                isLoading: _isSubmitting,
                onPressed: _isSubmitting ? null : _submit,
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => context.pop(),
                child: Text(
                  '이미 계정이 있으신가요? 로그인',
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
