import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

class AppInput extends StatelessWidget {
  const AppInput({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.errorText,
    this.obscure = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.maxLength,
    this.suffix,
    this.onChanged,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final String? errorText;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int? maxLength;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;
    final hasError = errorText != null && errorText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!, style: typography.title7.copyWith(color: colors.gray2)),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          maxLength: maxLength,
          style: typography.body2.copyWith(color: colors.gray3),
          onChanged: onChanged,
          decoration: InputDecoration(
            counterText: '',
            hintText: hint,
            hintStyle: typography.body2.copyWith(color: colors.gray1),
            filled: true,
            fillColor: colors.white,
            suffixIcon: suffix,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: hasError ? colors.red : colors.gray4),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: hasError ? colors.red : colors.main,
                width: 2,
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Text(errorText!, style: typography.body3.copyWith(color: colors.red)),
        ],
      ],
    );
  }
}

/// 표시/숨김 토글을 내장한 비밀번호 입력.
class AppPasswordInput extends StatefulWidget {
  const AppPasswordInput({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.errorText,
    this.onChanged,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  State<AppPasswordInput> createState() => _AppPasswordInputState();
}

class _AppPasswordInputState extends State<AppPasswordInput> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    return AppInput(
      controller: widget.controller,
      label: widget.label,
      hint: widget.hint,
      errorText: widget.errorText,
      obscure: _obscured,
      onChanged: widget.onChanged,
      suffix: IconButton(
        icon: Icon(
          _obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          color: colors.gray1,
        ),
        onPressed: () => setState(() => _obscured = !_obscured),
        tooltip: _obscured ? '비밀번호 표시' : '비밀번호 숨김',
      ),
    );
  }
}
