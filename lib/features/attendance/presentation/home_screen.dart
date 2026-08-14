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

/// 홈 화면이 지금 띄워야 할 상태 기반 팝업. 출석코드 입력·블루투스 꺼짐
/// 팝업은 버튼 탭 같은 "이벤트"가 아니라 조건(비콘 상태·활성 세션)의
/// 참/거짓 "전이"로 열리고 닫힌다 — [resolveHomePopupTarget]과
/// [HomePopupTarget]을 화면 상태(`_HomeScreenState`)와 분리한 순수 함수로
/// 뽑은 이유는 그 전이·우선순위 판정을 단위 테스트로 고정하기 위해서다.
@visibleForTesting
enum HomePopupTarget { none, bluetoothOff, codeInput }

/// 블루투스 꺼짐과 코드 입력 조건이 동시에 참이면 블루투스가 항상 이긴다
/// — 죽은 라디오 위에서 코드 입력을 받는 건 의미가 없다. `BeaconScanState`가
/// sealed class라 오늘은 두 조건이 동시에 참일 수 없지만(감지됨과 블루투스
/// 꺼짐은 같은 상태값의 서로 다른 변형이라 하나만 참일 수 있다), 그 사실에
/// 조용히 기대지 않는다 — 이 함수 자체가 우선순위를 강제해서, 상태 모델이
/// 나중에 바뀌어 두 조건이 실제로 동시에 참이 되어도 코드 입력이 이기는
/// 일이 없게 한다.
@visibleForTesting
HomePopupTarget resolveHomePopupTarget({
  required bool bluetoothOff,
  required bool codeConditionRaw,
}) {
  if (bluetoothOff) return HomePopupTarget.bluetoothOff;
  if (codeConditionRaw) return HomePopupTarget.codeInput;
  return HomePopupTarget.none;
}

/// 다이얼로그로 띄운 출석코드 팝업이 반응해야 하는 값(제출 중 여부·오답
/// 메시지·재시도 버튼 노출)만 뽑은 `ChangeNotifier`. 다이얼로그 라우트는
/// 루트 내비게이터의 오버레이에 별도로 얹힌 트리라 `_HomeScreenState`가
/// `setState`를 불러도 다이얼로그 쪽 서브트리는 자동으로 다시 그려지지
/// 않는다 — 그래서 다이얼로그 콘텐츠(`_CodeInputPopupContent`)가 이
/// notifier를 `ListenableBuilder`로 직접 구독한다.
class _CodeEntryState extends ChangeNotifier {
  bool submitting = false;
  String? invalidCodeMessage;
  bool needsManualRetry = false;

  void update({
    bool? submitting,
    String? invalidCodeMessage,
    bool clearInvalidCodeMessage = false,
    bool? needsManualRetry,
  }) {
    if (submitting != null) this.submitting = submitting;
    if (clearInvalidCodeMessage) this.invalidCodeMessage = null;
    if (invalidCodeMessage != null) this.invalidCodeMessage = invalidCodeMessage;
    if (needsManualRetry != null) this.needsManualRetry = needsManualRetry;
    notifyListeners();
  }
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
  final _CodeEntryState _codeEntryState = _CodeEntryState();
  String? _lastOtpCode;

  /// 성공 또는 ALREADY_CHECKED_IN 이후 true로 고정된다 — 그 뒤로는 비콘이
  /// 감지되고 활성 세션이 있어도 입력란을 다시 열지 않는다(브리핑 5-1).
  bool _attendanceDone = false;

  /// 지금 실제로 화면에 떠 있는(것으로 우리가 추적하는) 상태 기반 팝업.
  /// [_syncPopups]만 이 값을 바꾼다 — 다이얼로그를 밀어 넣거나(push) 빼는
  /// (pop) 모든 결정이 이 한 곳으로 모인다.
  HomePopupTarget _shownPopup = HomePopupTarget.none;

  /// `initState`에서 한 번 읽어 저장해 둔다 — Riverpod의
  /// `ConsumerStatefulElement`는 `dispose()` 시점에 `ref`가 이미
  /// 사용 불가 상태라 `ref.read`를 부르면 `StateError`가 난다
  /// (`context.mounted`가 `dispose()` 진입 전에 이미 false로 바뀐다).
  late final BeaconScanner _scanner;

  /// 같은 이유로 `dispose()` 시점을 위해 미리 잡아 둔다 — 이 시점엔 이
  /// 화면의 엘리먼트가 트리에서 빠지는 도중이라 `Navigator.of(context)`로
  /// 조상(루트 내비게이터)을 다시 찾는 걸 신뢰할 수 없다. 다이얼로그는
  /// 루트 내비게이터(=`AppShell` 바깥)에 붙어 있어 이 화면 자신의 위젯
  /// 트리와는 독립적으로 살아남으므로, 이 화면이 dispose돼도 팝업이 저절로
  /// 닫히지 않는다 — 명시적으로 닫아야 다음 탭으로 새지 않는다.
  late final NavigatorState _rootNavigator;

  @override
  void initState() {
    super.initState();
    _scanner = ref.read(beaconScannerProvider);
    _rootNavigator = Navigator.of(context, rootNavigator: true);
  }

  @override
  void dispose() {
    _beaconSub?.cancel();
    // 화면을 벗어나면 스캔을 멈춘다 — watch()를 한 번도 부르지 못한
    // 채(예: 클럽 설정 조회 실패) 이 화면이 dispose돼도 안전하게 no-op이다.
    unawaited(_scanner.stop());
    _otpController.dispose();
    _codeEntryState.dispose();
    // 열려 있던 상태 기반 팝업(코드 입력/블루투스 꺼짐)이 있으면 함께
    // 닫는다 — 안 그러면 이 화면이 탭 전환 등으로 트리에서 빠져도
    // 다이얼로그는 루트 내비게이터에 그대로 남아, 다음에 보이는 탭 위에
    // 계속 떠 있는 채로 샌다.
    if (_shownPopup != HomePopupTarget.none) {
      _rootNavigator.pop();
    }
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
      _syncPopups();
    });
  }

  Future<void> _restartScan() async {
    final clubId = _bootstrappedClubId;
    if (clubId == null) return;
    await _scanner.stop();
    if (!mounted) return;
    setState(() => _beaconState = const BeaconIdle());
    _syncPopups();
    await _startBeaconScan(clubId);
  }

  Future<void> _loadActiveSession(int clubId) async {
    try {
      final session = await ref.read(attendanceRepositoryProvider).fetchActiveSession(clubId);
      if (!mounted) return;
      setState(() => _activeSession = session);
      _syncPopups();
    } catch (_) {
      // 활성 세션 조회 실패는 "세션 없음"과 같은 화면(안내 문구)으로
      // 수렴시킨다 — 홈 화면의 핵심 기능은 계속 동작해야 한다.
      if (!mounted) return;
      setState(() => _activeSession = null);
      _syncPopups();
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

  /// 비콘 감지 AND 활성 세션 AND 아직 미완료 — 블루투스 꺼짐 우선순위는
  /// 고려하지 않은 "원값"이다. [resolveHomePopupTarget]이 이 값과
  /// 블루투스 꺼짐 여부를 함께 봐서 최종적으로 무엇을 띄울지 정한다.
  bool get _codeConditionRaw =>
      _beaconState is BeaconDetected && _activeSession != null && !_attendanceDone;

  /// 지금 떠 있어야 할 팝업과 실제로 추적 중인 팝업([_shownPopup])이
  /// 다르면 그 차이를 다이얼로그 push/pop으로 좁힌다. 상태가 바뀔 수 있는
  /// 모든 지점(비콘 스트림 이벤트, 활성 세션 조회, 출석 체크 결과) 직후에
  /// 이 함수를 부른다 — `build()`에서는 부르지 않는다(빌드 중 내비게이션은
  /// 반패턴이다).
  void _syncPopups() {
    if (!mounted) return;
    final target = resolveHomePopupTarget(
      bluetoothOff: _beaconState is BeaconBluetoothOff,
      codeConditionRaw: _codeConditionRaw,
    );
    if (target == _shownPopup) return;

    // 이미 떠 있는 팝업이 있으면 새 팝업을 밀어 넣기 전에 먼저 닫는다 —
    // 두 팝업이 동시에 쌓이는 일은 없어야 한다(블루투스 꺼짐이 코드 입력을
    // 곧바로 대체하는 경우가 실제로 이 경로를 탄다).
    if (_shownPopup != HomePopupTarget.none) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    _shownPopup = target;

    switch (target) {
      case HomePopupTarget.bluetoothOff:
        _pushBluetoothOffDialog();
      case HomePopupTarget.codeInput:
        _pushCodeInputDialog();
      case HomePopupTarget.none:
        break;
    }
  }

  /// 블루투스 꺼짐 팝업(Figma `339:1676`)을 다이얼로그로 띄운다. 블로킹
  /// 팝업이라 스크림 탭으로도 시스템 뒤로가기로도 닫히지 않는다
  /// (`PopScope(canPop: false)` + `showAppPopup`의 기본 `barrierDismissible:
  /// false`) — 사용자가 빠져나가는 길은 블루투스를 직접 켜서 조건 자체를
  /// 거짓으로 만들거나(그러면 다음 비콘 이벤트에서 [_syncPopups]가 스스로
  /// 닫는다), 버튼으로 설정 화면에 가는 것뿐이다.
  void _pushBluetoothOffDialog() {
    showAppPopup<void>(
      context: context,
      builder: (context) => PopScope(
        canPop: false,
        child: _BluetoothOffPopupContent(
          onOpenSettings: () => ref.read(openBluetoothSettingsProvider)(),
        ),
      ),
    ).then((_) {
      // 우리가 [_syncPopups]로 직접 pop한 게 아니라 다른 경로로 닫혔더라도
      // (예: 이론상의 향후 변경) _shownPopup을 반드시 되돌린다. 단, 이
      // then()이 실행되는 시점에 이미 다른 팝업으로 전이돼 있었다면
      // (_shownPopup이 더 이상 bluetoothOff가 아니라면) 그 최신 상태를
      // 덮어써서는 안 된다.
      if (mounted && _shownPopup == HomePopupTarget.bluetoothOff) {
        setState(() => _shownPopup = HomePopupTarget.none);
      }
    });
  }

  /// 출석코드 입력 팝업(Figma `339:1683`)을 다이얼로그로 띄운다. Figma에
  /// 확인/취소 버튼이나 닫기 아이콘이 없다 — 4자리를 채우는 즉시 자동
  /// 제출하는 설계라(브리핑 2) 사용자가 직접 닫을 이유가 없고, 조건(비콘
  /// 감지 AND 활성 세션 AND 미완료)이 거짓이 되면 [_syncPopups]가 자동으로
  /// 닫는다. 그래서 스크림 탭으로도 시스템 뒤로가기로도 닫히지 않게 뒀다
  /// (`PopScope(canPop: false)`) — 닫는 방법이 아예 없는 게 아니라, 그
  /// 방법이 사용자 조작이 아니라 조건 자체의 전이라는 뜻이다.
  void _pushCodeInputDialog() {
    showAppPopup<void>(
      context: context,
      builder: (context) => PopScope(
        canPop: false,
        child: ListenableBuilder(
          listenable: _codeEntryState,
          builder: (context, _) => _CodeInputPopupContent(
            controller: _otpController,
            state: _codeEntryState,
            onCompleted: _onOtpCompleted,
            onRetry: _retry,
          ),
        ),
      ),
    ).then((_) {
      if (mounted && _shownPopup == HomePopupTarget.codeInput) {
        setState(() => _shownPopup = HomePopupTarget.none);
      }
    });
  }

  void _onOtpCompleted(String code) {
    unawaited(_submitCode(code));
  }

  Future<void> _retry() async {
    final code = _lastOtpCode;
    if (code == null) return;
    _codeEntryState.update(needsManualRetry: false);
    await _submitCode(code);
  }

  Future<void> _submitCode(String code) async {
    final session = _activeSession;
    final clubId = _bootstrappedClubId;
    if (session == null || clubId == null) return;

    _lastOtpCode = code;
    _codeEntryState.update(submitting: true, clearInvalidCodeMessage: true);

    final result = await ref
        .read(attendanceControllerProvider)
        .submit(clubId: clubId, sessionId: session.sessionId, otpCode: code);

    if (!mounted) return;
    _codeEntryState.update(submitting: false);

    switch (result) {
      case CheckInSuccess(:final status):
        setState(() => _attendanceDone = true);
        // 코드 입력 조건이 거짓이 됐으니 그 팝업부터 닫는다 — 그러지
        // 않으면 아래에서 여는 출석완료 팝업이 이미 떠 있는 코드 입력
        // 팝업 위에 겹쳐 쌓인다.
        _syncPopups();
        await showAttendanceSuccessSheet(context, status: status);
      case CheckInInvalidCode():
        _otpController.shake();
        if (mounted) {
          _codeEntryState.update(invalidCodeMessage: '비밀번호가 올바르지 않습니다');
        }
      case CheckInAlreadyDone():
        setState(() => _attendanceDone = true);
        _syncPopups();
        if (mounted) showAppToast(context, '이미 출석 처리되었습니다');
      case CheckInFailed(:final message):
        _codeEntryState.update(needsManualRetry: true);
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

    // 출석코드 입력·블루투스 꺼짐 팝업은 더 이상 이 화면 트리 안의
    // Stack/Positioned.fill이 아니다 — 둘 다 [_syncPopups]가 다이얼로그
    // 라우트로 띄운다(루트 내비게이터에 붙어 하단 탭 셸 위로 뜬다). 그래서
    // 여기 build()는 홈 화면 본문만 그린다.
    return ColoredBox(
      color: colors.bg,
      child: SafeArea(
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
    );
  }

  Widget _buildBeaconSection(AppColors colors, AppTypography typography) {
    return switch (_beaconState) {
      BeaconIdle() || BeaconScanning() => _scanningSection(colors, typography),
      BeaconDetected() => _detectedSection(colors, typography),
      // 안내 문구·버튼은 이제 별도 팝업(_pushBluetoothOffDialog)이 담당한다
      // — 배경은 미감지 상태와 같은 동심원만 그린다.
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
    // 코드 입력은 이제 별도 다이얼로그(_pushCodeInputDialog)가 담당한다 —
    // 감지됨 상태에서는 동심원과(있다면) 보조 안내문만 그린다.
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

/// 출석코드 입력 팝업의 실제 콘텐츠(Figma `339:1683`). [state]가 바뀔
/// 때마다(오답 메시지·재시도 버튼·제출 중 여부) 다시 그려져야 하는데,
/// 이 위젯은 다이얼로그 라우트 안(루트 내비게이터의 오버레이)에 있어
/// `_HomeScreenState.setState()`만으로는 다시 그려지지 않는다 — 그래서
/// 호출자(`_pushCodeInputDialog`)가 `_codeEntryState`를 `ListenableBuilder`
/// 로 구독해 이 위젯을 감싼다.
class _CodeInputPopupContent extends StatelessWidget {
  const _CodeInputPopupContent({
    required this.controller,
    required this.state,
    required this.onCompleted,
    required this.onRetry,
  });

  final AppOtpController controller;
  final _CodeEntryState state;
  final ValueChanged<String> onCompleted;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Column(
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
        // 채우는 즉시 자동 제출한다는 명세서 요구와 정면으로 충돌한다 —
        // 확인 버튼을 요구하는 쪽은 명세서가 명시적으로 금지하므로, 동작
        // (스펙)을 따라 버튼을 넣지 않았다. 컴포넌트를 복제해 만들고 기본값
        // 텍스트를 안 바꾼 흔적이지 의도가 아니라는 뜻이다 — 나중에 Figma와
        // 대조하다 이 버튼을 "복원"하지 않는다.
        AppOtpInput(
          length: 4,
          controller: controller,
          enabled: !state.submitting,
          onCompleted: onCompleted,
        ),
        if (state.invalidCodeMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            state.invalidCodeMessage!,
            textAlign: TextAlign.center,
            style: typography.body3.copyWith(color: colors.red),
          ),
        ],
        if (state.needsManualRetry) ...[
          const SizedBox(height: 12),
          AppButton.ghost(label: '다시 시도', size: ButtonSize.md, onPressed: onRetry),
        ],
      ],
    );
  }
}

/// 블루투스 꺼짐 팝업의 실제 콘텐츠(Figma `339:1676`, 레이어 이름은
/// "코드팝업창"이지만 실제 내용은 `339:1683`의 변형이 아니라 별개의
/// "블루투스가 꺼져 있어요" + "블루투스 설정하러 가기" 팝업이다 — `339:1683`
/// 을 복제해 만들고 이름을 안 고친 흔적으로 보인다). 정적인 콘텐츠라
/// `_CodeInputPopupContent`와 달리 별도 notifier를 구독할 필요가 없다.
class _BluetoothOffPopupContent extends StatelessWidget {
  const _BluetoothOffPopupContent({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '블루투스가 꺼져 있어요',
          textAlign: TextAlign.center,
          style: typography.title4.copyWith(color: colors.gray3),
        ),
        const SizedBox(height: 18),
        AppButton(label: '블루투스 설정하러 가기', onPressed: onOpenSettings),
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
