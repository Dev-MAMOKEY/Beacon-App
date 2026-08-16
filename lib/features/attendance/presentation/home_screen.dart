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

  /// 클럽 스코프 데이터(활성 세션·기록·비콘 설정)의 세대. 클럽이 바뀌거나
  /// 홈 탭이 다시 보일 때마다 증가한다. 이 값을 도입한 이유:
  ///
  /// 클럽 7의 비콘 설정 조회가 느리게 시작 → 세션이 클럽 9로 바뀌고 클럽 9의
  /// 조회가 먼저 끝남 → 클럽 7의 설정이 **마지막에** 도착해 클럽 9의 구독을
  /// 갈아치우고 클럽 7 스캔을 시작. 그러면 "비콘 감지 AND 활성 세션"은
  /// 구문적으로 참이지만 그 둘이 서로 다른 클럽의 사실이라, 클럽 7의 비콘
  /// 앞에서 클럽 9의 세션에 출석 코드를 넣게 된다(리뷰 Critical 2).
  /// 모든 비동기 완료 지점이 자기가 시작된 세대를 확인하고, 아니면 결과를
  /// 버린다.
  int _bootstrapGeneration = 0;

  /// 비콘 스캔 하나의 수명. [_bootstrapGeneration]과 따로 두는 이유는 "다시
  /// 시도"(범위 이탈 후 재스캔)가 진행 중인 세션·기록 조회까지 무효화할
  /// 이유는 없기 때문이다.
  int _scanGeneration = 0;

  /// 진행 중인 출석 체크 요청의 세대. 오래된 응답이 새 응답 뒤에 UI를
  /// 덮어쓰는 것을 막는다(리뷰 Important 4).
  int _submitGeneration = 0;

  ActiveSession? _activeSession;
  MonthlyRecords? _records;

  final AppOtpController _otpController = AppOtpController();
  final _CodeEntryState _codeEntryState = _CodeEntryState();
  String? _lastOtpCode;

  /// **이미 출석을 마친 세션의 id.** 성공 또는 ALREADY_CHECKED_IN에서 채워진다.
  ///
  /// 화면 단위 `bool`이 아니라 세션 id인 이유: `bool`로 두면 한 번 출석한 뒤
  /// 관리자가 **다른 세션**을 열어도 입력란이 다시 열리지 않는다. 클럽 변경
  /// 말고는 풀리는 경로가 없어서, 오전 세션에 출석한 부원이 오후 세션에는
  /// 앱을 죽이기 전까지 출석할 수 없었다(리뷰 Critical 1). 기록 화면이 하루
  /// 여러 세션을 명시적으로 모델링하므로 두 기능이 서로 모순됐다.
  int? _checkedInSessionId;

  /// 지금 열려 있는 활성 세션에 대해 이미 출석을 마쳤는가.
  ///
  /// 활성 세션이 없으면 거짓이다 — 그 경우 화면은 "출석 완료"가 아니라
  /// "진행 중인 세션 없음"을 보여줘야 한다.
  bool get _attendanceDone {
    final session = _activeSession;
    return session != null && session.sessionId == _checkedInSessionId;
  }

  /// 홈 탭이 지금 실제로 사용자에게 보이는지.
  ///
  /// `StatefulShellRoute.indexedStack`은 선택되지 않은 브랜치를 dispose하지
  /// 않고 `Offstage` + `TickerMode(enabled: false)`로 감싼 채 살려 둔다
  /// (go_router 17.5.0 `route.dart`의 `_IndexedStackedRouteBranchContainer.
  /// _buildRouteBranchContainer`에서 직접 확인했다). 그래서 `dispose()`의
  /// 정리 로직은 탭 전환으로는 아예 실행되지 않고, 숨은 홈이 계속 BLE를
  /// 돌리며 기록 탭 위로 코드 입력 팝업을 띄울 수 있었다(리뷰 Important 3).
  ///
  /// `TickerMode`를 가시성 신호로 쓸 수 있는 근거는 두 가지다.
  /// 1. 효과값이 조상과 AND로 합성된다(`_TickerModeState._updateEffectiveMode`
  ///    = `_ancestorTickerMode && widget.enabled`). 브랜치 안쪽 `Navigator`의
  ///    `Overlay`가 넣는 `TickerMode(enabled: true)`가 사이에 끼어도 최종
  ///    값은 여전히 false다.
  /// 2. 우리 팝업은 `PopupRoute`(=`opaque == false`)라 그 아래 오버레이
  ///    엔트리는 계속 onstage로 남고 `tickerEnabled`가 false로 내려가지
  ///    않는다(`overlay.dart`의 `OverlayState.build`는 **opaque** 엔트리
  ///    아래에만 `tickerEnabled: false`를 준다). 즉 우리 자신이 띄운
  ///    다이얼로그 때문에 "숨겨졌다"고 오판하지 않는다.
  bool _visible = true;

  /// 지금 실제로 화면에 떠 있는(것으로 우리가 추적하는) 상태 기반 팝업과
  /// **그 라우트 객체**.
  ///
  /// 라우트 객체를 함께 들고 있는 이유는 닫기와 완료 판정 둘 다 "그때 띄운
  /// 바로 그것"을 가리켜야 하기 때문이다. 예전에는 `Navigator.pop()`으로
  /// 닫았는데, 그건 "스택 맨 위"를 닫을 뿐 정체성을 모른다 — 우리 팝업 위에
  /// 다른 루트 라우트가 얹혀 있으면 엉뚱한 것이 닫히고 정작 조건이 거짓이 된
  /// 팝업은 그대로 남는다(리뷰 Important 6, `home_screen_test.dart`의
  /// "홈의 팝업 위에 다른 루트 라우트가 있어도…"가 이 회귀를 잡는다).
  HomePopupTarget _shownPopup = HomePopupTarget.none;
  Route<void>? _shownPopupRoute;

  /// 이 화면이 루트 내비게이터에 직접 push한 팝업 라우트 전부 — 상태 기반
  /// 팝업뿐 아니라 출석완료 팝업도 포함한다. 홈이 트리에서 빠지거나 홈 탭이
  /// 숨겨지면 여기 담긴 것을 전부 닫는다(리뷰 Important 6).
  final List<Route<void>> _ownedRoutes = [];

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 홈 탭이 보이는지/숨겨졌는지는 InheritedWidget(`_EffectiveTickerMode`)
    // 의존성으로 전달되므로, 그 값이 뒤집히는 순간 이 콜백이 불린다.
    // `TickerMode.of`는 3.35에서 deprecated돼 `valuesOf`를 쓴다.
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible == _visible) return;
    _visible = visible;
    if (visible) {
      _onBecameVisible();
    } else {
      _onBecameHidden();
    }
  }

  @override
  void dispose() {
    // 이 시점 이후에 도착하는 모든 비동기 완료를 무효화한다.
    _bootstrapGeneration++;
    _scanGeneration++;
    _submitGeneration++;
    unawaited(_cancelBeaconSubscription());
    // 화면을 벗어나면 스캔을 멈춘다 — watch()를 한 번도 부르지 못한
    // 채(예: 클럽 설정 조회 실패) 이 화면이 dispose돼도 안전하게 no-op이다.
    unawaited(_scanner.stop());
    _otpController.dispose();
    _codeEntryState.dispose();
    // 이 화면이 띄운 팝업은 전부 이 화면과 함께 사라져야 한다 — 안 그러면
    // 다이얼로그는 루트 내비게이터에 그대로 남아 다음에 보이는 화면 위에
    // 계속 떠 있는 채로 샌다. 코드·블루투스 팝업뿐 아니라 출석완료 팝업도
    // 포함이다(리뷰 Important 6).
    _closeOwnedPopups();
    super.dispose();
  }

  /// 홈 탭이 숨겨졌다 — BLE 스캔을 멈추고 이 화면이 띄운 팝업을 전부 닫는다.
  void _onBecameHidden() {
    unawaited(_stopScan());
    _beaconState = const BeaconIdle();
    // `didChangeDependencies`는 빌드 단계에서 불린다 — 내비게이션은 이
    // 프레임이 끝난 뒤로 미룬다. 추적 상태(_shownPopup 등)는 지금 바로
    // 지워야 그 사이에 도착하는 이벤트가 "이미 떠 있다"고 오판하지 않는다.
    final routes = _takeOwnedPopups();
    WidgetsBinding.instance.addPostFrameCallback((_) => _removeRoutes(routes));
  }

  /// 홈 탭이 다시 보인다 — 스캔과 클럽 스코프 데이터를 처음부터 다시
  /// 올린다. `watch()`가 새 세션(새 단조 시계 + 빈 스트릭)을 만들므로
  /// 안정화 스트릭도 0에서 다시 쌓인다.
  void _onBecameVisible() {
    final clubId = _bootstrappedClubId;
    // 아직 부트스트랩 전이면(숨은 채로 처음 마운트된 경우) 곧이어 실행될
    // build()가 부트스트랩을 시작한다.
    if (clubId == null) return;
    _bootstrap(clubId);
  }

  /// 클럽이 바뀌었다 — 이전 클럽에서 모은 것을 전부 버린다. 세대 검사만으로는
  /// **이미 도착해 화면에 반영된** 옛 클럽의 값(비콘 상태·활성 세션·기록·
  /// 출석 완료 여부)이 남아, 새 클럽의 값과 뒤섞여 AND 조건을 만족시킨다
  /// (리뷰 Critical 2).
  ///
  /// `build()` 중에 불리므로 여기서는 필드만 바꾸고(어차피 이어지는 build가
  /// 새 값을 읽는다) 내비게이션은 프레임 뒤로 미룬다.
  void _resetClubScopedState() {
    _beaconState = const BeaconIdle();
    _activeSession = null;
    _records = null;
    _checkedInSessionId = null;
    _lastOtpCode = null;
    final routes = _takeOwnedPopups();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _removeRoutes(routes);
      // `_codeEntryState.update`는 다이얼로그 쪽 `ListenableBuilder`를
      // 다시 그리게 하므로 빌드 중에는 부를 수 없다. 진행 중이던 제출은
      // 세대 검사로 이미 버려지지만, 그 결과가 남긴 `submitting`/오답
      // 메시지까지 여기서 함께 지운다.
      if (!mounted) return;
      _codeEntryState.update(
        submitting: false,
        clearInvalidCodeMessage: true,
        needsManualRetry: false,
      );
    });
  }

  void _bootstrap(int clubId) {
    final generation = ++_bootstrapGeneration;
    unawaited(_startBeaconScan(clubId));
    unawaited(_loadActiveSession(clubId, generation));
    unawaited(_loadRecords(clubId, generation));
  }

  /// [generation]이 아직 현재 부트스트랩 세대인지. 아니면 그 결과는 이미
  /// 다른 클럽(또는 이전 가시성 구간)의 것이므로 버려야 한다.
  bool _isCurrentBootstrap(int generation) => mounted && generation == _bootstrapGeneration;

  bool _isCurrentScan(int generation) => mounted && generation == _scanGeneration;

  /// 현재 구독만 끊는다. 네이티브 스캔 중지까지 하려면 [_stopScan].
  Future<void> _cancelBeaconSubscription() async {
    final sub = _beaconSub;
    _beaconSub = null;
    await sub?.cancel();
  }

  /// 스캔을 완전히 멈춘다. 세대를 먼저 올려, 진행 중이던 [_startBeaconScan]
  /// 이 뒤늦게 `watch()`를 불러 "아무도 멈추지 않는 스캔"을 남기는 것을
  /// 막는다(리뷰 Important 5).
  Future<void> _stopScan() async {
    _scanGeneration++;
    // 구독 취소는 기다리지 않는다 — 이 함수가 보장해야 하는 것은 "네이티브
    // 스캔이 실제로 멈췄다"이고 그건 `stop()`이 자기 teardown을 기다려
    // 보장한다. 뒤늦게 도착하는 옛 구독의 이벤트는 세대 검사가 이미
    // 무해하게 만든다.
    unawaited(_cancelBeaconSubscription());
    await _scanner.stop();
  }

  Future<void> _startBeaconScan(int clubId) async {
    final generation = ++_scanGeneration;

    final BeaconConfig beaconConfig;
    try {
      beaconConfig = await ref.read(beaconConfigRepositoryProvider).fetch(clubId);
    } catch (_) {
      return;
    }
    // 이 조회가 도는 동안 클럽이 바뀌었거나 화면이 사라졌으면 결과를
    // 버린다 — 늦게 도착한 옛 클럽의 설정이 현재 클럽의 스캔을 갈아치우는
    // 것이 리뷰 Critical 2의 실패 시나리오다.
    if (!_isCurrentScan(generation)) return;

    await _cancelBeaconSubscription();
    // `mounted`를 이 await **앞에서만** 보면, 취소를 기다리는 사이에
    // dispose가 일어난 경우 dispose()가 이미 stop()을 부른 뒤에 아래
    // watch()가 새 스캔을 시작한다 — 콜백은 무시되지만 그 스캔을 멈출
    // 주체가 아무도 없다(리뷰 Important 5).
    if (!_isCurrentScan(generation)) return;

    _beaconSub = _scanner.watch(beaconConfig.toScanConfig()).listen((state) {
      if (!_isCurrentScan(generation)) return;
      setState(() => _beaconState = state);
      _syncPopups();
    });
  }

  Future<void> _restartScan() async {
    final clubId = _bootstrappedClubId;
    if (clubId == null) return;
    await _stopScan();
    if (!mounted) return;
    setState(() => _beaconState = const BeaconIdle());
    _syncPopups();
    await _startBeaconScan(clubId);
  }

  Future<void> _loadActiveSession(int clubId, int generation) async {
    try {
      final session = await ref.read(attendanceRepositoryProvider).fetchActiveSession(clubId);
      if (!_isCurrentBootstrap(generation)) return;
      setState(() => _activeSession = session);
      _syncPopups();
    } catch (_) {
      // 활성 세션 조회 실패는 "세션 없음"과 같은 화면(안내 문구)으로
      // 수렴시킨다 — 홈 화면의 핵심 기능은 계속 동작해야 한다.
      if (!_isCurrentBootstrap(generation)) return;
      setState(() => _activeSession = null);
      _syncPopups();
    }
  }

  Future<void> _loadRecords(int clubId, int generation) async {
    final now = DateTime.now();
    try {
      final records = await ref
          .read(recordsRepositoryProvider)
          .fetch(clubId: clubId, year: now.year, month: now.month);
      if (!_isCurrentBootstrap(generation)) return;
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
    // 홈 탭이 숨겨져 있으면 무엇도 띄우지 않는다 — 숨은 홈이 기록 탭 위로
    // 코드 입력 팝업을 띄우던 경로를 여기서 끊는다(리뷰 Important 3).
    final target = _visible
        ? resolveHomePopupTarget(
            bluetoothOff: _beaconState is BeaconBluetoothOff,
            codeConditionRaw: _codeConditionRaw,
          )
        : HomePopupTarget.none;
    if (target == _shownPopup) return;

    // 이미 떠 있는 팝업이 있으면 새 팝업을 밀어 넣기 전에 먼저 닫는다 —
    // 두 팝업이 동시에 쌓이는 일은 없어야 한다(블루투스 꺼짐이 코드 입력을
    // 곧바로 대체하는 경우가 실제로 이 경로를 탄다).
    final previous = _shownPopupRoute;
    _shownPopup = target;
    _shownPopupRoute = null;
    if (previous != null) _removeOwnedRoute(previous);

    switch (target) {
      case HomePopupTarget.bluetoothOff:
        _shownPopupRoute = _pushBluetoothOffDialog();
      case HomePopupTarget.codeInput:
        _shownPopupRoute = _pushCodeInputDialog();
      case HomePopupTarget.none:
        break;
    }
  }

  /// 이 화면이 소유하는 팝업 라우트를 push한다. 완료 콜백이 추적 상태를
  /// 되돌릴지는 **라우트 정체성**(`identical`)으로 판정한다 — enum 값만
  /// 비교하면, 이미 다른 팝업으로 교체된 뒤에 도착한 옛 팝업의 완료가 자기
  /// 자신인 줄 알고 추적을 `none`으로 되돌릴 수 있다. 그러면 다음
  /// `_syncPopups`가 `target(none) == _shownPopup(none)`으로 조기 반환해
  /// 살아 있는 새 팝업이 영원히 남는다(리뷰 Critical 1).
  ///
  /// 오늘의 코드 경로에서는 그 오인이 실제로 일어나지 않는다 —
  /// `Navigator.pop()`/`removeRoute()`가 라우트의 `popped` future를
  /// **동기적으로** 완료시켜서, 완료 콜백은 항상 다음 push보다 먼저 도는
  /// 마이크로태스크에 놓인다(옛 구현에 로그를 심어 확인했다). 그래서 이
  /// `identical` 검사는 재현된 버그의 수정이라기보다, pop과 재push 사이에
  /// `await`이 하나라도 끼는 순간 활성화될 함정을 구조적으로 없애는 것이다.
  /// 아래 `_removeOwnedRoute`가 라우트 객체를 필요로 하므로 비용도 0이다.
  Route<void> _pushOwnedRoute(Route<void> route) {
    _ownedRoutes.add(route);
    unawaited(
      _rootNavigator.push<void>(route).then((_) {
        _ownedRoutes.remove(route);
        if (identical(_shownPopupRoute, route)) {
          _shownPopup = HomePopupTarget.none;
          _shownPopupRoute = null;
        }
      }),
    );
    return route;
  }

  Route<void> _pushOwnedPopup(WidgetBuilder builder) => _pushOwnedRoute(
    buildAppPopupRoute<void>(context: context, navigator: _rootNavigator, builder: builder),
  );

  /// [route]만 정확히 닫는다. `Navigator.pop()`은 "스택 맨 위"를 닫을 뿐
  /// 정체성을 모르므로, 우리 팝업 위에 다른 루트 라우트가 얹혀 있으면
  /// 엉뚱한 것을 닫는다(리뷰 Important 6).
  void _removeOwnedRoute(Route<void> route) {
    if (!_ownedRoutes.remove(route)) return;
    if (route.isActive) _rootNavigator.removeRoute(route);
  }

  /// 소유 목록을 비우고 그 내용을 돌려준다. 추적 상태를 먼저 지우기 위한
  /// 것이라 실제 제거([_removeRoutes])와 분리돼 있다 — 빌드 단계에서는
  /// 내비게이션을 할 수 없기 때문이다.
  List<Route<void>> _takeOwnedPopups() {
    _shownPopup = HomePopupTarget.none;
    _shownPopupRoute = null;
    final routes = List<Route<void>>.of(_ownedRoutes);
    _ownedRoutes.clear();
    return routes;
  }

  void _removeRoutes(List<Route<void>> routes) {
    for (final route in routes) {
      if (route.isActive) _rootNavigator.removeRoute(route);
    }
  }

  void _closeOwnedPopups() => _removeRoutes(_takeOwnedPopups());

  /// 블루투스 꺼짐 팝업(Figma `339:1676`)을 다이얼로그로 띄운다. 블로킹
  /// 팝업이라 스크림 탭으로도 시스템 뒤로가기로도 닫히지 않는다
  /// (`PopScope(canPop: false)` + `showAppPopup`의 기본 `barrierDismissible:
  /// false`) — 사용자가 빠져나가는 길은 블루투스를 직접 켜서 조건 자체를
  /// 거짓으로 만들거나(그러면 다음 비콘 이벤트에서 [_syncPopups]가 스스로
  /// 닫는다), 버튼으로 설정 화면에 가는 것뿐이다.
  Route<void> _pushBluetoothOffDialog() {
    return _pushOwnedPopup(
      (context) => PopScope(
        canPop: false,
        child: _BluetoothOffPopupContent(
          onOpenSettings: () => ref.read(openBluetoothSettingsProvider)(),
        ),
      ),
    );
  }

  /// 출석코드 입력 팝업(Figma `339:1683`)을 다이얼로그로 띄운다. Figma에
  /// 확인/취소 버튼이나 닫기 아이콘이 없다 — 4자리를 채우는 즉시 자동
  /// 제출하는 설계라(브리핑 2) 사용자가 직접 닫을 이유가 없고, 조건(비콘
  /// 감지 AND 활성 세션 AND 미완료)이 거짓이 되면 [_syncPopups]가 자동으로
  /// 닫는다. 그래서 스크림 탭으로도 시스템 뒤로가기로도 닫히지 않게 뒀다
  /// (`PopScope(canPop: false)`) — 닫는 방법이 아예 없는 게 아니라, 그
  /// 방법이 사용자 조작이 아니라 조건 자체의 전이라는 뜻이다.
  Route<void> _pushCodeInputDialog() {
    // 팝업을 새로 여는 것은 언제나 새 시도의 시작이다 — 이전에 열렸을 때
    // 남은 오답 메시지·재시도 버튼을 끌고 오지 않는다. 특히 재시도 버튼이
    // 살아남으면 그 버튼이 옛 `_lastOtpCode`를 다시 쏘아 올린다.
    // (`AppOtpInput`은 다이얼로그마다 새로 만들어지므로 입력 칸은 이미
    // 비어 있다.)
    _codeEntryState.update(
      submitting: false,
      clearInvalidCodeMessage: true,
      needsManualRetry: false,
    );
    return _pushOwnedPopup(
      (context) => PopScope(
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
    );
  }

  void _onOtpCompleted(String code) {
    unawaited(_submitCode(code));
  }

  Future<void> _retry() async {
    final code = _lastOtpCode;
    if (code == null) return;
    await _submitCode(code);
  }

  Future<void> _submitCode(String code) async {
    // 진행 중이면 아무것도 하지 않는다. OTP 칸의 비활성화(`enabled:
    // !submitting`)는 다음 리빌드에서야 반영되므로 그 사이에 두 번째
    // `onCompleted`가 끼어들 수 있고, 수동 재시도 버튼도 리빌드 전에 두 번
    // 눌릴 수 있다(리뷰 Important 4).
    if (_codeEntryState.submitting) return;

    final session = _activeSession;
    final clubId = _bootstrappedClubId;
    if (session == null || clubId == null) return;

    // 4자리를 채운 순간과 요청이 나가는 순간 사이에 범위를 벗어날 수 있고,
    // 팝업이 어떤 이유로든 새어 나온 상태일 수도 있다 — 제출 직전에 조건을
    // 다시 확인한다. 이 화면의 핵심 보증("비콘 감지 AND 활성 세션")은
    // 팝업의 존재가 아니라 이 검사가 지킨다(리뷰 Critical 1).
    if (!_visible || !_codeConditionRaw) return;

    final submitGeneration = ++_submitGeneration;
    final bootstrapGeneration = _bootstrapGeneration;
    // 이 요청이 아직 최신인가. `mounted`를 클로저 안에 숨기면
    // `use_build_context_synchronously` 린트가 가드를 인식하지 못하므로
    // 조건식만 뽑아 두고 `mounted`는 호출부에 그대로 남긴다.
    bool isLatest() =>
        submitGeneration == _submitGeneration && bootstrapGeneration == _bootstrapGeneration;

    _lastOtpCode = code;
    // 재시도 버튼은 이 요청이 도는 동안 사라져야 한다 — 남아 있으면 그
    // 버튼이 방금 새로 대입된 `_lastOtpCode`로 두 번째 요청을 겹쳐 띄운다.
    _codeEntryState.update(
      submitting: true,
      clearInvalidCodeMessage: true,
      needsManualRetry: false,
    );

    final CheckInResult result;
    try {
      result = await ref
          .read(attendanceControllerProvider)
          .submit(clubId: clubId, sessionId: session.sessionId, otpCode: code);
    } catch (_) {
      // `AttendanceController`는 `ApiException`만 `CheckInResult`로 접는다 —
      // 그 밖의 예외(파싱 실패 등)가 새면 `submitting`이 true로 굳어 입력란이
      // 영구히 잠기고, `_onOtpCompleted`가 `unawaited`로 부르므로 처리되지
      // 않은 비동기 오류가 된다(리뷰 Important 4).
      if (!mounted || !isLatest()) return;
      _codeEntryState.update(submitting: false, needsManualRetry: true);
      showAppToast(context, '출석 처리에 실패했습니다. 다시 시도해주세요.');
      return;
    }

    // 오래된 결과가 새 결과 뒤에 UI를 덮어쓰지 않게 한다. 클럽이 바뀌었다면
    // 이 응답은 이전 클럽의 것이므로 반영해서는 안 된다.
    if (!mounted || !isLatest()) return;
    _codeEntryState.update(submitting: false);

    switch (result) {
      case CheckInSuccess(:final status):
        setState(() => _checkedInSessionId = session.sessionId);
        // 코드 입력 조건이 거짓이 됐으니 그 팝업부터 닫는다 — 그러지
        // 않으면 아래에서 여는 출석완료 팝업이 이미 떠 있는 코드 입력
        // 팝업 위에 겹쳐 쌓인다.
        _syncPopups();
        _pushOwnedRoute(
          buildAttendanceSuccessRoute(context, navigator: _rootNavigator, status: status),
        );
      case CheckInInvalidCode():
        _otpController.shake();
        _codeEntryState.update(invalidCodeMessage: '비밀번호가 올바르지 않습니다');
      case CheckInAlreadyDone():
        setState(() => _checkedInSessionId = session.sessionId);
        _syncPopups();
        showAppToast(context, '이미 출석 처리되었습니다');
      case CheckInFailed(:final message):
        _codeEntryState.update(needsManualRetry: true);
        showAppToast(context, message);
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

    // 홈 탭이 숨어 있는 동안에는 부트스트랩하지 않는다 — `IndexedStack`은
    // 숨은 브랜치도 계속 build하므로, 이 가드가 없으면 숨은 채로 처음
    // 마운트된 홈이 곧장 BLE 스캔을 시작한다. 다시 보이는 순간
    // `didChangeDependencies` → `build()` 순서로 여기 다시 들어온다.
    if (_visible && _bootstrappedClubId != session.clubId) {
      final isClubChange = _bootstrappedClubId != null;
      _bootstrappedClubId = session.clubId;
      if (isClubChange) _resetClubScopedState();
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
