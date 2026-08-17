import 'package:flutter/material.dart';

import '../../../components/ui/button.dart';
import '../../../components/ui/input.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/time/kst.dart';
import '../data/session_dto.dart';

/// 세션 생성·수정 폼.
///
/// **Figma에 이 화면이 없다.** 모바일 관리자 디자인은 세션 목록(`353:2033`)
/// 하나뿐이고, 생성/수정 폼은 웹(`388:1842` "웹 세션관리 페이지")에만 있다.
/// 그래서 이 프로젝트가 이미 쓰는 팝업 프리미티브(`AppPopupCard` + `AppInput`
/// + `AppButton`)로 구성했다 — 새 시각 언어를 지어내지 않는다(#14에 기록).
///
/// 받는 필드가 셋인 이유: 서버 `SessionCreateRequestDto`의 `required`가
/// `sessionName`·`expectStartAt`·**`expectEndAt`** 셋이다. 이슈 #14는
/// "이름, 예정 시간만"이라고 적었지만 종료 예정 시각 없이는 생성 자체가
/// 되지 않는다.
class SessionFormPopupContent extends StatefulWidget {
  const SessionFormPopupContent({
    super.key,
    required this.onSubmit,
    required this.onCancel,
    this.initial,
  });

  /// null이면 생성, 아니면 수정이다.
  final AdminSession? initial;

  /// 성공하면 팝업을 닫는 것은 호출자의 몫이다 — 실패 메시지는 이 팝업
  /// **안에** 남아야 하므로(스크림이 토스트를 덮는다, #42) 여기서 잡는다.
  final Future<void> Function(SessionDraft draft) onSubmit;

  final VoidCallback onCancel;

  @override
  State<SessionFormPopupContent> createState() => _SessionFormPopupContentState();
}

class _SessionFormPopupContentState extends State<SessionFormPopupContent> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial?.sessionName ?? '',
  );

  late DateTime _start = widget.initial?.expectStartAt ?? _defaultStart();
  late DateTime _end = widget.initial?.expectEndAt ?? _defaultStart().add(const Duration(hours: 2));

  String? _error;
  bool _submitting = false;

  static DateTime _defaultStart() {
    // 지금으로부터 다음 정시. 과거 시각이 기본값으로 들어가면 관리자가
    // 매번 고쳐야 한다.
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, now.hour + 1);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool isStart}) async {
    final current = isStart ? _start : _end;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 1),
      lastDate: DateTime(current.year + 2),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;

    setState(() {
      final picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      if (isStart) {
        _start = picked;
        // 시작이 종료를 넘어서면 종료를 함께 민다 — 사용자가 두 번 고치게
        // 하는 대신 관계를 유지한다.
        if (!_end.isAfter(picked)) _end = picked.add(const Duration(hours: 2));
      } else {
        _end = picked;
      }
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '세션 이름을 입력해주세요');
      return;
    }
    if (!_end.isAfter(_start)) {
      setState(() => _error = '종료 시각은 시작 시각보다 뒤여야 합니다');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        SessionDraft(sessionName: name, expectStartAt: _start, expectEndAt: _end),
      );
    } catch (_) {
      // `ApiException`만 잡으면 그 밖의 예외가 새어 `_submitting`이 참으로
      // 굳는다 — `barrierDismissible: false`라 닫을 수 없는 팝업이 된다
      // (#46에서 프로필 팝업 둘이 같은 지적을 받았다).
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '저장하지 못했습니다. 다시 시도해주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;
    final isEdit = widget.initial != null;

    // 제출 중에는 시스템 뒤로가기로도 닫히지 않아야 한다 — 빠져나가면
    // 팝업이 dispose돼 `mounted` 가드에 막혀 결과가 반영되지 않는다(#46).
    return PopScope(
      canPop: !_submitting,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isEdit ? '세션 수정' : '세션 만들기',
            textAlign: TextAlign.center,
            style: typography.title4.copyWith(color: colors.gray3),
          ),
          const SizedBox(height: 16),
          AppInput(controller: _name, label: '이름', hint: '세션 이름을 입력하세요'),
          const SizedBox(height: 16),
          _MomentField(label: '시작 예정', value: _start, onTap: () => _pick(isStart: true)),
          const SizedBox(height: 12),
          _MomentField(label: '종료 예정', value: _end, onTap: () => _pick(isStart: false)),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: typography.body3.copyWith(color: colors.red),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: AppButton.cancel(
                  label: '취소',
                  size: ButtonSize.md,
                  onPressed: _submitting ? null : widget.onCancel,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppButton(
                  label: isEdit ? '수정하기' : '만들기',
                  size: ButtonSize.md,
                  isLoading: _submitting,
                  onPressed: _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 탭하면 날짜·시각 선택기를 여는 읽기 전용 칸.
class _MomentField extends StatelessWidget {
  const _MomentField({required this.label, required this.value, required this.onTap});

  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(label, style: typography.title7.copyWith(color: colors.gray3)),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              // 목록 카드와 같은 형식으로 읽는다 — 같은 값을 두 곳에서 다른
              // 모양으로 보여주면 관리자가 서로 다른 시각으로 읽는다.
              _format(value),
              style: typography.body3.copyWith(color: colors.gray3),
            ),
          ),
        ],
      ),
    );
  }

  String _format(DateTime value) {
    final kst = toKst(value);
    final month = kst.month.toString().padLeft(2, '0');
    final day = kst.day.toString().padLeft(2, '0');
    final hour = kst.hour.toString().padLeft(2, '0');
    final minute = kst.minute.toString().padLeft(2, '0');
    return '${kst.year}. $month. $day. $hour:$minute';
  }
}
