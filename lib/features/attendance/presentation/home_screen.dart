import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../components/beacon/beacon_pulse.dart';
import '../../../components/ui/app_progress_bar.dart';
import '../../../components/ui/button.dart';
import '../../../components/ui/card.dart';
import '../../../components/ui/otp_input.dart';
import '../../../components/ui/toast.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/presentation/session_controller.dart';
import '../../beacon/data/beacon_config_dto.dart';
import '../../beacon/data/beacon_config_repository.dart';
import '../../beacon/data/beacon_settings.dart';
import '../../beacon/data/flutter_beacon_scanner.dart' show beaconScannerProvider;
import '../../beacon/domain/beacon_scanner.dart';
import '../../records/data/records_dto.dart';
import '../../records/data/records_repository.dart';
import '../data/attendance_dto.dart';
import '../data/attendance_repository.dart';
import 'attendance_controller.dart';
import 'attendance_success_sheet.dart';

const List<String> _weekdayNames = ['월', '화', '수', '목', '금', '토', '일'];

String _formatTodayLabel(DateTime date) {
  final weekday = _weekdayNames[date.weekday - 1];
  return '${date.month}월 ${date.day}일 ($weekday)';
}

/// 홈 화면(이슈 #11) — 비콘 감지와 활성 세션의 AND 조건에서만 4자리 출석
/// 코드 입력란을 연다. `lib/core/router/app_router.dart`의 `/home` 자리
/// 표시자를 이 화면으로 교체한다.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  StreamSubscription<BeaconScanState>? _beaconSub;
  BeaconScanState _beaconState = const BeaconIdle();

  int? _bootstrappedClubId;

  ActiveSession? _activeSession;
  MonthlyRecords? _records;

  final AppOtpController _otpController = AppOtpController();
  bool _submitting = false;
  String? _invalidCodeMessage;
  bool _needsManualRetry = false;
  String? _lastOtpCode;

  /// 성공 또는 ALREADY_CHECKED_IN 이후 true로 고정된다 — 그 뒤로는 비콘이
  /// 감지되고 활성 세션이 있어도 입력란을 다시 열지 않는다(브리핑 5-1).
  bool _attendanceDone = false;

  /// `initState`에서 한 번 읽어 저장해 둔다 — Riverpod의
  /// `ConsumerStatefulElement`는 `dispose()` 시점에 `ref`가 이미
  /// 사용 불가 상태라 `ref.read`를 부르면 `StateError`가 난다
  /// (`context.mounted`가 `dispose()` 진입 전에 이미 false로 바뀐다).
  late final BeaconScanner _scanner;

  @override
  void initState() {
    super.initState();
    _scanner = ref.read(beaconScannerProvider);
  }

  @override
  void dispose() {
    _beaconSub?.cancel();
    // 화면을 벗어나면 스캔을 멈춘다 — watch()를 한 번도 부르지 못한
    // 채(예: 클럽 설정 조회 실패) 이 화면이 dispose돼도 안전하게 no-op이다.
    unawaited(_scanner.stop());
    _otpController.dispose();
    super.dispose();
  }

  void _bootstrap(int clubId) {
    unawaited(_startBeaconScan(clubId));
    unawaited(_loadActiveSession(clubId));
    unawaited(_loadRecords(clubId));
  }

  Future<void> _startBeaconScan(int clubId) async {
    late final BeaconConfig beaconConfig;
    try {
      beaconConfig = await ref.read(beaconConfigRepositoryProvider).fetch(clubId);
    } catch (_) {
      return;
    }
    if (!mounted) return;

    await _beaconSub?.cancel();
    _beaconSub = _scanner.watch(beaconConfig.toScanConfig()).listen((state) {
      if (!mounted) return;
      setState(() => _beaconState = state);
    });
  }

  Future<void> _restartScan() async {
    final clubId = _bootstrappedClubId;
    if (clubId == null) return;
    await _scanner.stop();
    if (!mounted) return;
    setState(() => _beaconState = const BeaconIdle());
    await _startBeaconScan(clubId);
  }

  Future<void> _loadActiveSession(int clubId) async {
    try {
      final session = await ref.read(attendanceRepositoryProvider).fetchActiveSession(clubId);
      if (!mounted) return;
      setState(() => _activeSession = session);
    } catch (_) {
      // 활성 세션 조회 실패는 "세션 없음"과 같은 화면(안내 문구)으로
      // 수렴시킨다 — 홈 화면의 핵심 기능은 계속 동작해야 한다.
      if (!mounted) return;
      setState(() => _activeSession = null);
    }
  }

  Future<void> _loadRecords(int clubId) async {
    final now = DateTime.now();
    try {
      final records = await ref
          .read(recordsRepositoryProvider)
          .fetch(clubId: clubId, year: now.year, month: now.month);
      if (!mounted) return;
      setState(() => _records = records);
    } catch (_) {
      // 요약 카드가 없어도 출석 체크 기능 자체에는 영향이 없다 — 조용히
      // 자리표시자(대시)로 남긴다.
    }
  }

  void _onOtpCompleted(String code) {
    unawaited(_submitCode(code));
  }

  Future<void> _retry() async {
    final code = _lastOtpCode;
    if (code == null) return;
    setState(() => _needsManualRetry = false);
    await _submitCode(code);
  }

  Future<void> _submitCode(String code) async {
    final session = _activeSession;
    final clubId = _bootstrappedClubId;
    if (session == null || clubId == null) return;

    _lastOtpCode = code;
    setState(() {
      _submitting = true;
      _invalidCodeMessage = null;
    });

    final result = await ref
        .read(attendanceControllerProvider)
        .submit(clubId: clubId, sessionId: session.sessionId, otpCode: code);

    if (!mounted) return;
    setState(() => _submitting = false);

    switch (result) {
      case CheckInSuccess(:final status, :final checkedAt):
        setState(() {
          _attendanceDone = true;
          _needsManualRetry = false;
        });
        await showAttendanceSuccessSheet(
          context,
          status: status,
          checkedAt: checkedAt,
          sessionName: session.sessionName,
        );
      case CheckInInvalidCode():
        _otpController.shake();
        if (mounted) {
          setState(() => _invalidCodeMessage = '비밀번호가 올바르지 않습니다');
        }
      case CheckInAlreadyDone():
        setState(() {
          _attendanceDone = true;
          _needsManualRetry = false;
        });
        if (mounted) showAppToast(context, '이미 출석 처리되었습니다');
      case CheckInFailed(:final message):
        setState(() => _needsManualRetry = true);
        if (mounted) showAppToast(context, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;
    final session = ref.watch(sessionControllerProvider).value;

    if (session is! SessionReady) {
      return ColoredBox(
        color: colors.bg,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_bootstrappedClubId != session.clubId) {
      _bootstrappedClubId = session.clubId;
      _bootstrap(session.clubId);
    }

    return ColoredBox(
      color: colors.bg,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(name: session.profile.name, colors: colors, typography: typography),
              const SizedBox(height: 32),
              Center(child: _buildBeaconSection(colors, typography)),
              const SizedBox(height: 32),
              _SummaryCards(records: _records),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBeaconSection(AppColors colors, AppTypography typography) {
    return switch (_beaconState) {
      BeaconIdle() || BeaconScanning() => _scanningSection(colors, typography),
      BeaconDetected() => _detectedSection(colors, typography),
      BeaconBluetoothOff() => _bluetoothOffSection(colors, typography),
      BeaconPermissionDenied() => _permissionDeniedSection(colors, typography),
      BeaconOutOfRange() => _outOfRangeSection(colors, typography),
    };
  }

  Widget _scanningSection(AppColors colors, AppTypography typography) {
    return Column(
      children: [
        const BeaconPulse(state: BeaconPulseState.disconnected),
        const SizedBox(height: 16),
        Text('비콘을 찾는 중입니다...', style: typography.body3.copyWith(color: colors.gray2)),
        if (_activeSession == null) ...[
          const SizedBox(height: 8),
          Text(
            '현재 진행 중인 출석 세션이 없습니다',
            textAlign: TextAlign.center,
            style: typography.body3.copyWith(color: colors.gray1),
          ),
        ],
      ],
    );
  }

  Widget _detectedSection(AppColors colors, AppTypography typography) {
    return Column(
      children: [
        const BeaconPulse(state: BeaconPulseState.connected),
        const SizedBox(height: 24),
        if (_activeSession == null)
          Text(
            '현재 진행 중인 출석 세션이 없습니다',
            textAlign: TextAlign.center,
            style: typography.body3.copyWith(color: colors.gray2),
          )
        else if (_attendanceDone)
          Text(
            '오늘 출석이 완료되었습니다',
            style: typography.body3.copyWith(color: colors.gray2),
          )
        else
          _otpArea(colors, typography),
      ],
    );
  }

  Widget _otpArea(AppColors colors, AppTypography typography) {
    return Column(
      children: [
        AppOtpInput(
          length: 4,
          controller: _otpController,
          enabled: !_submitting,
          onCompleted: _onOtpCompleted,
        ),
        if (_invalidCodeMessage != null) ...[
          const SizedBox(height: 8),
          Text(_invalidCodeMessage!, style: typography.body3.copyWith(color: colors.red)),
        ],
        if (_needsManualRetry) ...[
          const SizedBox(height: 12),
          AppButton.ghost(label: '다시 시도', size: ButtonSize.md, onPressed: _retry),
        ],
      ],
    );
  }

  Widget _bluetoothOffSection(AppColors colors, AppTypography typography) {
    return Column(
      children: [
        const BeaconPulse(state: BeaconPulseState.disconnected),
        const SizedBox(height: 16),
        Text(
          '블루투스가 꺼져 있습니다. 설정에서 블루투스를 켜주세요.',
          textAlign: TextAlign.center,
          style: typography.body3.copyWith(color: colors.gray2),
        ),
        const SizedBox(height: 16),
        AppButton.ghost(
          label: '설정 열기',
          size: ButtonSize.md,
          onPressed: () => ref.read(openBluetoothSettingsProvider)(),
        ),
      ],
    );
  }

  Widget _permissionDeniedSection(AppColors colors, AppTypography typography) {
    return Column(
      children: [
        const BeaconPulse(state: BeaconPulseState.disconnected),
        const SizedBox(height: 16),
        Text(
          '비콘 스캔 권한이 필요합니다. 설정에서 위치 권한을 허용해주세요.',
          textAlign: TextAlign.center,
          style: typography.body3.copyWith(color: colors.gray2),
        ),
      ],
    );
  }

  Widget _outOfRangeSection(AppColors colors, AppTypography typography) {
    return Column(
      children: [
        const BeaconPulse(state: BeaconPulseState.disconnected),
        const SizedBox(height: 16),
        Text(
          '비콘 범위를 벗어났습니다.',
          textAlign: TextAlign.center,
          style: typography.body3.copyWith(color: colors.gray2),
        ),
        const SizedBox(height: 16),
        AppButton.ghost(label: '다시 시도', size: ButtonSize.md, onPressed: _restartScan),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.colors, required this.typography});

  final String name;
  final AppColors colors;
  final AppTypography typography;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('$name님', style: typography.title4.copyWith(color: colors.gray3)),
        Text(_formatTodayLabel(DateTime.now()), style: typography.body3.copyWith(color: colors.gray2)),
      ],
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.records});

  final MonthlyRecords? records;

  @override
  Widget build(BuildContext context) {
    final r = records;
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            label: '이번달 출석률',
            value: r == null ? '-' : '${r.attendanceRate.toStringAsFixed(0)}%',
            progress: r == null ? null : r.attendanceRate / 100,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(label: '지각', value: r == null ? '-' : '${r.late}회'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(label: '결석', value: r == null ? '-' : '${r.absent}회'),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value, this.progress});

  final String label;
  final String value;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: typography.title7.copyWith(color: colors.gray2)),
          const SizedBox(height: 8),
          Text(value, style: typography.title3.copyWith(color: colors.gray3)),
          if (progress != null) ...[
            const SizedBox(height: 8),
            AppProgressBar(value: progress!),
          ],
        ],
      ),
    );
  }
}
