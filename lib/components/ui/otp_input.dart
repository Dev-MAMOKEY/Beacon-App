import 'dart:math' as math;

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
  }) : assert(length > 0, 'length는 1 이상이어야 한다');

  final int length;
  final ValueChanged<String> onCompleted;
  final AppOtpController? controller;
  final bool enabled;

  @override
  State<AppOtpInput> createState() => _AppOtpInputState();
}

class _AppOtpInputState extends State<AppOtpInput>
    with SingleTickerProviderStateMixin {
  late List<TextEditingController> _controllers;
  late List<FocusNode> _focusNodes;
  late final AnimationController _shakeAnimation;
  int _lastShakeTick = 0;

  @override
  void initState() {
    super.initState();
    _controllers = _createControllers(widget.length);
    _focusNodes = _createFocusNodes(widget.length);
    _shakeAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    widget.controller?.addListener(_onControllerSignal);
  }

  static List<TextEditingController> _createControllers(int length) =>
      List.generate(length, (_) => TextEditingController());

  // TextField/EditableText가 이 FocusNode로 자신의 Focus를 붙이면서
  // onKeyEvent: null로 attach하기 때문에, 여기서 직접 넣어둔 콜백은
  // 덮어써지지 않고 그대로 남는다(FocusNode.attach는 onKeyEvent가 null이면
  // 기존 값을 유지한다). 그래서 KeyboardListener 같은 별도 상위 Focus
  // 위젯 없이도 물리 backspace 키를 감지할 수 있다 — 같은 FocusNode를
  // 상위 Focus 위젯과 TextField에 동시에 붙이면 "child of itself"
  // 어서션이 난다.
  List<FocusNode> _createFocusNodes(int length) {
    return List.generate(length, (index) {
      return FocusNode(
        onKeyEvent: (node, event) {
          _handleBackspace(index, event);
          return KeyEventResult.ignored;
        },
      );
    });
  }

  @override
  void didUpdateWidget(covariant AppOtpInput oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 컨트롤러 인스턴스가 바뀌면 이전 것에서는 떼고 새 것에 붙인다.
    // null ↔ non-null 전환도 이 비교 하나로 함께 처리된다.
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerSignal);
      widget.controller?.addListener(_onControllerSignal);
    }

    // length가 바뀌면 칸 수에 맞춰 컨트롤러/포커스 노드를 다시 만든다.
    // 오늘 이 앱에서 length를 바꾸는 화면은 없지만, 지키지 않으면
    // 늘어날 때 RangeError, 줄어들 때 숨은 칸의 값이 완료 판정에 섞인다.
    if (oldWidget.length != widget.length) {
      for (final controller in _controllers) {
        controller.dispose();
      }
      for (final node in _focusNodes) {
        node.dispose();
      }
      _controllers = _createControllers(widget.length);
      _focusNodes = _createFocusNodes(widget.length);
    }
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
    // 각 TextField는 자신의 컨트롤러를 직접 듣고 있어 clear()만으로 화면이
    // 갱신된다 — 이 State를 다시 그릴 이유가 없어 setState는 두지 않는다.
    if (mounted) {
      _focusNodes.first.requestFocus();
    }
  }

  String get _value => _controllers.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    if (value.isNotEmpty && index < widget.length - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    if (_value.length == widget.length) {
      widget.onCompleted(_value);
    }
  }

  /// 빈 칸에서 backspace를 누르면 이전 칸으로 이동해 그 칸을 지운다.
  /// 터치 사용자는 이전 칸을 직접 탭할 수 있지만, 키보드·스위치 사용자는
  /// 이 처리가 없으면 값이 없는 칸에서 완전히 멈춘다.
  void _handleBackspace(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey != LogicalKeyboardKey.backspace) return;
    if (_controllers[index].text.isNotEmpty) return;
    if (index == 0) return;

    _focusNodes[index - 1].requestFocus();
    _controllers[index - 1].clear();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        // 감쇠하는 사인파로 부드럽게 3회 왕복한다. t=0과 t=1(정지 상태)에서
        // 진폭이 정확히 0이라 항상 원점에 정착한다.
        final t = _shakeAnimation.value;
        final offset = 8 * (1 - t) * math.sin(t * 3 * 2 * math.pi);
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
              child: Semantics(
                label: '인증번호 ${index + 1} / ${widget.length}',
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
            ),
          );
        }),
      ),
    );
  }
}
