import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../components/ui/button.dart';
import '../../../components/ui/input.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../beacon/data/beacon_config_dto.dart';

/// RSSI 임계값 슬라이더의 범위.
///
/// 서버는 `rssiThreshold < 0`만 요구한다([BeaconConfig.fromJson]). 실제
/// RSSI는 항상 음수이고, -100dBm보다 약하면 사실상 잡히지 않으며 -40dBm은
/// 비콘에 손이 닿는 거리다. 슬라이더로는 그 계약을 **절대 깰 수 없게** 둔다 —
/// 숫자를 직접 타이핑하게 두면 0이나 양수가 저장되고, 그러면 다음 조회에서
/// `FormatException`이 나 비콘 설정 화면이 통째로 죽는다.
const int minRssiThreshold = -100;
const int maxRssiThreshold = -40;

/// 관리자 설정.
///
/// **웹 디자인(`356:2127`)을 모바일로 옮긴 것이다.** 웹은 카드 셋에 우상단
/// "저장하기" 버튼 **하나**인데, 그 셋은 서로 다른 엔드포인트다.
///
/// | 웹 카드 | 엔드포인트 |
/// |---|---|
/// | 동아리 정보 | `PATCH /clubs/{id}` |
/// | 코드 생성 | 저장 개념이 없다 — 버튼이 곧 동작 |
/// | 비콘 설정 | `PUT /clubs/{id}/beacon` |
///
/// 버튼 하나가 두 요청을 순차로 보내면 **부분 실패**가 생긴다(동아리는
/// 저장됐는데 비콘은 실패). 무엇이 저장됐는지 화면이 말해 줄 수 없으므로
/// 섹션마다 자기 저장 버튼을 둔다.
///
/// 웹에 없는 PSK 항목이 하나 더 있다. API에 PSK의 출처가 없어 이 기기에만
/// 저장하는 값이라(#15) 웹 디자인에 자리가 없다 — 세션 시작 때 묻는 흐름은
/// 그대로 두고, 여기서 **다시 바꿀 수 있는 길**만 연다.
class ClubSettingsSheetContent extends StatelessWidget {
  const ClubSettingsSheetContent({
    super.key,
    required this.clubName,
    required this.clubDescription,
    required this.inviteCode,
    required this.beacon,
    required this.hasPsk,
    required this.onSaveClub,
    required this.onIssueInviteCode,
    required this.onRevokeInviteCode,
    required this.onSaveBeacon,
    required this.onEditPsk,
    this.isLoading = false,
    this.loadFailed = false,
    this.savingClub = false,
    this.savingBeacon = false,
    this.workingInviteCode = false,
  });

  final TextEditingController clubName;
  final TextEditingController clubDescription;

  /// 현재 유효한 초대코드. 아직 발급하지 않았으면 null.
  final String? inviteCode;

  /// 비콘 설정. 아직 못 읽었으면 null.
  final BeaconConfig? beacon;

  /// 이 기기에 PSK가 저장돼 있는지. **값 자체는 화면에 절대 내보내지
  /// 않는다** — 아는 사람은 누구나 그 동아리 비콘에 명령할 수 있다.
  final bool hasPsk;

  final VoidCallback onSaveClub;
  final VoidCallback onIssueInviteCode;
  final VoidCallback onRevokeInviteCode;
  final ValueChanged<BeaconConfig> onSaveBeacon;
  final VoidCallback onEditPsk;

  final bool isLoading;
  final bool loadFailed;
  final bool savingClub;
  final bool savingBeacon;
  final bool workingInviteCode;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (loadFailed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Text(
            '설정을 불러오지 못했습니다',
            style: typography.body2.copyWith(color: colors.gray2),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('설정', style: typography.title4.copyWith(color: colors.gray3)),
        const SizedBox(height: 16),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Section(
                  title: '동아리 정보',
                  children: [
                    AppInput(controller: clubName, label: '동아리명', hint: '동아리명을 입력해주세요'),
                    const SizedBox(height: 12),
                    AppInput(
                      controller: clubDescription,
                      label: '설명',
                      hint: '동아리에 대한 설명을 입력해주세요',
                    ),
                    const SizedBox(height: 16),
                    AppButton(
                      label: '동아리 정보 저장',
                      size: ButtonSize.md,
                      isLoading: savingClub,
                      onPressed: onSaveClub,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _InviteCodeSection(
                  code: inviteCode,
                  working: workingInviteCode,
                  onIssue: onIssueInviteCode,
                  onRevoke: onRevokeInviteCode,
                ),
                const SizedBox(height: 24),
                _BeaconSection(
                  // 저장 뒤 서버가 다듬은 값을 받으면 **새 인스턴스**가
                  // 들어온다. `late final` 컨트롤러는 첫 빌드 값에 묶여
                  // 있으므로, 키를 갈아 상태를 새로 만들어야 그 값이 칸에
                  // 보인다. 안 그러면 화면은 내가 친 값을 계속 보여 준다.
                  key: ObjectKey(beacon),
                  config: beacon,
                  saving: savingBeacon,
                  onSave: onSaveBeacon,
                ),
                const SizedBox(height: 24),
                _Section(
                  title: '비콘 PSK',
                  children: [
                    Text(
                      hasPsk
                          ? '이 기기에 저장돼 있습니다.'
                          : '아직 저장돼 있지 않습니다. 세션을 시작하려면 필요합니다.',
                      style: typography.body3.copyWith(color: colors.gray2),
                    ),
                    const SizedBox(height: 12),
                    AppButton.ghost(
                      label: hasPsk ? 'PSK 다시 입력' : 'PSK 입력',
                      size: ButtonSize.md,
                      onPressed: onEditPsk,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: typography.body1.copyWith(color: colors.gray3)),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}

class _InviteCodeSection extends StatelessWidget {
  const _InviteCodeSection({
    required this.code,
    required this.working,
    required this.onIssue,
    required this.onRevoke,
  });

  final String? code;
  final bool working;
  final VoidCallback onIssue;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;
    final current = code;

    return _Section(
      title: '초대코드',
      children: [
        if (current == null)
          Text(
            '아직 발급된 코드가 없습니다.',
            style: typography.body3.copyWith(color: colors.gray2),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              current,
              style: typography.title4.copyWith(color: colors.gray3),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (current != null) ...[
              Expanded(
                child: AppButton.ghost(
                  label: '복사하기',
                  size: ButtonSize.md,
                  onPressed: working
                      ? null
                      : () async {
                          await Clipboard.setData(ClipboardData(text: current));
                        },
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: AppButton(
                // 서버가 기존 코드를 자동으로 무효화하고 새 코드를 준다 —
                // "생성"이 아니라 "재발급"이므로 문구도 그렇게 쓴다.
                label: current == null ? '코드 발급' : '다시 만들기',
                size: ButtonSize.md,
                isLoading: working,
                onPressed: onIssue,
              ),
            ),
          ],
        ),
        if (current != null) ...[
          const SizedBox(height: 8),
          AppButton.destructive(
            label: '코드 무효화',
            size: ButtonSize.md,
            onPressed: working ? null : onRevoke,
          ),
        ],
      ],
    );
  }
}

class _BeaconSection extends StatefulWidget {
  const _BeaconSection({
    super.key,
    required this.config,
    required this.saving,
    required this.onSave,
  });

  final BeaconConfig? config;
  final bool saving;
  final ValueChanged<BeaconConfig> onSave;

  @override
  State<_BeaconSection> createState() => _BeaconSectionState();
}

class _BeaconSectionState extends State<_BeaconSection> {
  late final TextEditingController _uuid = TextEditingController(
    text: widget.config?.uuid ?? '',
  );
  late final TextEditingController _late = TextEditingController(
    text: widget.config?.lateThresholdMinutes.toString() ?? '',
  );
  late final TextEditingController _stabilization = TextEditingController(
    text: widget.config?.rssiStabilizationSeconds.toString() ?? '',
  );
  late int _rssi = widget.config?.rssiThreshold ?? -70;

  String? _error;

  @override
  void dispose() {
    _uuid.dispose();
    _late.dispose();
    _stabilization.dispose();
    super.dispose();
  }

  /// 서버로 보내기 **전에** 막는다.
  ///
  /// [BeaconConfig.fromJson]이 던지는 것과 같은 규칙이다. 여기서 안 막으면
  /// 서버가 그 값을 받아 저장하고, 다음 조회에서 `FormatException`이 나
  /// 비콘 설정을 읽는 모든 화면(부원 홈 포함)이 통째로 죽는다.
  void _submit() {
    final base = widget.config;
    if (base == null) return;

    final uuid = _uuid.text.trim();
    if (uuid.isEmpty) {
      setState(() => _error = 'UUID를 입력해주세요.');
      return;
    }
    final late = int.tryParse(_late.text.trim());
    if (late == null || late < 0) {
      setState(() => _error = '지각 시간 기준은 0 이상의 숫자여야 합니다.');
      return;
    }
    final stabilization = int.tryParse(_stabilization.text.trim());
    if (stabilization == null || stabilization <= 0) {
      setState(() => _error = 'RSSI 안정화 시간은 1초 이상이어야 합니다.');
      return;
    }

    setState(() => _error = null);
    widget.onSave(
      base.copyWith(
        uuid: uuid,
        lateThresholdMinutes: late,
        rssiStabilizationSeconds: stabilization,
        rssiThreshold: _rssi,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    if (widget.config == null) {
      return _Section(
        title: '비콘 설정',
        children: [
          Text(
            '비콘 설정을 불러오지 못했습니다.',
            style: typography.body3.copyWith(color: colors.gray2),
          ),
        ],
      );
    }

    return _Section(
      title: '비콘 설정',
      children: [
        AppInput(
          controller: _uuid,
          label: 'UUID',
          hint: 'e.g. FDA50693-A4E2-4FB1-AFCF-C6EB07647825',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: AppInput(
                controller: _late,
                label: '지각 시간 기준',
                hint: '분',
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AppInput(
                controller: _stabilization,
                label: 'RSSI 안정화 시간',
                hint: '초',
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('RSSI', style: typography.body3.copyWith(color: colors.gray2)),
        Text(
          '${_rssi}dBm',
          style: typography.title4.copyWith(color: colors.main),
        ),
        Slider(
          value: _rssi.toDouble(),
          min: minRssiThreshold.toDouble(),
          max: maxRssiThreshold.toDouble(),
          divisions: maxRssiThreshold - minRssiThreshold,
          onChanged: widget.saving ? null : (v) => setState(() => _rssi = v.round()),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('(먼)', style: typography.body4.copyWith(color: colors.gray2)),
            Text('(가까운)', style: typography.body4.copyWith(color: colors.gray2)),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: typography.body3.copyWith(color: colors.red)),
        ],
        const SizedBox(height: 16),
        AppButton(
          label: '비콘 설정 저장',
          size: ButtonSize.md,
          isLoading: widget.saving,
          onPressed: _submit,
        ),
      ],
    );
  }
}
