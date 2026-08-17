import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../components/ui/button.dart';
import '../../../components/ui/input.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../data/beacon_psk_store.dart';

/// 비콘 PSK 입력 팝업.
///
/// **왜 세션 시작 시점에 묻는가.** 이슈 #15는 PSK를 관리자 설정 화면(#18)에서
/// 받는다고 했지만 **#18은 Figma에 모바일 화면이 없다**(웹 1440px 전용).
/// 없는 화면에 넣을 수 없고, 설정 화면을 새로 지어내면 디자인 없이 만드는
/// 실패를 반복한다.
///
/// PSK가 실제로 쓰이는 유일한 순간이 "출석 시작하기"다. 그때 묻는 쪽이
/// - 발견 가능성이 높고(설정에 묻어 두면 있는 줄도 모른다),
/// - 한 번 저장하면 다시 묻지 않으며,
/// - 잘못 넣었을 때 **바로 그 화면에서** 고칠 수 있다.
///
/// 약점 하나를 인정한다: 이 방식만으로는 저장된 PSK를 나중에 바꿀 경로가
/// 없다. 비콘 기기를 교체하면 저장값이 틀리게 되므로, 시작이 실패했을 때
/// 다시 물을 수 있도록 [initial]을 받는다.
class BeaconPskPopupContent extends StatefulWidget {
  const BeaconPskPopupContent({
    super.key,
    required this.onSubmit,
    required this.onCancel,
    this.initial,
  });

  /// 저장된 값이 있으면 채워 둔다 — 한 글자만 틀렸을 때 전부 다시 치게
  /// 하지 않는다.
  final String? initial;

  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  @override
  State<BeaconPskPopupContent> createState() => _BeaconPskPopupContentState();
}

class _BeaconPskPopupContentState extends State<BeaconPskPopupContent> {
  late final TextEditingController _psk = TextEditingController(text: widget.initial ?? '');

  String? _error;

  @override
  void dispose() {
    _psk.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _psk.text.trim();
    if (!isValidBeaconPsk(value)) {
      // 형식이 틀린 PSK는 **증상이 늦게 나타난다** — 저장되고, 세션도
      // 시작되고, 비콘만 광고를 시작하지 않는다. 여기서 막는다.
      setState(() => _error = '32자 16진수를 입력해주세요 (0-9, a-f)');
      return;
    }
    widget.onSubmit(value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '비콘 키 입력',
          textAlign: TextAlign.center,
          style: typography.title4.copyWith(color: colors.gray3),
        ),
        const SizedBox(height: 12),
        Text(
          '비콘 기기에 설정된 32자리 키를 입력하세요.\n이 기기에만 저장되고 서버로 보내지 않습니다.',
          textAlign: TextAlign.center,
          style: typography.body3.copyWith(color: colors.gray2),
        ),
        const SizedBox(height: 16),
        AppInput(
          controller: _psk,
          hint: '32자 16진수',
          errorText: _error,
          maxLength: 32,
          // 16진수만 받는다 — 붙여넣기로 들어온 하이픈·공백을 애초에 막는다.
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]'))],
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: AppButton.cancel(
                label: '취소',
                size: ButtonSize.md,
                onPressed: widget.onCancel,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppButton(label: '저장하고 시작', size: ButtonSize.md, onPressed: _submit),
            ),
          ],
        ),
      ],
    );
  }
}
