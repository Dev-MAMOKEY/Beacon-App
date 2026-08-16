import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// [cancel]은 Figma 버튼 컴포넌트(`353:1903` "버튼 모음")의 `취소버튼`
/// variant(`353:1901`)다 — 배경 `gray1`, 글자 `white`. 팝업의 취소/변경
/// 2단 버튼(`353:1907`·`353:1685`)이 쓴다. [ghost](투명 배경 + `gray3`
/// 글자)와는 다른 것이라 재사용할 수 없다.
enum ButtonVariant { primary, destructive, ghost, cancel }

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
    this.trailing,
  });

  const AppButton.destructive({
    super.key,
    required this.label,
    this.onPressed,
    this.size = ButtonSize.lg,
    this.isLoading = false,
    this.trailing,
  }) : variant = ButtonVariant.destructive;

  const AppButton.ghost({
    super.key,
    required this.label,
    this.onPressed,
    this.size = ButtonSize.lg,
    this.isLoading = false,
    this.trailing,
  }) : variant = ButtonVariant.ghost;

  const AppButton.cancel({
    super.key,
    required this.label,
    this.onPressed,
    this.size = ButtonSize.lg,
    this.isLoading = false,
    this.trailing,
  }) : variant = ButtonVariant.cancel;

  static const double radius = 12;

  final String label;
  final VoidCallback? onPressed;
  final ButtonVariant variant;
  final ButtonSize size;
  final bool isLoading;

  /// 라벨 오른쪽에 6 간격으로 붙는 장식. Figma 버튼 컴포넌트 `317:1419`
  /// ("속성 1=버튼")는 라벨 뒤에 셰브론을 달고 있다 — 마이페이지의 로그아웃
  /// 버튼(`353:1730`)이 그 variant다. 장식일 뿐이라 [Semantics]에서는
  /// 제외된다(버튼의 접근성 라벨은 [label] 하나다).
  final Widget? trailing;

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
                : _buildLabel(style),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(AppButtonStyle style) {
    final text = Text(label, style: style.textStyle.copyWith(color: style.foreground));
    final trailing = this.trailing;
    if (trailing == null) return text;
    // Figma `317:1419` 실측 — 라벨과 셰브론 사이 6.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [text, const SizedBox(width: 6), trailing],
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
    ButtonVariant.cancel => (background: colors.gray1, foreground: colors.white),
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
