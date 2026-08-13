import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// 부모가 입력을 초기화하거나 오답 흔들림을 트리거하기 위한 핸들.
class AppOtpController extends ChangeNotifier {
  int _resetTick = 0;
  int _shakeTick = 0;

  int get resetTick => _resetTick;
  int get shakeTick => _shakeTick;

  void reset() {
    _resetTick++;
    notifyListeners();
  }

  /// 오답일 때 입력을 비우고 흔든다.
  void shake() {
    _shakeTick++;
    _resetTick++;
    notifyListeners();
  }
}

class AppOtpInput extends StatefulWidget {
  const AppOtpInput({
    super.key,
    required this.length,
    required this.onCompleted,
    this.controller,
    this.enabled = true,
  });

  final int length;
  final ValueChanged<String> onCompleted;
  final AppOtpController? controller;
  final bool enabled;

  @override
  State<AppOtpInput> createState() => _AppOtpInputState();
}

class _AppOtpInputState extends State<AppOtpInput>
    with SingleTickerProviderStateMixin {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  late final AnimationController _shakeAnimation;
  int _lastShakeTick = 0;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.length, (_) => TextEditingController());
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
    _shakeAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    widget.controller?.addListener(_onControllerSignal);
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerSignal);
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    _shakeAnimation.dispose();
    super.dispose();
  }

  void _onControllerSignal() {
    final controller = widget.controller!;
    for (final field in _controllers) {
      field.clear();
    }
    if (controller.shakeTick != _lastShakeTick) {
      _lastShakeTick = controller.shakeTick;
      _shakeAnimation.forward(from: 0);
    }
    if (mounted) {
      setState(() {});
      _focusNodes.first.requestFocus();
    }
  }

  String get _value => _controllers.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    if (value.isNotEmpty && index < widget.length - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    setState(() {});
    if (_value.length == widget.length) {
      widget.onCompleted(_value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        // 0 → 1 구간에서 좌우로 3회 흔든다.
        final offset = _shakeAnimation.isAnimating
            ? 8 * (1 - _shakeAnimation.value) *
                  ((_shakeAnimation.value * 6).floor().isEven ? 1 : -1)
            : 0.0;
        return Transform.translate(offset: Offset(offset, 0), child: child);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(widget.length, (index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: SizedBox(
              width: 56,
              height: 64,
              child: TextField(
                controller: _controllers[index],
                focusNode: _focusNodes[index],
                enabled: widget.enabled,
                autofocus: index == 0,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 1,
                style: typography.title3.copyWith(color: colors.gray3),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: colors.white,
                  contentPadding: EdgeInsets.zero,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colors.gray4),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colors.main, width: 2),
                  ),
                ),
                onChanged: (value) => _onDigitChanged(index, value),
              ),
            ),
          );
        }),
      ),
    );
  }
}
