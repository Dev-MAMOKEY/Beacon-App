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
    // 재진입 방지: _isSubmitting은 다음 프레임에서야 버튼에 반영되므로, 그
    // 전에 두 번 눌리면 신청 두 개가 나간다 — 회원가입은 계정을 두 개
    // 만들어버릴 수 있어 로그인보다 대가가 크다.
    if (_isSubmitting) return;
    if (!_validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final repository = ref.read(authRepositoryProvider);
      final stdId = _stdId.text.trim();
      final password = _password.text;
      final name = _name.text.trim();

      final signedUp = await _trySignup(repository, stdId: stdId, password: password, name: name);
      if (!signedUp || !mounted) return;

      // 회원가입 자체는 성공했다. 아래 자동 로그인은 별개의 시도다 — 실패해도
      // "회원가입이 실패했다"는 뜻이 아니므로 별도 try로 분리해 다르게
      // 안내한다(둘을 하나의 try로 묶으면 로그인 실패의 원본 메시지가 토스트로
      // 뜨고, 재시도하면 DUPLICATE_STUDENT_ID가 떠서 마치 첫 시도가 실패한
      // 것처럼 보인다).
      await _tryAutoLogin(repository, stdId: stdId, password: password);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// 회원가입 자체를 시도한다. 성공하면 true. 실패는 여기서 전부 화면에
  /// 반영하고 false를 돌려준다 — 호출부는 이후 자동 로그인을 시도하지 않는다.
  Future<bool> _trySignup(
    AuthRepository repository, {
    required String stdId,
    required String password,
    required String name,
  }) async {
    try {
      await repository.signup(stdId: stdId, password: password, name: name);
      return true;
    } on ApiException catch (error) {
      // await 이후에는 화면이 이미 사라졌을 수 있다(예: 사용자가 뒤로 가기).
      // 이미 사라진 화면에 대고 setState/showAppToast(context)를 부르지
      // 않도록 반드시 확인한다 — 특히 showAppToast는 context를 직접 쓴다.
      if (!mounted) return false;
      if (error.code == ErrorCode.duplicateStudentId) {
        setState(() => _stdIdError = '이미 사용 중인 학번입니다');
      } else {
        showAppToast(context, error.message);
      }
      return false;
    }
  }

  /// 회원가입 직후 자동 로그인을 시도한다. 실패해도 계정 자체는 이미
  /// 만들어졌으므로, 그 사실을 분명히 알리고 로그인 화면으로 보낸다 — 실패
  /// 메시지를 그대로 토스트로 띄우면 "회원가입이 실패했다"는 오해를 준다.
  Future<void> _tryAutoLogin(
    AuthRepository repository, {
    required String stdId,
    required String password,
  }) async {
    try {
      final tokens = await repository.login(stdId: stdId, password: password);
      if (!mounted) return;
      await ref.read(sessionControllerProvider.notifier).onAuthenticated(tokens);
      // 명세서: 성공하면 자동 로그인 처리 후 초대코드 화면으로. 이후 화면
      // 전환은 라우터의 redirect가 세션 상태 변화를 구독해 알아서 처리하므로,
      // 여기서 직접 내비게이션을 호출하지 않는다 — 라우터가 이미 다른 곳으로
      // 옮겨버린 뒤에 이 화면이 스스로 내비게이션을 시도하면 경합이 생긴다.
    } on ApiException catch (_) {
      if (!mounted) return;
      // 계정은 이미 만들어졌다 — 로그인 실패의 원본 메시지(예:
      // INVALID_CREDENTIALS)를 그대로 보여주면 회원가입 자체가 실패한
      // 것처럼 보인다. 세션 상태가 바뀌지 않았으므로(로그인에 성공한 적이
      // 없다) 라우터가 대신 옮겨주지 않는다 — 여기서 직접 로그인 화면으로
      // 보낸다.
      showAppToast(context, '계정이 생성되었습니다. 로그인 화면에서 로그인해주세요.');
      context.pop();
    }
  }

  void _clearStdIdError(String _) {
    if (_stdIdError != null) setState(() => _stdIdError = null);
  }

  void _clearNameError(String _) {
    if (_nameError != null) setState(() => _nameError = null);
  }

  void _clearPasswordError(String _) {
    if (_passwordError != null) setState(() => _passwordError = null);
  }

  void _clearPasswordConfirmError(String _) {
    if (_passwordConfirmError != null) setState(() => _passwordConfirmError = null);
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
                onChanged: _clearStdIdError,
              ),
              const SizedBox(height: 20),
              AppInput(
                controller: _name,
                label: '이름',
                hint: '이름을 입력해주세요',
                errorText: _nameError,
                onChanged: _clearNameError,
              ),
              const SizedBox(height: 20),
              AppPasswordInput(
                controller: _password,
                label: '비밀번호',
                hint: '영문과 숫자를 포함해 8자 이상',
                errorText: _passwordError,
                onChanged: _clearPasswordError,
              ),
              const SizedBox(height: 20),
              AppPasswordInput(
                controller: _passwordConfirm,
                label: '비밀번호 확인',
                hint: '비밀번호를 한 번 더 입력해주세요',
                errorText: _passwordConfirmError,
                onChanged: _clearPasswordConfirmError,
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
