import 'package:flutter/material.dart';

import '../../../components/ui/button.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../attendance/data/attendance_dto.dart';
import '../../records/presentation/session_detail_sheet.dart' show attendanceStatusLabel;
import '../data/club_member_repository.dart';

/// 체크인하지 않은 부원을 관리자가 손으로 출석 처리한다.
///
/// 웹(`356:1800`)에는 이 진입점이 표 안의 "상태 변경" 열로 녹아 있지만,
/// 그 표에는 **이미 기록이 있는 부원만** 나온다. 비콘을 아예 못 잡은 부원은
/// 목록에 없어서 웹에서도 별도 경로가 필요하다 — 모바일에서는 출석 현황
/// 시트의 버튼으로 뺐다.
class ManualAttendancePopupContent extends StatefulWidget {
  const ManualAttendancePopupContent({
    super.key,
    required this.candidates,
    required this.onSubmit,
    required this.onCancel,
  });

  /// 아직 기록이 없는 부원만. 이미 기록이 있는 사람을 여기서 또 넣으면
  /// 서버가 중복으로 거절하거나 기존 기록을 덮어쓴다 — 그건 상태 변경으로
  /// 해야 할 일이다.
  final List<ClubMember> candidates;

  final Future<void> Function(int memberId, AttendanceStatus status) onSubmit;
  final VoidCallback onCancel;

  @override
  State<ManualAttendancePopupContent> createState() => _ManualAttendancePopupContentState();
}

class _ManualAttendancePopupContentState extends State<ManualAttendancePopupContent> {
  int? _memberId;
  AttendanceStatus _status = AttendanceStatus.present;
  String? _error;
  bool _submitting = false;

  Future<void> _submit() async {
    final memberId = _memberId;
    if (memberId == null) {
      setState(() => _error = '부원을 선택해주세요');
      return;
    }
    if (_submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(memberId, _status);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '출석을 등록하지 못했습니다. 다시 시도해주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return PopScope(
      canPop: !_submitting,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '수동 출석',
            textAlign: TextAlign.center,
            style: typography.title4.copyWith(color: colors.gray3),
          ),
          const SizedBox(height: 16),
          if (widget.candidates.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                '모든 부원의 기록이 이미 있습니다.\n상태를 바꾸려면 목록에서 이름을 눌러주세요.',
                textAlign: TextAlign.center,
                style: typography.body3.copyWith(color: colors.gray2),
              ),
            )
          else ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.candidates.length,
                itemBuilder: (context, index) {
                  final member = widget.candidates[index];
                  final selected = member.memberId == _memberId;
                  return InkWell(
                    onTap: _submitting
                        ? null
                        : () => setState(() {
                            _memberId = member.memberId;
                            _error = null;
                          }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      decoration: BoxDecoration(
                        color: selected ? colors.bg : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              member.name,
                              style: typography.body2.copyWith(color: colors.gray3),
                            ),
                          ),
                          Text(
                            member.stdId,
                            style: typography.body4.copyWith(color: colors.gray2),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final status in AttendanceStatus.values) ...[
                  if (status != AttendanceStatus.present) const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: _submitting ? null : () => setState(() => _status = status),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: status == _status ? colors.bg : colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: status == _status ? colors.main : colors.gray4,
                            width: status == _status ? 2 : 1,
                          ),
                        ),
                        child: Text(
                          attendanceStatusLabel(status),
                          style: typography.body3.copyWith(color: colors.gray3),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
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
              if (widget.candidates.isNotEmpty) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    label: '등록하기',
                    size: ButtonSize.md,
                    isLoading: _submitting,
                    onPressed: _submit,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
