import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.prefix,
    this.suffix,
    this.onChanged,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final String? errorText;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int? maxLength;

  /// 글자 앞에 오는 24×24 아이콘. Figma "입력 칸" 컴포넌트(`317:1435`)는
  /// 항상 왼쪽에 아이콘을 달고 있다 — 마이페이지(#13)의 이름/비밀번호 변경
  /// 팝업이 처음으로 그것을 그대로 옮긴다. 장식이라 [Semantics]에는 들어가지
  /// 않는다(필드의 접근성 라벨은 [label]과 [errorText]가 만든다).
  final Widget? prefix;

  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;
    final hasError = errorText != null && errorText!.isNotEmpty;

    // 스크린리더가 포커스를 옮겼을 때 라벨과 에러를 필드 자체와 함께 읽도록
    // 별개의 Text 노드가 아니라 필드의 Semantics label로 합친다.
    final String? semanticLabel = hasError
        ? (label != null ? '$label, $errorText' : errorText)
        : label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          ExcludeSemantics(
            // Figma 실측(`317:1515`): 라벨은 gray2가 아니라 gray3다.
            child: Text(label!, style: typography.title7.copyWith(color: colors.gray3)),
          ),
          const SizedBox(height: 8),
        ],
        Semantics(
          label: semanticLabel,
          child: TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization,
            maxLength: maxLength,
            inputFormatters: inputFormatters,
            style: typography.body2.copyWith(color: colors.gray3),
            onChanged: onChanged,
            decoration: InputDecoration(
              counterText: '',
              hintText: hint,
              // Figma 실측(`317:1435`): 힌트는 gray1이 아니라 **gray3의 40%**이고
              // 크기도 body2(16)가 아니라 body3(14)다.
              hintStyle: typography.body3.copyWith(
                color: colors.gray3.withValues(alpha: 0.4),
              ),
              filled: true,
              fillColor: colors.white,
              prefixIcon: prefix == null
                  ? null
                  : Padding(
                      // Figma `317:1435` 실측 — 좌 패딩 16, 아이콘과 글자
                      // 사이 16. 아이콘 자체 크기를 건드리지 않도록
                      // prefixIconConstraints의 최소값을 풀어 둔다(기본값
                      // 48×48은 필드 높이를 밀어 올린다).
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: prefix,
                    ),
              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
              suffixIcon: suffix,
              contentPadding: EdgeInsets.only(
                // prefix가 있으면 왼쪽 여백은 그 Padding이 이미 만든다.
                left: prefix == null ? 16 : 0,
                right: 16,
                top: 18,
                bottom: 18,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: hasError ? colors.red : colors.gray4),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: hasError ? colors.red : colors.main,
                  width: 2,
                ),
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          ExcludeSemantics(
            child: Text(errorText!, style: typography.body3.copyWith(color: colors.red)),
          ),
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
    this.prefix,
    this.onChanged,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final String? errorText;
  final Widget? prefix;
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
      prefix: widget.prefix,
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
