import 'package:flutter/material.dart';

import '../../../components/ui/button.dart';
import '../../../components/ui/input.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../attendance/data/attendance_dto.dart';
import '../../records/presentation/records_calendar.dart' show attendanceBadgeColor;
import '../../records/presentation/session_detail_sheet.dart' show attendanceStatusLabel;
import '../data/attendance_admin_dto.dart';

/// 한 부원의 출석 상태를 손으로 바꾼다.
///
/// 웹 표(`356:1800`)의 "상태 변경"(O/X) 열과 "사유" 열이 여기로 합쳐졌다 —
/// 모바일에서는 행을 탭하면 이 팝업이 뜨고, 상태와 사유를 함께 정한다.
class AttendanceStatusPopupContent extends StatefulWidget {
  const AttendanceStatusPopupContent({
    super.key,
    required this.record,
    required this.onSubmit,
    required this.onCancel,
  });

  final AdminAttendanceRecord record;

  /// 실패 메시지는 이 팝업 **안**에 남아야 한다 — 토스트는 팝업 스크림
  /// 아래로 가려진다(#42).
  final Future<void> Function(AttendanceStatus status, String? adminNote) onSubmit;

  final VoidCallback onCancel;

  @override
  State<AttendanceStatusPopupContent> createState() => _AttendanceStatusPopupContentState();
}

class _AttendanceStatusPopupContentState extends State<AttendanceStatusPopupContent> {
  late AttendanceStatus _status = widget.record.attendanceStatus;
  late final TextEditingController _note = TextEditingController(
    text: widget.record.adminNote ?? '',
  );

  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_status, _note.text.trim());
    } catch (_) {
      // `ApiException`만 잡으면 그 밖의 예외가 새어 `_submitting`이 참으로
      // 굳는다 — `barrierDismissible: false`라 닫을 수 없는 팝업이 된다(#46).
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '상태를 바꾸지 못했습니다. 다시 시도해주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    // 제출 중에는 시스템 뒤로가기로도 닫히지 않아야 한다 — 빠져나가면
    // 팝업이 dispose돼 결과가 반영되지 않는다(#46).
    return PopScope(
      canPop: !_submitting,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.record.memberName,
            textAlign: TextAlign.center,
            style: typography.title4.copyWith(color: colors.gray3),
          ),
          const SizedBox(height: 4),
          Text(
            widget.record.stdId,
            textAlign: TextAlign.center,
            style: typography.body3.copyWith(color: colors.gray2),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              for (final status in AttendanceStatus.values) ...[
                if (status != AttendanceStatus.present) const SizedBox(width: 8),
                Expanded(
                  child: _StatusChoice(
                    status: status,
                    selected: status == _status,
                    onTap: _submitting ? null : () => setState(() => _status = status),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          AppInput(controller: _note, label: '사유', hint: '필요하면 남겨주세요'),
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
                  label: '변경하기',
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

class _StatusChoice extends StatelessWidget {
  const _StatusChoice({required this.status, required this.selected, required this.onTap});

  final AttendanceStatus status;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? attendanceBadgeColor(colors, status) : colors.white,
          borderRadius: BorderRadius.circular(14),
          // 선택 여부를 색만으로 구분하면 상태 색이 옅은 "기타"에서 구별이
          // 어렵다 — 테두리를 함께 준다.
          border: Border.all(
            color: selected ? colors.gray3 : colors.gray4,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          attendanceStatusLabel(status),
          style: typography.body3.copyWith(color: colors.gray3),
        ),
      ),
    );
  }
}
