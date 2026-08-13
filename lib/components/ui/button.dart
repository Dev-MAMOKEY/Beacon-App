import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

enum ButtonVariant { primary, destructive, ghost }

enum ButtonSize { md, lg }

@immutable
class AppButtonStyle {
  const AppButtonStyle({
    required this.background,
    required this.foreground,
    required this.height,
    required this.textStyle,
  });

  final Color background;
  final Color foreground;
  final double height;
  final TextStyle textStyle;
}

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = ButtonVariant.primary,
    this.size = ButtonSize.lg,
    this.isLoading = false,
  });

  const AppButton.destructive({
    super.key,
    required this.label,
    this.onPressed,
    this.size = ButtonSize.lg,
    this.isLoading = false,
  }) : variant = ButtonVariant.destructive;

  const AppButton.ghost({
    super.key,
    required this.label,
    this.onPressed,
    this.size = ButtonSize.lg,
    this.isLoading = false,
  }) : variant = ButtonVariant.ghost;

  static const double radius = 12;

  final String label;
  final VoidCallback? onPressed;
  final ButtonVariant variant;
  final ButtonSize size;
  final bool isLoading;

  bool get _isEnabled => onPressed != null && !isLoading;

  @override
  Widget build(BuildContext context) {
    final style = resolveButtonStyle(context, variant, size, enabled: _isEnabled);

    return Semantics(
      button: true,
      enabled: _isEnabled,
      label: label,
      // 자식 Text가 라벨을 다시 읽지 않도록 이 노드의 속성만 남긴다. 대신
      // GestureDetector가 잃는 tap 액션을 여기서 onTap으로 직접 되살린다.
      excludeSemantics: true,
      onTap: _isEnabled ? onPressed : null,
      child: FocusableActionDetector(
        enabled: _isEnabled,
        mouseCursor: _isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              onPressed?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: _isEnabled ? onPressed : null,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            key: const ValueKey('app_button_surface'),
            duration: const Duration(milliseconds: 120),
            height: style.height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: style.background,
              borderRadius: BorderRadius.circular(radius),
            ),
            child: isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(style.foreground),
                    ),
                  )
                : Text(
                    label,
                    style: style.textStyle.copyWith(color: style.foreground),
                  ),
          ),
        ),
      ),
    );
  }
}

/// variant/size를 스타일로 해석한다. exhaustive switch라 새 variant를 추가하면
/// 컴파일 타임에 누락을 알려준다 — 위젯 본문에는 색 분기를 두지 않는다.
AppButtonStyle resolveButtonStyle(
  BuildContext context,
  ButtonVariant variant,
  ButtonSize size, {
  required bool enabled,
}) {
  final colors = Theme.of(context).extension<AppColors>()!;
  final typography = Theme.of(context).extension<AppTypography>()!;

  final ({Color background, Color foreground}) palette = switch (variant) {
    ButtonVariant.primary => (background: colors.main, foreground: colors.white),
    ButtonVariant.destructive => (background: colors.red, foreground: colors.white),
    ButtonVariant.ghost => (background: Colors.transparent, foreground: colors.gray3),
  };

  final ({double height, TextStyle textStyle}) metrics = switch (size) {
    ButtonSize.md => (height: 44.0, textStyle: typography.title7),
    ButtonSize.lg => (height: 56.0, textStyle: typography.title6),
  };

  return AppButtonStyle(
    background: enabled ? palette.background : colors.gray4,
    foreground: enabled ? palette.foreground : colors.gray2,
    height: metrics.height,
    textStyle: metrics.textStyle,
  );
}
