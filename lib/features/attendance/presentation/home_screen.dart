import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../components/beacon/beacon_pulse.dart';
import '../../../components/ui/app_progress_bar.dart';
import '../../../components/ui/button.dart';
import '../../../components/ui/card.dart';
import '../../../components/ui/otp_input.dart';
import '../../../components/ui/popup.dart';
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

/// Figma 실측(339:1498/326:1569 "환영인사 텍스트") — 연도·월·일을 모두
/// 2자리로 채운 "YYYY년 MM월 DD일" 형식이고 요일이 없다. 최초 구현은
/// 프로즈만 보고 "M월 D일 (요일)" 형식을 임의로 붙였었다.
String _formatTodayLabel(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}년 $month월 $day일';
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

  /// 비콘 감지 AND 활성 세션 AND 아직 미완료 — 코드 입력 팝업을 여는
  /// 유일한 조건. Figma 실측 결과 코드 입력은 홈 화면 안에 박혀 있는
  /// 콘텐츠가 아니라 그 위에 뜨는 별도 팝업(339:1683)이었다 — 그래서
  /// 조건에 따라 화면 트리에 얹었다 뗐다 하는 오버레이로 구현한다.
  bool get _codeInputOpen =>
      _beaconState is BeaconDetected && _activeSession != null && !_attendanceDone;

  /// 블루투스 꺼짐 팝업을 여는 유일한 조건. `_beaconState`가 이 상태를
  /// 벗어나는 순간(사용자가 설정에서 블루투스를 켜는 등) 조건이 거짓이
  /// 되어 팝업이 스스로 사라진다 — `_codeInputOpen`과 같은 오버레이
  /// 패턴이다.
  bool get _bluetoothOffPopupOpen => _beaconState is BeaconBluetoothOff;

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
      case CheckInSuccess(:final status):
        setState(() {
          _attendanceDone = true;
          _needsManualRetry = false;
        });
        await showAttendanceSuccessSheet(context, status: status);
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
      child: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 사용자 이름은 상단 바(AppShell)가 이미 보여준다(Figma
                  // "상단 메뉴") — 여기서 다시 반복하지 않는다. 날짜만
                  // 가운데 정렬로 표시한다.
                  Center(
                    child: Text(
                      _formatTodayLabel(DateTime.now()),
                      style: typography.title4.copyWith(color: colors.gray2),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Center(child: _buildBeaconSection(colors, typography)),
                  const SizedBox(height: 36),
                  _SummaryCards(records: _records),
                ],
              ),
            ),
          ),
          if (_codeInputOpen) _codeEntryOverlay(colors, typography),
          if (_bluetoothOffPopupOpen) _bluetoothOffOverlay(colors, typography),
        ],
      ),
    );
  }

  Widget _buildBeaconSection(AppColors colors, AppTypography typography) {
    return switch (_beaconState) {
      BeaconIdle() || BeaconScanning() => _scanningSection(colors, typography),
      BeaconDetected() => _detectedSection(colors, typography),
      // 안내 문구·버튼은 이제 별도 팝업(_bluetoothOffOverlay)이 담당한다 —
      // 배경은 미감지 상태와 같은 동심원만 그린다.
      BeaconBluetoothOff() => const BeaconPulse(state: BeaconPulseState.disconnected),
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
    // 코드 입력은 이제 별도 팝업(_codeEntryOverlay)이 담당한다 — 감지됨
    // 상태에서는 동심원과(있다면) 보조 안내문만 그린다.
    return Column(
      children: [
        const BeaconPulse(state: BeaconPulseState.connected),
        if (_activeSession == null) ...[
          const SizedBox(height: 24),
          Text(
            '현재 진행 중인 출석 세션이 없습니다',
            textAlign: TextAlign.center,
            style: typography.body3.copyWith(color: colors.gray2),
          ),
        ] else if (_attendanceDone) ...[
          const SizedBox(height: 24),
          Text('오늘 출석이 완료되었습니다', style: typography.body3.copyWith(color: colors.gray2)),
        ],
      ],
    );
  }

  /// 출석코드 입력 팝업(Figma `339:1683` "출석코드 팝업창"). 확인 버튼
  /// 탭이 아니라 조건(`_codeInputOpen`)에 따라 화면 트리에서 나타났다
  /// 사라진다 — 라우트 기반 다이얼로그가 아니라 오버레이인 이유는, 조건이
  /// 거짓이 되는 순간(비콘 범위 이탈 등) 별도의 팝(pop) 처리 없이 그냥
  /// 사라져야 하기 때문이다.
  Widget _codeEntryOverlay(AppColors colors, AppTypography typography) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.4),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: AppPopupCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '출석코드 입력',
                textAlign: TextAlign.center,
                style: typography.title4.copyWith(color: colors.gray3),
              ),
              const SizedBox(height: 8),
              Text(
                '4자리 번호를 입력하세요',
                textAlign: TextAlign.center,
                style: typography.body2.copyWith(color: colors.gray2),
              ),
              const SizedBox(height: 24),
              // Figma는 이 자리 아래에 버튼을 하나 더 그려 뒀지만(기본값
              // "로그인"이 그대로 남아 있어 미설정 상태로 보인다), 4자리를
              // 채우는 즉시 자동 제출한다는 명세서 요구와 정면으로
              // 충돌한다 — 확인 버튼을 요구하는 쪽은 명세서가 명시적으로
              // 금지하므로, 동작(스펙)을 따라 버튼을 넣지 않았다.
              // 조정자 확인 대기, 리포트 참고.
              AppOtpInput(
                length: 4,
                controller: _otpController,
                enabled: !_submitting,
                onCompleted: _onOtpCompleted,
              ),
              if (_invalidCodeMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _invalidCodeMessage!,
                  textAlign: TextAlign.center,
                  style: typography.body3.copyWith(color: colors.red),
                ),
              ],
              if (_needsManualRetry) ...[
                const SizedBox(height: 12),
                AppButton.ghost(label: '다시 시도', size: ButtonSize.md, onPressed: _retry),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 블루투스 꺼짐 팝업(Figma `339:1676`). 레이어 이름은 "코드팝업창"이지만
  /// 실제 내용은 출석코드 팝업(`339:1683`)의 변형이 아니라 "블루투스가
  /// 꺼져 있어요" + "블루투스 설정하러 가기" 버튼뿐인 별개 팝업이다 —
  /// `339:1683`을 복제해 만들고 레이어 이름을 안 고친 흔적으로 보인다.
  /// `_codeEntryOverlay`와 같은 오버레이 패턴: `_bluetoothOffPopupOpen`이
  /// 거짓이 되는 순간(블루투스가 다시 켜지는 등) 별도 pop 처리 없이 그냥
  /// 사라진다.
  Widget _bluetoothOffOverlay(AppColors colors, AppTypography typography) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.4),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: AppPopupCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '블루투스가 꺼져 있어요',
                textAlign: TextAlign.center,
                style: typography.title4.copyWith(color: colors.gray3),
              ),
              const SizedBox(height: 18),
              AppButton(
                label: '블루투스 설정하러 가기',
                onPressed: () => ref.read(openBluetoothSettingsProvider)(),
              ),
            ],
          ),
        ),
      ),
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

/// 요약 카드 3종(Figma `401:1986`/`404:2026` "출석 상태"). 전체 폭
/// 출석률 카드 하나 위에, 지각·결석 카드 두 개가 나란히 온다 — 세 칸이
/// 한 줄로 늘어선 배치가 아니다.
class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.records});

  final MonthlyRecords? records;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final r = records;

    return Column(
      children: [
        _RateCard(rate: r?.attendanceRate),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _CountCard(
                iconAsset: 'assets/icons/time-line.svg',
                iconColor: colors.yellow,
                label: '지각 횟수',
                value: r?.late,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: _CountCard(
                iconAsset: 'assets/icons/error-warning-line.svg',
                iconColor: colors.red,
                label: '결석 횟수',
                value: r?.absent,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RateCard extends StatelessWidget {
  const _RateCard({required this.rate});

  final double? rate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;
    final displayValue = rate == null ? '-' : rate!.toStringAsFixed(0);

    return AppCard(
      borderRadius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SvgPicture.asset(
                    'assets/icons/calendar-check-line.svg',
                    width: 24,
                    height: 24,
                    colorFilter: ColorFilter.mode(colors.main, BlendMode.srcIn),
                  ),
                  const SizedBox(height: 10),
                  Text('출석률', style: typography.body2.copyWith(color: colors.gray2)),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(displayValue, style: typography.number1.copyWith(color: colors.gray3)),
                  const SizedBox(width: 4),
                  // Figma는 "%" 표기를 23px SemiBold로 그렸다 — 토큰에
                  // 없는 크기라 가장 가까운 기존 토큰(title3, 24px)으로
                  // 대체했다.
                  Text('%', style: typography.title3.copyWith(color: colors.gray3)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          AppProgressBar(value: (rate ?? 0) / 100),
        ],
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({
    required this.iconAsset,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final String iconAsset;
  final Color iconColor;
  final String label;
  final int? value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return AppCard(
      borderRadius: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SvgPicture.asset(
                iconAsset,
                width: 24,
                height: 24,
                colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
              ),
              const SizedBox(height: 10),
              Text(label, style: typography.body2.copyWith(color: colors.gray2)),
            ],
          ),
          Text(
            value == null ? '-' : '$value',
            style: typography.number1.copyWith(color: colors.gray3),
          ),
        ],
      ),
    );
  }
}
