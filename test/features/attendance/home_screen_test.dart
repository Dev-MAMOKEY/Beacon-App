import 'dart:async';

import 'package:beacon_app/components/ui/button.dart';
import 'package:beacon_app/components/ui/otp_input.dart';
import 'package:beacon_app/components/ui/popup.dart';
import 'package:beacon_app/core/network/api_exception.dart';
import 'package:beacon_app/core/network/error_code.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:beacon_app/core/time/kst.dart';
import 'package:beacon_app/features/attendance/data/attendance_dto.dart';
import 'package:beacon_app/features/attendance/data/attendance_repository.dart';
import 'package:beacon_app/features/attendance/presentation/home_screen.dart';
import 'package:beacon_app/features/auth/data/auth_dto.dart';
import 'package:beacon_app/features/auth/presentation/session_controller.dart';
import 'package:beacon_app/features/beacon/data/beacon_config_dto.dart';
import 'package:beacon_app/features/beacon/data/beacon_config_repository.dart';
import 'package:beacon_app/features/beacon/data/beacon_settings.dart';
import '../../support/fake_beacon_scanner.dart';
import 'package:beacon_app/features/beacon/data/flutter_beacon_scanner.dart';
import 'package:beacon_app/features/beacon/domain/beacon_scanner.dart';
import 'package:beacon_app/features/records/data/records_dto.dart';
import 'package:beacon_app/features/records/data/records_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _profile = MemberProfile(
  name: '김민준',
  stdId: '20250101',
  clubIds: [7],
  pushEnabled: true,
);

/// 같은 사용자가 다른 동아리를 primary로 갖게 된 경우 — `SessionReady.clubId`
/// 는 `profile.primaryClubId`에서 나온다.
const _otherClubProfile = MemberProfile(
  name: '김민준',
  stdId: '20250101',
  clubIds: [9],
  pushEnabled: true,
);

const _beaconConfig = BeaconConfig(
  uuid: 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0',
  lateThresholdMinutes: 10,
  rssiStabilizationSeconds: 3,
  rssiThreshold: -70,
);

const _club9BeaconConfig = BeaconConfig(
  uuid: 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE',
  lateThresholdMinutes: 10,
  rssiStabilizationSeconds: 3,
  rssiThreshold: -70,
);

const _activeSession = ActiveSession(
  sessionId: 88,
  sessionName: '정기모임',
  status: 'ACTIVE',
);

/// 같은 값이라도 **매번 새 인스턴스**를 만든다.
///
/// `const ActiveSession(...)`은 Dart가 정규화해 같은 인자면 같은 인스턴스를
/// 돌려주므로, 객체 동일성으로 키를 잡는 잘못된 구현을 테스트가 구별하지
/// 못한다. 프로덕션은 HTTP 응답마다 새 DTO를 만든다.
ActiveSession _freshSession({required int sessionId, required String sessionName}) {
  return ActiveSession(
    sessionId: sessionId,
    sessionName: sessionName,
    // 상수 접힘을 막아 매 호출이 새 인스턴스가 되게 한다.
    status: ['ACTIVE'].first,
  );
}

/// `SessionController.build()`가 곧장 `SessionReady`를 돌려주게 하는
/// 테스트 더블 — 토큰 저장소·인증 리포지토리를 전부 배선할 필요 없이
/// clubId를 곧장 확정할 수 있다.
class _ReadySessionController extends SessionController {
  _ReadySessionController(this._profile);

  MemberProfile _profile;

  @override
  Future<SessionState> build() async => SessionReady(_profile);

  /// 로그인한 채로 primary 동아리가 바뀌는 상황을 재현한다.
  void switchTo(MemberProfile next) {
    _profile = next;
    state = AsyncData(SessionReady(next));
  }
}

class _FakeBeaconConfigRepository implements BeaconConfigRepository {
  @override
  Future<BeaconConfig> fetch(int clubId) async => _beaconConfig;
}

/// 클럽별로 조회 완료 시점을 테스트가 직접 정하는 페이크 — "느리게 시작한
/// 옛 클럽의 설정이 새 클럽의 설정보다 늦게 도착한다"는 순서를 재현한다.
class _DeferredBeaconConfigRepository implements BeaconConfigRepository {
  final Map<int, Completer<BeaconConfig>> _pending = {};
  final List<int> requestedClubIds = [];

  @override
  Future<BeaconConfig> fetch(int clubId) {
    requestedClubIds.add(clubId);
    return (_pending[clubId] ??= Completer<BeaconConfig>()).future;
  }

  void complete(int clubId, BeaconConfig config) {
    (_pending[clubId] ??= Completer<BeaconConfig>()).complete(config);
  }
}

/// 구독 취소가 테스트의 신호를 기다리는 스캐너 — `_startBeaconScan`이
/// `await`로 취소를 기다리는 **그 사이에** dispose가 일어나는 창을 재현한다.
/// [FakeBeaconScanner]는 broadcast 컨트롤러라 `cancel()`이 곧장 끝나므로 이
/// 창을 만들 수 없다.
class _SlowCancelBeaconScanner implements BeaconScanner {
  _SlowCancelBeaconScanner(this.cancelGate);

  final Completer<void> cancelGate;
  int watchCallCount = 0;
  int stopCallCount = 0;

  @override
  Stream<BeaconScanState> watch(BeaconScanConfig config) {
    watchCallCount++;
    return StreamController<BeaconScanState>(onCancel: () => cancelGate.future).stream;
  }

  @override
  Future<void> stop() async => stopCallCount++;
}

/// 루트 내비게이터에 실제로 남아 있는 라우트를 추적한다. "팝업이 사라졌다"를
/// 텍스트 유무로만 확인하면, 보이는 내용만 지우고 투명한 모달 배리어·라우트를
/// 남겨 앱을 막아 버리는 구현도 통과한다.
class _RouteStackObserver extends NavigatorObserver {
  final List<Route<dynamic>> stack = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => stack.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => stack.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => stack.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : stack.indexOf(oldRoute);
    if (index >= 0 && newRoute != null) {
      stack[index] = newRoute;
    } else if (newRoute != null) {
      stack.add(newRoute);
    }
  }
}

/// checkIn 호출을 스크립트로 넣고, 실제로 전달된 인자를 기록하는 페이크.
class _ScriptedAttendanceRepository implements AttendanceRepository {
  _ScriptedAttendanceRepository({this.activeSession});

  ActiveSession? activeSession;
  final List<Object> results = []; // AttendanceStatus 또는 ApiException
  final List<(int clubId, int sessionId, String otpCode)> checkInArgs = [];
  int _callIndex = 0;

  /// null이 아니면 checkIn이 이 Future가 끝날 때까지 응답을 붙잡아 둔다 —
  /// "요청이 아직 진행 중"인 상태를 테스트가 유지할 수 있게 한다.
  Completer<void>? gate;

  /// [results]를 다 쓴 뒤에도 호출되면 이 값을 돌려준다(또는 던진다).
  Object? fallbackResult;

  int activeSessionCalls = 0;
  bool activeSessionThrowsOnce = false;

  @override
  Future<ActiveSession?> fetchActiveSession(int clubId) async {
    activeSessionCalls++;
    if (activeSessionThrowsOnce) {
      activeSessionThrowsOnce = false;
      throw Exception('일시적 조회 실패');
    }
    return activeSession;
  }

  @override
  Future<AttendanceStatus> checkIn({
    required int clubId,
    required int sessionId,
    required String otpCode,
  }) async {
    checkInArgs.add((clubId, sessionId, otpCode));
    final result = _callIndex < results.length ? results[_callIndex] : fallbackResult!;
    _callIndex++;
    final pending = gate;
    if (pending != null) await pending.future;
    if (result is ApiException) throw result;
    if (result is Exception) throw result;
    return result as AttendanceStatus;
  }
}

/// 어떤 (year, month)로 조회됐는지 기록하는 가짜. 수치와 실패도 지정할 수 있다.
class _RecordingRecordsRepository implements RecordsRepository {
  _RecordingRecordsRepository({this.present = 0, this.late = 0, this.absent = 0});

  final int present;
  final int late;
  final int absent;

  final List<(int year, int month)> requested = [];
  bool shouldThrow = false;

  @override
  Future<MonthlyRecords> fetch({
    required int clubId,
    required int year,
    required int month,
  }) async {
    requested.add((year, month));
    if (shouldThrow) throw Exception('조회 실패');
    return MonthlyRecords(
      year: year,
      month: month,
      records: const [],
      present: present,
      absent: absent,
      late: late,
      etc: 0,
      attendanceRate: 0,
    );
  }
}

class _FixedRecordsRepository implements RecordsRepository {
  const _FixedRecordsRepository({required this.late, required this.absent});

  final int late;
  final int absent;

  @override
  Future<MonthlyRecords> fetch({
    required int clubId,
    required int year,
    required int month,
  }) async {
    return MonthlyRecords(
      year: year,
      month: month,
      records: const [],
      present: 10,
      absent: absent,
      late: late,
      etc: 0,
      attendanceRate: 94,
    );
  }
}

/// 루트 내비게이터에 홈 화면 자신 말고 다른 라우트(=팝업)가 하나도 남아
/// 있지 않은지. `_pumpHome`의 하네스는 `MaterialApp(home: ...)` 라우트 하나로
/// 시작한다.
void _expectNoLeftoverPopupRoute(_RouteStackObserver routes, {String? reason}) {
  expect(
    routes.stack,
    hasLength(1),
    reason: reason ?? '보이는 내용만 지우고 모달 배리어·라우트를 남기면 앱이 그대로 막힌다',
  );
}

Future<({ProviderContainer container, _RouteStackObserver routes, ValueNotifier<bool> visible})>
_pumpHome(
  WidgetTester tester, {
  required BeaconScanner scanner,
  required _ScriptedAttendanceRepository attendanceRepository,
  BeaconConfigRepository? beaconConfigRepository,
  RecordsRepository? recordsRepository,
  DateTime Function()? clock,
  List<Override> extraOverrides = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      sessionControllerProvider.overrideWith(() => _ReadySessionController(_profile)),
      beaconScannerProvider.overrideWithValue(scanner),
      beaconConfigRepositoryProvider.overrideWithValue(
        beaconConfigRepository ?? _FakeBeaconConfigRepository(),
      ),
      attendanceRepositoryProvider.overrideWithValue(attendanceRepository),
      recordsRepositoryProvider.overrideWithValue(recordsRepository ?? _RecordingRecordsRepository()),
      ...extraOverrides,
    ],
  );
  addTearDown(container.dispose);
  final routes = _RouteStackObserver();

  // 실제 앱에서는 AppShell의 Scaffold 안에서 렌더되므로(app_router.dart),
  // 여기서도 Scaffold로 감싼다 — 그렇지 않으면 AppOtpInput의 TextField가
  // Material 조상을 찾지 못해 예외를 던진다.
  // `StatefulShellRoute.indexedStack`이 숨은 브랜치를 감싸는 방식 그대로 —
  // 탭 전환은 dispose가 아니라 TickerMode를 끄는 것이다. 실제 셸을 띄우지
  // 않고도 "탭을 떠났다 돌아왔다"를 재현할 수 있다.
  final visible = ValueNotifier<bool>(true);
  addTearDown(visible.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAppTheme(),
        navigatorObservers: [routes],
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (context, enabled, child) => TickerMode(enabled: enabled, child: child!),
            child: HomeScreen(clock: clock ?? DateTime.now),
          ),
        ),
      ),
    ),
  );
  // 1) 세션 판별(SessionController.build) 완료, 2) 그 결과로 홈 화면이
  // bootstrap을 시작, 3) bootstrap의 각 Future(비콘 설정 조회 → watch 구독
  // 시작, 활성 세션 조회, 기록 조회) 완료까지 흘려보낸다.
  await tester.pumpAndSettle();

  return (container: container, routes: routes, visible: visible);
}

Future<void> _enterOtp(WidgetTester tester, String code) async {
  final fields = find.byType(TextField);
  for (var i = 0; i < code.length; i++) {
    await tester.enterText(fields.at(i), code[i]);
    await tester.pump();
  }
}

/// 홈 화면 dispose 테스트 전용 호스트. 기존 "화면 dispose 시 스캔이
/// 중지된다" 테스트처럼 `tester.pumpWidget(SizedBox.shrink())`로 전체
/// 위젯 트리를 갈아치우면 `MaterialApp`(=루트 내비게이터·Overlay) 자체도
/// 사라져 버려, "다이얼로그가 실제로 pop됐는지"를 검증할 수 없다 — 그
/// 시점엔 다이얼로그가 붙어 있던 Overlay조차 이미 없기 때문이다. 이
/// 호스트는 `MaterialApp`은 살려 두고 `HomeScreen`만 트리에서 뺀다.
class _ToggleHome extends StatefulWidget {
  const _ToggleHome({super.key, required this.child});

  final Widget child;

  @override
  State<_ToggleHome> createState() => _ToggleHomeState();
}

class _ToggleHomeState extends State<_ToggleHome> {
  bool _visible = true;

  void hide() => setState(() => _visible = false);

  @override
  Widget build(BuildContext context) => _visible ? widget.child : const SizedBox.shrink();
}

void main() {
  testWidgets('비콘 감지 + 활성 세션 → 코드 입력란이 열린다', (tester) async {
    // 잡아야 할 잘못된 구현: 입력란을 조건 없이 항상 렌더한다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession);
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();

    expect(find.byType(AppOtpInput), findsOneWidget);
  });

  // Figma 실측(339:1683 "출석코드 팝업창")에서 처음 드러난 텍스트 — 최초
  // 구현(프로즈 브리핑 기반)에는 이 제목·안내 문구가 아예 없었다.
  testWidgets('코드 입력 팝업에 제목과 안내 문구가 표시된다', (tester) async {
    // 잡아야 할 잘못된 구현: 입력란만 그리고 제목/안내 문구를 빼먹는다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession);
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();

    expect(find.text('출석코드 입력'), findsOneWidget);
    expect(find.text('4자리 번호를 입력하세요'), findsOneWidget);
  });

  // Figma의 팝업엔 버튼이 하나 그려져 있지만(기본값 "로그인"이 그대로
  // 남아 있어 미설정 상태로 보인다), 명세서는 4자리 완성 즉시 자동
  // 제출하며 확인 버튼이 없어야 한다고 명시한다 — 동작은 명세서를
  // 따랐다(조정자 확인 대기). 이 결정이 조용히 뒤집히지 않도록 고정한다.
  testWidgets('코드 입력 팝업에는 확인 버튼이 없다', (tester) async {
    // 잡아야 할 잘못된 구현: Figma를 그대로 따라 확인/로그인 버튼을
    // 추가한다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession);
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();

    expect(find.byType(AppOtpInput), findsOneWidget);
    expect(find.byType(AppButton), findsNothing);
  });

  testWidgets('비콘 감지 + 세션 없음 → 입력란이 열리지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: 비콘 상태만 보고 입력란을 연다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: null);
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();

    expect(find.byType(AppOtpInput), findsNothing);
  });

  testWidgets('비콘 미감지 + 활성 세션 → 입력란이 열리지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: 활성 세션 존재만 보고 입력란을 연다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession);
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconScanning());
    await tester.pumpAndSettle();

    expect(find.byType(AppOtpInput), findsNothing);
  });

  testWidgets('4자리 입력 완료 시 확인 버튼 없이 checkIn이 호출된다', (tester) async {
    // 잡아야 할 잘못된 구현: 확인 버튼 탭을 기다린 뒤에만 checkIn을 부른다
    // — 이 테스트는 버튼을 전혀 찾지도, 탭하지도 않는다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
      ..results.add(AttendanceStatus.present);
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();

    await _enterOtp(tester, '1234');
    await tester.pumpAndSettle();

    expect(repo.checkInArgs, hasLength(1));
  });

  testWidgets('checkIn이 정확한 clubId/sessionId/otpCode로 호출된다', (tester) async {
    // 잡아야 할 잘못된 구현: 인자 순서가 뒤바뀌거나 세션 id가 하드코딩된다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
      ..results.add(AttendanceStatus.present);
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();

    await _enterOtp(tester, '7329');
    await tester.pumpAndSettle();

    expect(repo.checkInArgs.single, (7, 88, '7329'));
  });

  testWidgets('출석한 뒤 다른 세션이 열리면 코드 입력 팝업이 다시 열린다', (tester) async {
    // 잡아야 할 잘못된 구현: 출석 완료를 화면 단위 `bool`로 들고 클럽 변경
    // 으로만 푼다. 그러면 오전 세션에 출석한 부원이 오후 세션에는 앱을
    // 죽이기 전까지 출석할 수 없다(리뷰 Critical 1). 기록 화면은 하루
    // 여러 세션을 명시적으로 모델링하므로 두 기능이 서로 모순된다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
      ..results.add(AttendanceStatus.present);
    final harness = await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    await _enterOtp(tester, '1234');
    await tester.pumpAndSettle();

    // 완료 팝업을 닫는다.
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(find.text('출석코드 입력'), findsNothing, reason: '같은 세션에 다시 열려서는 안 된다');

    // 관리자가 **다른** 세션을 시작한다. 이름은 **일부러 같게** 둔다 —
    // 동아리가 '정기모임'을 하루 두 번 여는 것이 바로 이 수정이 존재하는
    // 이유이고, 이름으로 키를 잡는 구현은 그 경우 원래 결함을 그대로
    // 재현하면서도 테스트는 초록으로 남는다(리뷰 Important 1).
    repo.activeSession = const ActiveSession(
      sessionId: 99,
      sessionName: '정기모임',
      status: 'ACTIVE',
    );
    repo.results.add(AttendanceStatus.present);

    // 탭을 떠났다 돌아오면 활성 세션을 다시 조회한다.
    harness.visible.value = false;
    await tester.pumpAndSettle();
    harness.visible.value = true;
    await tester.pumpAndSettle();

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();

    expect(find.text('출석코드 입력'), findsOneWidget, reason: '다른 세션에는 다시 출석할 수 있어야 한다');
    // 팝업 뒤의 본문도 함께 갱신돼야 한다 — 한쪽 읽기 지점만 고치면 화면이
    // "출석이 완료되었습니다"라고 말하면서 동시에 코드를 요구한다
    // (리뷰 Important 3).
    expect(
      find.text('오늘 출석이 완료되었습니다'),
      findsNothing,
      reason: '아직 출석하지 않은 세션인데 완료 문구가 남아 있으면 안 된다',
    );
  });

  testWidgets('같은 세션이 그대로면 재방문해도 코드 입력 팝업이 열리지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: 래치를 아예 없애거나 재방문마다 초기화한다 —
    // 그러면 이미 출석한 세션에 대해 입력란이 계속 열려 중복 제출을 부른다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
      ..results.add(AttendanceStatus.present);
    final harness = await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    await _enterOtp(tester, '1234');
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    // 세션 id는 그대로(88)지만 **새 인스턴스**로 교체한다 — 프로덕션은 응답
    // 마다 새 DTO를 만들므로, 객체 동일성으로 키를 잡는 구현은 같은 세션을
    // 다시 조회하는 순간 팝업을 다시 열어 중복 제출을 부른다(리뷰 codex).
    //
    // `const`를 쓰면 안 된다 — Dart가 같은 인자의 const 표현식을 정규화해
    // **같은 인스턴스**를 돌려주므로, 객체 동일성 구현이 그대로 통과한다.
    // (처음에 const로 썼다가 이 변이가 살아남는 것을 확인했다.)
    repo.activeSession = _freshSession(sessionId: 88, sessionName: '정기모임');
    harness.visible.value = false;
    await tester.pumpAndSettle();
    harness.visible.value = true;
    await tester.pumpAndSettle();

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();

    expect(find.text('출석코드 입력'), findsNothing);
    expect(find.text('오늘 출석이 완료되었습니다'), findsOneWidget);
    expect(repo.checkInArgs, hasLength(1), reason: '같은 세션에 두 번 제출하지 않는다');
  });

  testWidgets('INVALID_ATTENDANCE_CODE → 입력이 비워지고 메시지가 뜬다', (tester) async {
    // 잡아야 할 잘못된 구현: 입력을 그대로 유지하거나 메시지를 띄우지 않는다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
      ..results.add(
        const ApiException(ErrorCode.invalidAttendanceCode, '비밀번호가 올바르지 않습니다.'),
      );
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();

    await _enterOtp(tester, '0000');
    await tester.pumpAndSettle();

    expect(find.text('비밀번호가 올바르지 않습니다'), findsOneWidget);
    for (final field in find.byType(TextField).evaluate()) {
      final textField = field.widget as TextField;
      expect(
        textField.controller!.text,
        isEmpty,
        reason: '오답 뒤에는 네 칸 모두 비워져 있어야 다음 시도가 옛 값과 섞이지 않는다',
      );
    }
  });

  testWidgets('ALREADY_CHECKED_IN → 입력란이 닫히고 완료 상태가 된다', (tester) async {
    // 잡아야 할 잘못된 구현: 이 코드를 그냥 에러로만 처리해 입력란이 계속
    // 열려 있어 재입력이 가능하다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
      ..results.add(const ApiException(ErrorCode.alreadyCheckedIn, '이미 출석 처리되었습니다.'));
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();

    await _enterOtp(tester, '1234');
    await tester.pumpAndSettle();

    expect(find.byType(AppOtpInput), findsNothing);
    expect(find.text('이미 출석 처리되었습니다'), findsOneWidget);
  });

  testWidgets('화면 dispose 시 스캔이 중지된다', (tester) async {
    // 잡아야 할 잘못된 구현: 구독을 취소만 하고 scanner.stop()을 부르지
    // 않아 네이티브 스캔이 화면을 떠나도 계속 돈다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession);
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();

    expect(scanner.stopCallCount, 0);
    final watchesBeforeDispose = scanner.watchCallCount;

    // 홈 화면을 트리에서 완전히 제거해 dispose를 유발한다.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(scanner.stopCallCount, greaterThanOrEqualTo(1));
    // 호출 횟수만 보면 "stop()을 부른 뒤 가드 없는 continuation이 다시
    // 스캔을 시작하는" 구현도 통과한다 — watch()가 늘지 않았는지도 본다
    // (그 창을 실제로 벌려 재현하는 것은 아래 `_SlowCancelBeaconScanner`
    // 테스트다).
    expect(scanner.watchCallCount, watchesBeforeDispose);
  });

  // Figma 실측(401:1986/404:2026 "출석 상태")에서 처음 드러난 라벨 —
  // 최초 구현은 프로즈만 보고 "이번달 출석률"/"지각"/"결석"이라는 다른
  // 문구를 썼다.
  testWidgets('요약 카드 라벨이 Figma 실측 문구(출석률/지각 횟수/결석 횟수)와 정확히 일치한다', (
    tester,
  ) async {
    // 잡아야 할 잘못된 구현: "이번달 출석률"/"지각"/"결석"처럼 프로즈에서
    // 임의로 지어낸 라벨을 그대로 쓴다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession);
    await _pumpHome(
      tester,
      scanner: scanner,
      attendanceRepository: repo,
      recordsRepository: const _FixedRecordsRepository(late: 2, absent: 1),
    );

    expect(find.text('출석률'), findsOneWidget);
    expect(find.text('지각 횟수'), findsOneWidget);
    expect(find.text('결석 횟수'), findsOneWidget);
    expect(find.text('이번달 출석률'), findsNothing);
  });

  // Figma 실측(339:1676, 레이어 이름은 "코드팝업창"이지만 실제 내용은
  // 별개의 블루투스 꺼짐 팝업)에서 처음 드러난 팝업 — 최초 구현은
  // 인라인 안내문 + "설정 열기" 버튼이었다. 조정자가 팝업 쪽을 채택했다.
  testWidgets('블루투스 꺼짐 상태에서 팝업이 뜬다', (tester) async {
    // 잡아야 할 잘못된 구현: 예전처럼 인라인 안내문만 그리고 팝업을
    // 띄우지 않는다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession);
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconBluetoothOff());
    await tester.pumpAndSettle();

    expect(find.text('블루투스가 꺼져 있어요'), findsOneWidget);
    expect(find.text('블루투스 설정하러 가기'), findsOneWidget);
  });

  testWidgets('블루투스 꺼짐이 아닌 상태로 바뀌면 팝업이 사라진다', (tester) async {
    // 잡아야 할 잘못된 구현: 한 번 뜨면 비콘 상태가 바뀌어도 팝업이
    // 계속 화면에 남는다(조건 없이 계속 렌더).
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession);
    final (container: _, :routes, visible: _) = await _pumpHome(
      tester,
      scanner: scanner,
      attendanceRepository: repo,
    );

    scanner.emit(const BeaconBluetoothOff());
    await tester.pumpAndSettle();
    expect(find.text('블루투스가 꺼져 있어요'), findsOneWidget);

    scanner.emit(const BeaconScanning());
    await tester.pumpAndSettle();

    expect(find.text('블루투스가 꺼져 있어요'), findsNothing);
    // 텍스트만 사라지고 다이얼로그 라우트(=모달 배리어)가 남으면 앱이
    // 그대로 막힌다 — 라우트 자체가 빠졌는지 확인한다.
    _expectNoLeftoverPopupRoute(routes);
  });

  testWidgets('블루투스 설정하러 가기를 누르면 설정 액션이 호출된다', (tester) async {
    // 잡아야 할 잘못된 구현: 버튼은 렌더하지만 onPressed가 실제 설정
    // 액션(openBluetoothSettingsProvider)을 부르지 않는다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession);
    var callCount = 0;
    await _pumpHome(
      tester,
      scanner: scanner,
      attendanceRepository: repo,
      extraOverrides: [
        openBluetoothSettingsProvider.overrideWithValue(() async {
          callCount++;
        }),
      ],
    );

    scanner.emit(const BeaconBluetoothOff());
    await tester.pumpAndSettle();

    await tester.tap(find.text('블루투스 설정하러 가기'));
    await tester.pumpAndSettle();

    expect(callCount, 1);
  });

  // 조정자 지시(2차) — 출석코드 입력·블루투스 꺼짐 팝업이 다이얼로그
  // 라우트로 바뀌면서 "조건이 참인 동안 화면 트리에 얹혀 있다 조건이
  // 거짓이 되면 사라진다"는 보증을 코드가 직접 챙겨야 하게 됐다(예전
  // Stack 오버레이는 조건부 렌더 한 줄이면 충분했다). 비콘이 범위를
  // 벗어나는 것은 `_attendanceDone`을 거치지 않고 코드 입력 조건
  // (`_codeConditionRaw`)이 직접 거짓이 되는 경로라, 기존 테스트들(모두
  // ALREADY_CHECKED_IN/성공 경로만 검증했다)과 다른 지점을 잡는다.
  testWidgets('비콘이 범위를 벗어나면 열려 있던 코드 입력 팝업이 닫힌다', (tester) async {
    // 잡아야 할 잘못된 구현: 코드 입력 조건이 거짓이 돼도 이미 띄운
    // 다이얼로그를 pop하지 않는다 — 비콘이 범위를 벗어나도 팝업이 화면에
    // 그대로 남는다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession);
    final (container: _, :routes, visible: _) = await _pumpHome(
      tester,
      scanner: scanner,
      attendanceRepository: repo,
    );

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    expect(find.text('출석코드 입력'), findsOneWidget);

    scanner.emit(const BeaconOutOfRange());
    await tester.pumpAndSettle();

    expect(find.text('출석코드 입력'), findsNothing);
    expect(find.byType(AppOtpInput), findsNothing);
    _expectNoLeftoverPopupRoute(routes);
  });

  testWidgets('블루투스 꺼짐 상태가 두 번 토글되어도 팝업은 한 번에 하나만 뜬다', (tester) async {
    // 잡아야 할 잘못된 구현: 이미 같은 팝업이 떠 있는지 확인하지 않고
    // 조건이 참일 때마다 무조건 새 다이얼로그를 밀어 넣는다 — 껐다 켰다
    // 반복하면 팝업이 여러 장 겹쳐 쌓인다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession);
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconBluetoothOff());
    await tester.pumpAndSettle();
    expect(find.text('블루투스가 꺼져 있어요'), findsOneWidget);

    scanner.emit(const BeaconScanning());
    await tester.pumpAndSettle();
    expect(find.text('블루투스가 꺼져 있어요'), findsNothing);

    scanner.emit(const BeaconBluetoothOff());
    await tester.pumpAndSettle();

    expect(find.text('블루투스가 꺼져 있어요'), findsOneWidget);
  });

  testWidgets('화면이 dispose되면 열려 있던 팝업도 함께 사라진다', (tester) async {
    // 잡아야 할 잘못된 구현: dispose()가 열려 있는 팝업을 닫지 않는다 —
    // 다이얼로그가 루트 내비게이터에 그대로 남아 홈 화면이 트리에서
    // 빠져도(예: 로그아웃, 향후 탭 재구성) 계속 화면 위에 떠 있게 샌다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession);
    final container = ProviderContainer(
      overrides: [
        sessionControllerProvider.overrideWith(() => _ReadySessionController(_profile)),
        beaconScannerProvider.overrideWithValue(scanner),
        beaconConfigRepositoryProvider.overrideWithValue(_FakeBeaconConfigRepository()),
        attendanceRepositoryProvider.overrideWithValue(repo),
        recordsRepositoryProvider.overrideWithValue(_RecordingRecordsRepository()),
      ],
    );
    addTearDown(container.dispose);

    final hostKey = GlobalKey<_ToggleHomeState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: _ToggleHome(key: hostKey, child: const HomeScreen())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    scanner.emit(const BeaconBluetoothOff());
    await tester.pumpAndSettle();
    expect(find.text('블루투스가 꺼져 있어요'), findsOneWidget);

    // HomeScreen만 트리에서 뺀다 — MaterialApp(=루트 내비게이터)은 살아
    // 있으므로, 팝업이 남아 있다면 계속 보일 것이다.
    hostKey.currentState!.hide();
    await tester.pumpAndSettle();

    expect(find.text('블루투스가 꺼져 있어요'), findsNothing);
  });

  testWidgets('서버가 LATE를 돌려주면 완료 화면이 지각 처리되었습니다를 보여준다', (tester) async {
    // 잡아야 할 잘못된 구현: 완료 문구를 "출석 완료"로 고정해 둔다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
      ..results.add(AttendanceStatus.late);
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();

    await _enterOtp(tester, '1234');
    await tester.pumpAndSettle();

    expect(find.text('지각 처리되었습니다'), findsOneWidget);
    expect(find.text('출석 완료!'), findsNothing);
    // 완료 팝업이 **아직 열려 있는 코드 입력 팝업 위에** 겹쳐 쌓여도 위
    // 두 expect는 통과한다 — 코드 팝업이 실제로 닫혔는지 함께 본다.
    expect(find.text('출석코드 입력'), findsNothing);
    expect(find.byType(AppOtpInput), findsNothing);
  });

  testWidgets('서버가 PRESENT를 돌려주면 출석 완료를 보여준다', (tester) async {
    // 위 테스트와 짝 — 서버 값을 실제로 읽어 반영하는지는 두 테스트가
    // 함께 있어야 증명된다(하나만 있으면 문구를 고정해도 그 하나는 통과한다).
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
      ..results.add(AttendanceStatus.present);
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();

    await _enterOtp(tester, '1234');
    await tester.pumpAndSettle();

    expect(find.text('출석 완료!'), findsOneWidget);
    expect(find.text('지각 처리되었습니다'), findsNothing);
    expect(find.text('출석코드 입력'), findsNothing);
    expect(find.byType(AppOtpInput), findsNothing);
  });

  // Figma 실측(339:1705)을 그대로 따른 결정 — 완료 팝업은 제목과 버튼
  // 뿐이다. 기능명세서 17-6은 체크 아이콘·처리 시각·세션 이름도
  // "표시 요소"로 명시하지만, 조정자가 이 화면에 한해 Figma를
  // 우선하기로 결정했다(이슈 #11 `## 범위 → ### 제외` 참고) — 처리
  // 시각·세션 이름은 기록 화면(#12)에서 확인한다.
  testWidgets('출석완료 팝업은 Figma 그대로 제목과 확인 버튼만 보여준다', (tester) async {
    // 잡아야 할 잘못된 구현: 명세서 17-6을 그대로 따라 체크 아이콘·처리
    // 시각·세션 이름을 계속 보여준다(이전 구현).
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
      ..results.add(AttendanceStatus.present);
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();

    await _enterOtp(tester, '1234');
    await tester.pumpAndSettle();

    expect(find.text('출석 완료!'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
    expect(find.textContaining(_activeSession.sessionName), findsNothing);
  });

  testWidgets('완료 화면의 확인을 누르면 홈으로 돌아가고 입력란이 사라진다', (tester) async {
    // 잡아야 할 잘못된 구현: 확인을 눌러도 완료 화면이 안 닫히거나, 닫힌
    // 뒤에 비콘·세션 조건이 여전히 참이라는 이유로 입력란이 다시 열린다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
      ..results.add(AttendanceStatus.present);
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();

    await _enterOtp(tester, '1234');
    await tester.pumpAndSettle();

    expect(find.text('출석 완료!'), findsOneWidget);

    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    expect(find.text('출석 완료!'), findsNothing, reason: '완료 시트가 닫혀 있어야 한다');
    // 비콘은 여전히 감지 상태(Detected)이고 활성 세션도 그대로지만, 이미
    // 출석을 마쳤으므로 입력란은 다시 열리면 안 된다.
    expect(find.byType(AppOtpInput), findsNothing);
  });

  // ---------------------------------------------------------------------
  // 리뷰 Important 6 (그리고 Critical 1이 요구한 "라우트 정체성") — 닫기가
  // `Navigator.pop()`이면 "스택 맨 위"를 닫을 뿐 정체성을 모른다. 홈이 띄운
  // 팝업 **위에** 다른 루트 라우트가 얹혀 있으면 엉뚱한 것이 닫히고, 정작
  // 조건이 거짓이 된 팝업은 그대로 남는다.
  // ---------------------------------------------------------------------
  testWidgets('홈의 팝업 위에 다른 루트 라우트가 있어도 홈은 자기 팝업만 닫는다', (tester) async {
    // 잡아야 할 잘못된 구현: `_syncPopups`가 `Navigator.pop()`으로 닫는다 —
    // 맨 위(다른 팝업)가 닫히고 블루투스 팝업은 그대로 남는다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession);
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconBluetoothOff());
    await tester.pumpAndSettle();
    expect(find.text('블루투스가 꺼져 있어요'), findsOneWidget);

    // 홈과 무관한 루트 라우트를 그 위에 얹는다. 불투명하지 않은
    // (PopupRoute 계열) 라우트여야 홈이 계속 보이는 상태로 남는다.
    final rootNavigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      rootNavigator.push<void>(
        DialogRoute<void>(
          context: rootNavigator.context,
          builder: (context) => const Text('다른 팝업', textDirection: TextDirection.ltr),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('다른 팝업'), findsOneWidget);

    // 블루투스가 켜졌다 — 홈은 **자기** 팝업만 닫아야 한다.
    scanner.emit(const BeaconScanning());
    await tester.pumpAndSettle();

    expect(
      find.text('블루투스가 꺼져 있어요'),
      findsNothing,
      reason: '조건이 거짓이 된 팝업은 스택 어디에 있든 닫혀야 한다',
    );
    expect(
      find.text('다른 팝업'),
      findsOneWidget,
      reason: '홈이 띄우지 않은 라우트를 홈이 닫아서는 안 된다',
    );
  });

  // ---------------------------------------------------------------------
  // 리뷰 Critical 2 — 비콘과 세션이 서로 다른 클럽에서 올 수 있다.
  // ---------------------------------------------------------------------
  testWidgets('늦게 도착한 옛 클럽의 비콘 설정이 현재 클럽의 스캔을 갈아치우지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: 비콘 설정 조회 완료 지점에 `mounted` 검사만
    // 있어, 클럽 7의 느린 조회가 클럽 9의 스캔이 시작된 **뒤에** 끝나면
    // 클럽 9의 구독을 취소하고 클럽 7 UUID로 스캔을 다시 건다. 그러면
    // 클럽 7의 비콘 앞에서 클럽 9의 세션에 출석하게 된다.
    final scanner = FakeBeaconScanner();
    final configRepo = _DeferredBeaconConfigRepository();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession);
    final (:container, routes: _, visible: _) = await _pumpHome(
      tester,
      scanner: scanner,
      attendanceRepository: repo,
      beaconConfigRepository: configRepo,
    );

    expect(configRepo.requestedClubIds, [7]);
    expect(scanner.watchCallCount, 0, reason: '클럽 7의 설정 조회가 아직 끝나지 않았다');

    // 세션의 클럽이 9로 바뀐다.
    (container.read(sessionControllerProvider.notifier) as _ReadySessionController).switchTo(
      _otherClubProfile,
    );
    await tester.pumpAndSettle();
    expect(configRepo.requestedClubIds, [7, 9]);

    // 클럽 9의 설정이 먼저 도착해 스캔이 시작된다.
    configRepo.complete(9, _club9BeaconConfig);
    await tester.pumpAndSettle();
    expect(scanner.watchCallCount, 1);
    expect(scanner.lastConfig!.uuid, _club9BeaconConfig.uuid);

    // 그 뒤에 클럽 7의 설정이 뒤늦게 도착한다.
    configRepo.complete(7, _beaconConfig);
    // `StreamSubscription.cancel()`이 돌려주는 `Future`는 루트 존 소유라
    // fakeAsync의 마이크로태스크 플러시로는 이어지지 않는다 — 실기기에서는
    // 곧바로 이어지는 그 연속을 테스트에서도 실제로 진행시켜야, 옛 클럽의
    // continuation이 `watch()`까지 갈 기회를 준다(그러지 않으면 이 테스트는
    // 버그가 있어도 통과한다).
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(
      scanner.lastConfig!.uuid,
      _club9BeaconConfig.uuid,
      reason: '이미 지나간 클럽의 설정으로 스캔을 다시 걸면 비콘과 세션이 서로 다른 클럽의 것이 된다',
    );
    expect(scanner.watchCallCount, 1);
  });

  testWidgets('클럽이 바뀌면 이전 클럽의 감지 상태와 열려 있던 코드 입력 팝업이 초기화된다', (tester) async {
    // 잡아야 할 잘못된 구현: 클럽이 바뀌어도 `_beaconState`/`_activeSession`/
    // `_attendanceDone`를 그대로 두어, 클럽 7에서 감지된 비콘과 클럽 9에서
    // 새로 조회한 세션이 AND 조건을 만족시킨다 — 팝업이 그대로 살아남는다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession);
    final (:container, :routes, visible: _) = await _pumpHome(
      tester,
      scanner: scanner,
      attendanceRepository: repo,
    );

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    expect(find.text('출석코드 입력'), findsOneWidget);

    (container.read(sessionControllerProvider.notifier) as _ReadySessionController).switchTo(
      _otherClubProfile,
    );
    await tester.pumpAndSettle();

    expect(
      find.text('출석코드 입력'),
      findsNothing,
      reason: '클럽 7의 비콘 감지로 열린 입력란이 클럽 9의 세션에 그대로 걸쳐 있으면 안 된다',
    );
    _expectNoLeftoverPopupRoute(routes);
    // 새 클럽에서는 아직 아무 비콘도 감지되지 않았다.
    expect(find.text('비콘을 찾는 중입니다...'), findsOneWidget);
  });

  testWidgets('앱이 백그라운드로 가면 스캔을 멈추고 코드 입력 팝업도 닫는다', (tester) async {
    // 잡아야 할 잘못된 구현: 탭 가시성(`TickerMode`)만 보고 앱 생명주기는
    // 보지 않는다. 앱을 백그라운드로 보내면 탭은 그대로 선택된 상태라
    // TickerMode가 바뀌지 않는데 OS는 ranging을 멈춘다 — 마지막 BeaconDetected가
    // 그대로 남아, 방을 나갔다 돌아온 뒤에도 코드를 넣으면 통과한다
    // (리뷰 Critical).
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession);
    final (container: _, :routes, visible: _) = await _pumpHome(
      tester,
      scanner: scanner,
      attendanceRepository: repo,
    );

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    expect(find.text('출석코드 입력'), findsOneWidget);
    expect(scanner.stopCallCount, 0);

    // 실제 전이 순서 그대로. `hidden`/`paused`부터가 ranging이 멈추는 구간이다.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    expect(scanner.stopCallCount, 1, reason: '백그라운드에서는 스캔을 멈춰야 한다');
    expect(
      find.text('출석코드 입력'),
      findsNothing,
      reason: '돌아왔을 때 낡은 감지 상태로 열린 팝업이 남아 있으면 안 된다',
    );
    // 내용만 지우고 모달 배리어를 남기면 앱이 그대로 막힌다 — 라우트 스택을
    // 직접 본다. `hidden`/`paused`에서는 프레임이 꺼지므로 팝업 정리를
    // post-frame 콜백에 맡길 수 없고, 그래서 생명주기 경로는 동기 제거를 쓴다.
    _expectNoLeftoverPopupRoute(routes);
  });

  testWidgets('응답이 도착할 때 홈이 숨겨져 있으면 완료 팝업을 다른 탭 위로 띄우지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: `_syncPopups`에만 `_visible` 가드를 두고 완료
    // 팝업 push에는 두지 않는다. 기존 가시성 테스트는 전부 **비콘 이벤트
    // 시점**에 발동하므로, **응답 완료 시점** 경로는 어떤 테스트도 지나가지
    // 않았다. 그 결과 전체 스크림을 가진 모달이 사용자가 보고 있는 탭 위에
    // 뜨고, 홈은 이미 숨겨져 `_onBecameHidden`이 다시 불리지 않으므로
    // 확인을 누르기 전엔 앱을 되찾을 수 없다(리뷰 Important 1).
    final scanner = FakeBeaconScanner();
    final gate = Completer<void>();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
      ..results.add(AttendanceStatus.present)
      ..gate = gate;
    final (container: _, :routes, :visible) = await _pumpHome(
      tester,
      scanner: scanner,
      attendanceRepository: repo,
    );

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    await _enterOtp(tester, '1234');
    await tester.pump();

    // 응답이 오기 전에 다른 탭으로 옮긴다.
    visible.value = false;
    await tester.pumpAndSettle();

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('출석 완료!'), findsNothing, reason: '숨은 홈이 다른 탭 위로 모달을 띄우면 안 된다');
    _expectNoLeftoverPopupRoute(routes);
    // 서버가 인정한 출석은 잊으면 안 된다 — 돌아왔을 때 중복 제출을 부른다.
    visible.value = true;
    await tester.pumpAndSettle();
    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    expect(find.text('출석코드 입력'), findsNothing, reason: '이미 출석한 세션이다');
    expect(find.text('오늘 출석이 완료되었습니다'), findsOneWidget);
  });

  group('KST — 홈과 기록이 같은 달을 가리킨다', () {
    // 홈은 `kst.dart`를 임포트조차 하지 않고 `DateTime.now()`를 그대로 썼다.
    // 기록 화면은 정확히 반대로 `toKst(widget.clock())`을 쓰고 그 이유를
    // 주석과 테스트로 고정해 뒀다. UTC 기기에서 두 화면이 다른 달을
    // 가리켰다(리뷰 Important).
    //
    // **KST 머신에서는 `toLocal()`로 바꿔도 통과하므로** 이 그룹은
    // `TZ=UTC`에서도 반드시 돌려야 의미가 있다.

    /// KST 9월 1일 00:00 — 경계를 **막 넘은** 순간.
    DateTime justAfterBoundary() => DateTime.utc(2026, 8, 31, 15);

    /// KST 8월 31일 23:59 — 경계 **직전**. 위와 1분 차이다.
    ///
    /// 두 값을 짝으로 쓰는 이유: 경계에서 멀리 떨어진 픽스처 하나만 쓰면
    /// 오프셋이 대략 +4~+27시간 아무 값이어도 통과한다. 실제로 처음엔
    /// `DateTime.utc(2026, 8, 31, 20)` 하나만 썼고, `kstOffset`을 5시간으로
    /// 바꾸는 변이를 새 테스트가 **하나도** 잡지 못했다(리뷰 Important 3).
    DateTime justBeforeBoundary() => DateTime.utc(2026, 8, 31, 14, 59);

    /// 같은 순간이지만 **로컬 플래그**로 넣는다 — 프로덕션의 `DateTime.now()`가
    /// 정확히 이 모양이고, `toKst`의 `.toUtc()`가 실제로 일하는 것도 이
    /// 경우뿐이다. `DateTime.utc(...)`만 먹이면 `.toUtc()`를 지워도, 결과에
    /// `.toLocal()`을 덧붙여도 전부 통과한다(리뷰 Important 2·3).
    DateTime justBeforeBoundaryLocal() => DateTime.utc(2026, 8, 31, 14, 30).toLocal();

    Future<_RecordingRecordsRepository> pumpWithClock(
      WidgetTester tester,
      DateTime Function() clock,
    ) async {
      final records = _RecordingRecordsRepository();
      await _pumpHome(
        tester,
        scanner: FakeBeaconScanner(),
        attendanceRepository: _ScriptedAttendanceRepository(activeSession: _activeSession),
        recordsRepository: records,
        clock: clock,
      );
      return records;
    }

    testWidgets('경계를 막 넘으면 요약 카드가 다음 달을 조회한다', (tester) async {
      final records = await pumpWithClock(tester, justAfterBoundary);
      expect(records.requested, [(2026, 9)]);
    });

    testWidgets('경계 1분 전이면 요약 카드가 이번 달을 조회한다', (tester) async {
      // 앞 테스트와 **1분 차이**다 — 둘이 짝을 이뤄야 오프셋이 정확히 +9시간
      // 임을 고정한다.
      final records = await pumpWithClock(tester, justBeforeBoundary);
      expect(records.requested, [(2026, 8)]);
    });

    testWidgets('경계를 막 넘으면 오늘 날짜 라벨도 다음 달이다', (tester) async {
      await pumpWithClock(tester, justAfterBoundary);
      expect(find.text('2026년 09월 01일'), findsOneWidget);
    });

    testWidgets('경계 1분 전이면 오늘 날짜 라벨이 이번 달이다', (tester) async {
      await pumpWithClock(tester, justBeforeBoundary);
      expect(find.text('2026년 08월 31일'), findsOneWidget);
    });

    testWidgets('로컬 플래그로 들어온 시각도 KST로 옮긴다', (tester) async {
      // 잡아야 할 잘못된 구현: `toKst`에서 `.toUtc()`를 빼거나, 결과에
      // `.toLocal()`을 덧붙인다. UTC 픽스처만으로는 둘 다 살아남는다.
      final records = await pumpWithClock(tester, justBeforeBoundaryLocal);
      expect(records.requested, [(2026, 8)]);
      expect(find.text('2026년 08월 31일'), findsOneWidget);
    });

    testWidgets('화면이 살아 있는 동안 KST 자정을 넘으면 지난달 수치를 그대로 보여주지 않는다', (
      tester,
    ) async {
      // 잡아야 할 잘못된 구현: 조회 월과 렌더 시각을 대조하지 않는다. 조회는
      // 부트스트랩 때 한 번, 라벨은 매 빌드마다다 — 자정을 넘으면 라벨만
      // 넘어가고 카드는 지난달 수치를 그대로 들고 있다. 홈의 카드에는 월
      // 표시가 없어 화면상 아무 신호가 없다(리뷰 Important 1).
      var now = DateTime.utc(2026, 8, 31, 14, 58); // KST 23:58
      final records = _RecordingRecordsRepository(present: 7, late: 2, absent: 1);
      final scanner = FakeBeaconScanner();
      await _pumpHome(
        tester,
        scanner: scanner,
        attendanceRepository: _ScriptedAttendanceRepository(activeSession: _activeSession),
        recordsRepository: records,
        clock: () => now,
      );

      expect(records.requested, [(2026, 8)]);
      expect(find.text('2'), findsOneWidget, reason: '사전 조건: 8월 지각 2회가 보인다');

      // 자정을 넘긴다. 스캐너 이벤트가 리빌드를 일으킨다(실제 앱과 같다).
      now = DateTime.utc(2026, 8, 31, 15, 1); // KST 09-01 00:01
      scanner.emit(const BeaconScanning());
      await tester.pumpAndSettle();

      expect(find.text('2026년 09월 01일'), findsOneWidget);
      expect(
        find.text('2'),
        findsNothing,
        reason: '9월 라벨 아래 8월 수치가 남아 있으면 안 된다',
      );
    });

    testWidgets('재조회가 실패하면 이전 달 수치를 지운다', (tester) async {
      // 잡아야 할 잘못된 구현: `catch (_)`에서 아무것도 하지 않는다. 최초
      // 로드에서만 "대시로 남는다"가 참이고, 재부트스트랩에서는 `_records`가
      // 이미 차 있어 **이전 달 숫자가 새 달 라벨 아래 그대로 남는다**
      // (리뷰 Important 5). 기록 화면은 같은 상황에서 이미 비우고 있었다.
      var now = DateTime.utc(2026, 8, 31, 14, 58);
      final records = _RecordingRecordsRepository(present: 7, late: 2, absent: 1);
      final (container: _, routes: _, :visible) = await _pumpHome(
        tester,
        scanner: FakeBeaconScanner(),
        attendanceRepository: _ScriptedAttendanceRepository(activeSession: _activeSession),
        recordsRepository: records,
        clock: () => now,
      );
      expect(find.text('2'), findsOneWidget);

      // 자정을 넘긴 뒤 탭을 떠났다 돌아온다 — 재조회가 실패한다.
      now = DateTime.utc(2026, 8, 31, 15, 1);
      records.shouldThrow = true;
      visible.value = false;
      await tester.pumpAndSettle();
      visible.value = true;
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1)));
        await tester.pumpAndSettle();
      }

      expect(records.requested, [(2026, 8), (2026, 9)]);
      expect(find.text('2'), findsNothing, reason: '실패했으면 옛 수치를 지워야 한다');
    });

    testWidgets('주입하지 않으면 프로덕션 기본 시계를 쓴다', (tester) async {
      // 잡아야 할 잘못된 구현: 기본 시계를 엉뚱한 값으로 둔다. 모든 테스트가
      // clock을 주입하므로 프로덕션 기본값(`DateTime.now`)은 한 번도 검증되지
      // 않았고, 실제로 `DateTime.utc(1999,1,1)`로 바꿔도 409개가 전부
      // 통과했다(리뷰 Important 4). #40의 `Timer.new`와 같은 유형이다.
      final expected = toKst(DateTime.now());
      await _pumpHome(
        tester,
        scanner: FakeBeaconScanner(),
        attendanceRepository: _ScriptedAttendanceRepository(activeSession: _activeSession),
      );

      final month = expected.month.toString().padLeft(2, '0');
      final day = expected.day.toString().padLeft(2, '0');
      expect(find.text('${expected.year}년 $month월 $day일'), findsOneWidget);
    });
  });

  group('활성 세션 갱신 — 탭을 옮기지 않아도 따라잡는다', () {
    // 부트스트랩 1회 조회만으로는 세 가지가 전부 깨진다(리뷰 Important 1):
    // 세션 종료 후에도 팝업이 남아 종료된 세션에 제출하고, 나중에 시작된
    // 세션은 탭을 옮겼다 돌아오기 전까지 열리지 않으며, 첫 조회가 실패하면
    // 그 가시성 구간 내내 "세션 없음"으로 굳는다.

    testWidgets('세션이 시작되면 탭을 옮기지 않아도 입력란이 열린다', (tester) async {
      final scanner = FakeBeaconScanner();
      final repo = _ScriptedAttendanceRepository(activeSession: null);
      await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

      scanner.emit(const BeaconDetected(-60));
      await tester.pumpAndSettle();
      expect(find.text('출석코드 입력'), findsNothing, reason: '사전 조건: 아직 세션이 없다');

      // 관리자가 세션을 시작한다. 탭은 그대로 둔다.
      repo.activeSession = _activeSession;
      await tester.pump(activeSessionRefreshInterval);
      await tester.pumpAndSettle();

      expect(find.text('출석코드 입력'), findsOneWidget);
    });

    testWidgets('세션이 종료되면 열려 있던 입력란이 닫힌다', (tester) async {
      final scanner = FakeBeaconScanner();
      final repo = _ScriptedAttendanceRepository(activeSession: _activeSession);
      final (container: _, :routes, visible: _) = await _pumpHome(
        tester,
        scanner: scanner,
        attendanceRepository: repo,
      );

      scanner.emit(const BeaconDetected(-60));
      await tester.pumpAndSettle();
      expect(find.text('출석코드 입력'), findsOneWidget);

      repo.activeSession = null;
      await tester.pump(activeSessionRefreshInterval);
      await tester.pumpAndSettle();

      expect(find.text('출석코드 입력'), findsNothing);
      _expectNoLeftoverPopupRoute(routes);
    });

    testWidgets('첫 조회가 실패해도 다음 주기에 회복한다', (tester) async {
      final scanner = FakeBeaconScanner();
      final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
        ..activeSessionThrowsOnce = true;
      await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

      scanner.emit(const BeaconDetected(-60));
      await tester.pumpAndSettle();
      expect(find.text('출석코드 입력'), findsNothing, reason: '사전 조건: 첫 조회가 실패했다');

      await tester.pump(activeSessionRefreshInterval);
      await tester.pumpAndSettle();

      expect(find.text('출석코드 입력'), findsOneWidget);
    });

    testWidgets('status가 ACTIVE가 아니면 세션이 없는 것으로 친다', (tester) async {
      // 잡아야 할 잘못된 구현: `null` 여부만 보고 `status`를 무시한다. 1회
      // 조회일 때는 그래도 됐지만, 15초마다 물으면 **세션이 막 끝나는 순간과
      // 겹치는 응답**을 받을 수 있다 — 그때 `ENDED`를 활성으로 취급하면 끝난
      // 세션에 대해 입력란을 열어 둔다.
      final scanner = FakeBeaconScanner();
      final repo = _ScriptedAttendanceRepository(
        activeSession: const ActiveSession(
          sessionId: 88,
          sessionName: '정기모임',
          status: 'ENDED',
        ),
      );
      await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

      scanner.emit(const BeaconDetected(-60));
      await tester.pumpAndSettle();

      expect(find.text('출석코드 입력'), findsNothing);
      expect(find.text('현재 진행 중인 출석 세션이 없습니다'), findsOneWidget);
    });

    testWidgets('숨겨진 동안에는 재조회하지 않는다', (tester) async {
      // 잡아야 할 잘못된 구현: 타이머를 멈추지 않는다 — 보이지도 않는 탭이
      // 계속 서버를 두드리고, 그 결과가 숨은 채로 팝업 상태를 흔든다.
      final scanner = FakeBeaconScanner();
      final repo = _ScriptedAttendanceRepository(activeSession: _activeSession);
      final (container: _, routes: _, :visible) = await _pumpHome(
        tester,
        scanner: scanner,
        attendanceRepository: repo,
      );
      final before = repo.activeSessionCalls;

      visible.value = false;
      await tester.pumpAndSettle();
      await tester.pump(activeSessionRefreshInterval * 3);
      await tester.pumpAndSettle();

      expect(repo.activeSessionCalls, before, reason: '숨은 동안에는 조회하지 않는다');
    });
  });

  group('제출 직전 검사 — 팝업이 새어 나와도 조건이 거짓이면 보내지 않는다', () {
    // 이 화면의 핵심 보증("비콘 감지 AND 활성 세션")은 팝업의 존재가 아니라
    // `_submitCode` 첫 줄의 검사가 지킨다 — 소스에도 그렇게 적혀 있다.
    // 그런데 **그 줄을 통째로 지워도 스위트가 초록이었다**(#44). 팝업이 닫히면
    // 입력할 방법이 없어 어떤 테스트도 그 경로를 지나가지 않았기 때문이다.
    //
    // 그래서 "팝업이 어떤 이유로든 새어 나온 상태"를 직접 만든다 — 열려 있는
    // 동안 `onCompleted` 콜백을 붙잡아 두었다가, 조건을 거짓으로 만든 뒤에
    // 그 콜백을 부른다. 방어적 경로를 시험하는 정직한 방법이다.
    ValueChanged<String> captureOnCompleted(WidgetTester tester) =>
        tester.widget<AppOtpInput>(find.byType(AppOtpInput)).onCompleted;

    testWidgets('비콘이 범위를 벗어난 뒤 도착한 완료는 제출되지 않는다', (tester) async {
      final scanner = FakeBeaconScanner();
      final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
        ..results.add(AttendanceStatus.present);
      await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

      scanner.emit(const BeaconDetected(-60));
      await tester.pumpAndSettle();
      final onCompleted = captureOnCompleted(tester);

      scanner.emit(const BeaconOutOfRange());
      await tester.pumpAndSettle();

      onCompleted('1234');
      await tester.pumpAndSettle();

      expect(repo.checkInArgs, isEmpty, reason: '방을 나갔는데 출석이 나가면 보증이 무너진다');
    });

    testWidgets('활성 세션이 사라진 뒤 도착한 완료는 제출되지 않는다', (tester) async {
      final scanner = FakeBeaconScanner();
      final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
        ..results.add(AttendanceStatus.present);
      await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

      scanner.emit(const BeaconDetected(-60));
      await tester.pumpAndSettle();
      final onCompleted = captureOnCompleted(tester);

      // 세션이 종료된다(#45의 폴링이 이걸 따라잡는다).
      repo.activeSession = null;
      await tester.pump(activeSessionRefreshInterval);
      await tester.pumpAndSettle();

      onCompleted('1234');
      await tester.pumpAndSettle();

      expect(repo.checkInArgs, isEmpty, reason: '종료된 세션에 출석을 보내면 안 된다');
    });

    testWidgets('탭이 숨겨진 뒤 도착한 완료는 제출되지 않는다', (tester) async {
      // 잡아야 할 잘못된 구현: 제출 직전 검사에서 `!_visible`만 뺀다.
      // 비콘 상태와 세션은 그대로라 `_codeConditionRaw`는 여전히 참이다 —
      // 가시성 항이 유일한 방어다.
      final scanner = FakeBeaconScanner();
      final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
        ..results.add(AttendanceStatus.present);
      final (container: _, routes: _, :visible) = await _pumpHome(
        tester,
        scanner: scanner,
        attendanceRepository: repo,
      );

      scanner.emit(const BeaconDetected(-60));
      await tester.pumpAndSettle();
      final onCompleted = captureOnCompleted(tester);

      visible.value = false;
      await tester.pumpAndSettle();

      onCompleted('1234');
      await tester.pumpAndSettle();

      expect(repo.checkInArgs, isEmpty, reason: '보이지도 않는 탭이 출석을 보내면 안 된다');
    });
  });

  testWidgets('서버 오류 메시지는 토스트가 아니라 팝업 안에 보인다', (tester) async {
    // 잡아야 할 잘못된 구현: `showAppToast`로 띄운다. 그 `SnackBar`는 셸
    // `Scaffold` 안에 그려지는데, 코드 입력 팝업이 아직 열려 있어 그 위에
    // 깔린 `ModalBarrier`(스크림)가 덮는다. 사용자는 실패한 것만 알고 이유는
    // 끝내 못 본다.
    //
    // **`find.text`만으로는 인라인과 토스트를 구별하지 못한다** — 토스트도
    // 같은 문자열을 그린다. `SnackBar` 부재를 함께 검사해야 판별된다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
      ..results.add(const ApiException(ErrorCode.network, '서버에 연결하지 못했습니다.'))
      ..results.add(const ApiException(ErrorCode.network, '서버에 연결하지 못했습니다.'));
    final (container: _, :routes, visible: _) = await _pumpHome(
      tester,
      scanner: scanner,
      attendanceRepository: repo,
    );

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    await _enterOtp(tester, '1234');
    await tester.pumpAndSettle();

    // **`find.text`만으로는 어디에 그려졌는지 알 수 없다.** 오류 문구를 홈
    // 본문(스크림 **아래**)에 그리는 구현도 그 검사를 통과한다 — 리뷰에서
    // 실제로 그 변이가 405개를 전부 통과했고, 그게 바로 이 수정이 막으려던
    // 버그다. 팝업 카드의 자손인지까지 봐야 한다.
    expect(
      find.descendant(of: find.byType(AppPopupCard), matching: find.text('서버에 연결하지 못했습니다.')),
      findsOneWidget,
      reason: '스크림 위(팝업 안)에 그려져야 한다',
    );
    expect(find.byType(SnackBar), findsNothing, reason: '스크림 아래로 가려질 자리에 띄우면 안 된다');
    // 팝업이 아직 열려 있는 상태여야 이 검사가 의미를 갖는다 — 팝업이
    // 닫혀 있었다면 토스트를 써도 가려지지 않는다.
    expect(find.text('출석코드 입력'), findsOneWidget, reason: '이 시점에 팝업은 열려 있다');
    expect(routes.stack, hasLength(2), reason: '스크림을 깐 팝업 라우트가 살아 있다');
    expect(find.text('다시 시도'), findsOneWidget);
  });

  testWidgets('예상 못 한 예외의 안내도 토스트가 아니라 팝업 안에 보인다', (tester) async {
    // 잡아야 할 잘못된 구현: `catch (_)` 분기만 토스트로 남겨 둔다. 이 경로는
    // `ApiException`이 아닌 예외(파싱 실패 등)에서만 도므로 어떤 테스트도
    // 지나가지 않았고, 실제로 이 분기만 되돌리는 변이가 살아남았다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
      ..results.add(Exception('파싱 실패'));
    final (container: _, :routes, visible: _) = await _pumpHome(
      tester,
      scanner: scanner,
      attendanceRepository: repo,
    );

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    await _enterOtp(tester, '1234');
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AppPopupCard),
        matching: find.text('출석 처리에 실패했습니다. 다시 시도해주세요.'),
      ),
      findsOneWidget,
      reason: '스크림 위(팝업 안)에 그려져야 한다',
    );
    expect(find.byType(SnackBar), findsNothing, reason: '스크림 아래로 가려질 자리에 띄우면 안 된다');
    // `routes.stack`만으로는 **어느** 팝업인지 알 수 없다 — 코드 팝업이 닫히고
    // 블루투스 팝업이 열린 구현도 통과한다(리뷰 Minor 3).
    expect(find.text('출석코드 입력'), findsOneWidget, reason: '코드 입력 팝업이 떠 있어야 한다');
    expect(routes.stack, hasLength(2), reason: '스크림을 깐 팝업 라우트가 살아 있다');
  });

  testWidgets('요청 중에 팝업이 닫히면 메시지를 토스트로 돌린다', (tester) async {
    // 잡아야 할 잘못된 구현: 메시지를 **항상** 팝업 안에 적는다. 요청이 도는
    // 사이에 범위를 벗어나면 `_codeConditionRaw`가 거짓이 돼 `_syncPopups`가
    // 팝업을 닫는데, 그러면 메시지가 죽은 `_CodeEntryState`로 들어가
    // **아무 데도 보이지 않는다** — 재시도 버튼도 그 팝업 안이라 함께
    // 사라진다. 수정 전(develop)에는 최소한 토스트라도 보였다(리뷰 Important 1).
    final scanner = FakeBeaconScanner();
    final gate = Completer<void>();
    // 종결성 오류를 쓴다 — 재시도 중단 경로(#45)와 섞이지 않게 해서 이
    // 테스트가 **표시 자리 선택만** 보게 한다.
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
      ..results.add(const ApiException(ErrorCode.sessionNotActive, '종료된 세션입니다.'))
      ..gate = gate;
    final (container: _, :routes, visible: _) = await _pumpHome(
      tester,
      scanner: scanner,
      attendanceRepository: repo,
    );

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    await _enterOtp(tester, '1234');
    await tester.pump();

    // 요청이 도는 사이에 범위를 벗어난다 — 팝업이 닫힌다.
    scanner.emit(const BeaconOutOfRange());
    await tester.pumpAndSettle();
    expect(find.text('출석코드 입력'), findsNothing, reason: '사전 조건: 팝업이 닫혔다');
    _expectNoLeftoverPopupRoute(routes);

    gate.complete();
    await tester.pumpAndSettle();

    expect(
      find.byType(SnackBar),
      findsOneWidget,
      reason: '팝업이 없으면 토스트가 유일하게 보이는 자리다',
    );
    expect(find.text('종료된 세션입니다.'), findsOneWidget);
  });

  testWidgets('재시도하면 이전 오류 메시지가 지워진다', (tester) async {
    // 잡아야 할 잘못된 구현: 재시도 시 `clearErrorMessage`를 빠뜨려, 새 시도가
    // 도는 동안 옛 실패 문구가 그대로 남는다.
    final scanner = FakeBeaconScanner();
    final gate = Completer<void>();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
      ..results.add(const ApiException(ErrorCode.network, '서버에 연결하지 못했습니다.'))
      ..results.add(const ApiException(ErrorCode.network, '서버에 연결하지 못했습니다.'));
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    await _enterOtp(tester, '1234');
    await tester.pumpAndSettle();
    expect(find.text('서버에 연결하지 못했습니다.'), findsOneWidget);

    // 다음 시도는 게이트로 붙잡아 "도는 중"에서 멈춘다.
    repo
      ..results.add(AttendanceStatus.present)
      ..gate = gate;
    await tester.tap(find.text('다시 시도'));
    await tester.pump();

    expect(
      find.text('서버에 연결하지 못했습니다.'),
      findsNothing,
      reason: '새 시도가 도는 동안 옛 실패 문구가 남아 있으면 안 된다',
    );

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('보이는 동안 이미 출석 처리된 세션이면 그 토스트도 실제로 뜬다', (tester) async {
    // `ALREADY_CHECKED_IN` 분기의 토스트 가드는 어떤 테스트도 지나가지
    // 않아, 가드를 풀어도 통째로 지워도 통과했다(리뷰 Important 3).
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
      ..results.add(const ApiException(ErrorCode.alreadyCheckedIn, '이미 출석했습니다.'));
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    await _enterOtp(tester, '1234');
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('이미 출석 처리되었습니다'), findsOneWidget);
  });

  testWidgets('앱이 백그라운드인 채 응답이 오면 완료 팝업 라우트를 쌓지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: 가드를 `_visible`이 아니라 `_tabVisible`로 둔다.
    // 탭은 그대로 선택돼 있는데 폰이 잠긴 경우가 정확히 그 상황이다 —
    // 모달이 그대로 push되고, 복귀하면 스크림 뒤에 갇힌다(리뷰 Important 2).
    //
    // **텍스트가 아니라 라우트 스택을 봐야 한다** — 백그라운드 상태에서는
    // 라우트가 스택에 있어도 `find.text`가 잡지 못한다(리뷰 확인).
    final scanner = FakeBeaconScanner();
    final gate = Completer<void>();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
      ..results.add(AttendanceStatus.present)
      ..gate = gate;
    final (container: _, :routes, visible: _) = await _pumpHome(
      tester,
      scanner: scanner,
      attendanceRepository: repo,
    );

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    await _enterOtp(tester, '1234');
    await tester.pump();

    // 탭은 그대로 둔 채 앱만 백그라운드로 보낸다.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    gate.complete();
    await tester.pumpAndSettle();

    _expectNoLeftoverPopupRoute(routes, reason: '탭이 아니라 앱이 가려진 경우에도 모달을 쌓으면 안 된다');
  });

  testWidgets('앱이 백그라운드인 채 응답이 오면 이미 출석 토스트도 띄우지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: 토스트 가드를 `_visible`이 아니라 `_tabVisible`로
    // 둔다. 탭은 선택돼 있는데 폰이 잠긴 경우를 놓친다(리뷰 Important 2).
    //
    // `ALREADY_CHECKED_IN`을 쓰는 이유: 실패 분기는 #42에서 토스트를 아예
    // 쓰지 않게 됐으므로, 그걸로는 토스트 가드를 검증할 수 없다.
    final scanner = FakeBeaconScanner();
    final gate = Completer<void>();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
      ..results.add(const ApiException(ErrorCode.alreadyCheckedIn, '이미 출석했습니다.'))
      ..gate = gate;
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    await _enterOtp(tester, '1234');
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    gate.complete();
    await tester.pumpAndSettle();

    // **백그라운드 상태에서 바로 검사하면 안 된다** — `paused`에서는 프레임이
    // 꺼져 있어 토스트를 띄웠더라도 `SnackBar`가 렌더되지 않고, 그러면 잘못된
    // 구현도 통과한다(실제로 `_tabVisible` 변이가 여기서 살아남았다).
    // 복귀시켜 큐에 들어간 토스트가 있으면 드러나게 한다.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('숨겨진 동안 이미 출석 처리된 세션이면 그 토스트도 띄우지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: `ALREADY_CHECKED_IN` 분기의 토스트만 가드를
    // 빠뜨린다. 이 분기의 숨김 경로는 어떤 테스트도 지나가지 않았다
    // (리뷰 Important 3).
    final scanner = FakeBeaconScanner();
    final gate = Completer<void>();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
      ..results.add(const ApiException(ErrorCode.alreadyCheckedIn, '이미 출석했습니다.'))
      ..gate = gate;
    final (container: _, routes: _, :visible) = await _pumpHome(
      tester,
      scanner: scanner,
      attendanceRepository: repo,
    );

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    await _enterOtp(tester, '1234');
    await tester.pump();

    visible.value = false;
    await tester.pumpAndSettle();

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('탭으로 돌아온 뒤 응답이 도착해도 인정된 출석을 잊지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: 응답 유효성을 `_bootstrapGeneration`으로 판정한다.
    // `_onBecameVisible()`이 새 부트스트랩을 시작하며 그 세대를 올리므로,
    // 제출 → 탭 이동 → **응답 전에 복귀**하면 클럽은 그대로인데 응답이 남의
    // 것으로 취급돼 통째로 버려진다. 그러면 서버가 인정한 출석을 잊고
    // 입력란이 다시 열려 중복 제출을 부른다(리뷰 Important 1).
    final scanner = FakeBeaconScanner();
    final gate = Completer<void>();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
      ..results.add(AttendanceStatus.present)
      ..gate = gate;
    final (container: _, routes: _, :visible) = await _pumpHome(
      tester,
      scanner: scanner,
      attendanceRepository: repo,
    );

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    await _enterOtp(tester, '1234');
    await tester.pump();

    // 응답이 오기 전에 나갔다가 **돌아온다**.
    visible.value = false;
    await tester.pumpAndSettle();
    visible.value = true;
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1)));
      await tester.pumpAndSettle();
    }

    gate.complete();
    await tester.pumpAndSettle();

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();

    expect(
      find.text('출석코드 입력'),
      findsNothing,
      reason: '서버가 인정한 출석을 잊으면 중복 제출을 부른다',
    );
    expect(repo.checkInArgs, hasLength(1));
  });

  testWidgets('잠깐 포커스를 잃은 것(inactive)만으로는 스캔도 입력도 잃지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: `inactive`를 백그라운드로 친다. `inactive`는
    // 제어센터·알림 그림자·시스템 다이얼로그처럼 **ranging이 멈추지 않는**
    // 순간에도 오고, 최초 실행의 권한 다이얼로그 자체도 이걸 유발한다.
    // 그때마다 스캔을 허물면 입력하던 네 자리가 사라지고 안정화를 처음부터
    // 다시 쌓아야 한다(리뷰 Important 2).
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession);
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    await _enterOtp(tester, '12'); // 네 자리 중 두 자리만 입력
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(scanner.stopCallCount, 0, reason: 'ranging이 멈추지 않는 구간이다');
    expect(scanner.watchCallCount, 1, reason: '스캔을 다시 걸 이유가 없다');
    expect(find.text('출석코드 입력'), findsOneWidget, reason: '팝업이 유지돼야 한다');
    final typed = find.byType(TextField).evaluate().map((e) {
      return (e.widget as TextField).controller!.text;
    }).join();
    expect(typed, '12', reason: '입력하던 자리가 사라지면 안 된다');
  });

  testWidgets('앱이 돌아오면 스캔을 다시 시작하고 감지 상태를 새로 쌓는다', (tester) async {
    // 잡아야 할 잘못된 구현: 백그라운드에서 멈추기만 하고 복귀 시 재개하지
    // 않는다 — 사용자가 앱을 다시 열어도 비콘을 영영 찾지 못한다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession);
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(find.text('비콘을 찾는 중입니다...'), findsOneWidget, reason: '감지 상태를 그대로 믿지 않는다');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1)));
      await tester.pumpAndSettle();
    }

    expect(scanner.watchCallCount, 2, reason: '복귀하면 스캔을 다시 시작해야 한다');
    // 재개 직후에는 아직 감지가 아니다 — 새 스트릭을 처음부터 쌓아야 한다.
    expect(find.text('출석코드 입력'), findsNothing);

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    expect(find.text('출석코드 입력'), findsOneWidget);
  });

  testWidgets('클럽이 바뀌면 세션 id가 같아도 출석 완료 래치가 풀린다', (tester) async {
    // 잡아야 할 잘못된 구현: `_resetClubScopedState`에서 래치 초기화를
    // 빠뜨린다. 세션 id는 클럽 단위로 매겨진다(`/clubs/{clubId}/sessions/
    // {sessionId}/attendance`이고 `ActiveSession`은 clubId를 담지 않는다)
    // — 두 클럽에 속한 부원이 클럽 7의 88번에 출석한 뒤 클럽 9로 바꿨을 때
    // 그쪽 활성 세션도 88번이면, 출석한 적 없는 세션에 대해 입력란이 막히고
    // 본문은 "출석이 완료되었습니다"라고 말한다(리뷰 Important 2).
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
      ..results.add(AttendanceStatus.present);
    final (:container, routes: _, visible: _) = await _pumpHome(
      tester,
      scanner: scanner,
      attendanceRepository: repo,
    );

    // 클럽 7의 세션 88에 출석한다.
    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    await _enterOtp(tester, '1234');
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    // 클럽 9로 바꾼다. 그쪽 활성 세션도 **우연히 id가 88**이다.
    (container.read(sessionControllerProvider.notifier) as _ReadySessionController).switchTo(
      _otherClubProfile,
    );
    // 클럽 전환은 `await _cancelBeaconSubscription()`을 지나가야 새 스캔이
    // 시작된다 — `fakeAsync`의 마이크로태스크 flush는 그 루트 존 future를
    // 진행시키지 않으므로 실제 이벤트 루프를 한 번 돌려준다.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1)));
      await tester.pumpAndSettle();
    }
    expect(scanner.watchCallCount, 2, reason: '새 클럽의 스캔이 실제로 다시 시작돼야 이 검사가 의미를 갖는다');

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();

    expect(
      find.text('출석코드 입력'),
      findsOneWidget,
      reason: '다른 클럽의 88번 세션에는 출석한 적이 없다',
    );
    expect(find.text('오늘 출석이 완료되었습니다'), findsNothing);
  });

  // ---------------------------------------------------------------------
  // 리뷰 Important 4 — 체크인에 동시 실행 배제가 없다.
  // ---------------------------------------------------------------------
  testWidgets('재시도 버튼을 리빌드 전에 두 번 눌러도 체크인 요청은 하나만 더 나간다', (tester) async {
    // 잡아야 할 잘못된 구현: `_submitCode`가 `submitting`을 조기 반환
    // 조건으로 쓰지 않는다 — 버튼이 화면에서 사라지기 전(다음 리빌드 전)에
    // 들어온 두 번째 탭이 그대로 두 번째 요청이 된다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession);
    // 첫 제출은 자동 재시도(정확히 한 번)까지 모두 실패해 CheckInFailed로
    // 확정된다 → 수동 재시도 버튼이 노출된다.
    repo.results.addAll([
      const ApiException(ErrorCode.unknown, '일시적인 오류'),
      const ApiException(ErrorCode.unknown, '일시적인 오류'),
    ]);
    repo.fallbackResult = AttendanceStatus.present;
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    await _enterOtp(tester, '1234');
    await tester.pumpAndSettle();

    expect(find.text('다시 시도'), findsOneWidget);
    expect(repo.checkInArgs, hasLength(2));

    // 다음 요청을 붙잡아 두어 "진행 중" 상태를 유지한다.
    final gate = Completer<void>();
    repo.gate = gate;

    // 리빌드 없이 연속 두 번 탭한다(tester.tap은 pump하지 않는다).
    await tester.tap(find.text('다시 시도'));
    await tester.tap(find.text('다시 시도'));
    await tester.pump();

    expect(
      repo.checkInArgs,
      hasLength(3),
      reason: '두 번째 탭은 이미 진행 중인 요청 때문에 무시돼야 한다',
    );

    gate.complete();
    repo.gate = null;
    await tester.pumpAndSettle();
  });

  testWidgets('실패 뒤 새 코드를 입력하면 재시도 버튼이 즉시 사라진다', (tester) async {
    // 잡아야 할 잘못된 구현: `_submitCode`가 `needsManualRetry`를 지우지
    // 않는다 — 새 요청이 도는 동안에도 버튼이 남아 있고, 그 버튼은 방금
    // 새로 대입된 `_lastOtpCode`를 다시 쏘아 올려 동시 제출이 된다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession);
    repo.results.addAll([
      const ApiException(ErrorCode.unknown, '일시적인 오류'),
      const ApiException(ErrorCode.unknown, '일시적인 오류'),
    ]);
    repo.fallbackResult = AttendanceStatus.present;
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    await _enterOtp(tester, '1234');
    await tester.pumpAndSettle();
    expect(find.text('다시 시도'), findsOneWidget);

    final gate = Completer<void>();
    repo.gate = gate;

    // 네 칸이 이미 차 있으므로 한 칸만 고쳐도 완료 판정이 다시 일어난다.
    await tester.enterText(find.byType(TextField).first, '5');
    await tester.pump();

    expect(
      find.text('다시 시도'),
      findsNothing,
      reason: '새 요청이 진행되는 동안 재시도 버튼이 남아 있으면 동시 제출로 이어진다',
    );

    gate.complete();
    repo.gate = null;
    await tester.pumpAndSettle();
  });

  testWidgets('ApiException이 아닌 예외가 새어 나와도 입력란이 잠기지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: `_submitCode`가 `submit()`을 try 없이 await
    // 한다 — `AttendanceController`가 접지 못하는 예외(파싱 실패 등)가
    // 그대로 새면 `submitting`이 true로 굳어 입력란이 영구히 비활성화되고,
    // `unawaited` 호출이라 처리되지 않은 비동기 오류가 된다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
      ..results.add(const FormatException('응답을 해석할 수 없습니다'));
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    await _enterOtp(tester, '1234');
    await tester.pumpAndSettle();

    expect(find.text('다시 시도'), findsOneWidget, reason: '실패로 확정하고 수동 재시도를 열어야 한다');
    for (final element in find.byType(TextField).evaluate()) {
      expect(
        (element.widget as TextField).enabled,
        isTrue,
        reason: 'submitting이 풀리지 않으면 네 칸이 영구히 비활성화된다',
      );
    }
  });

  testWidgets('코드 입력 팝업이 다시 열리면 이전 실패의 재시도 버튼이 남지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: `_codeEntryState`가 팝업 수명과 무관하게
    // 살아 있어, 범위를 벗어났다 돌아오면 옛 실패의 재시도 버튼이 그대로
    // 붙어 있고 그 버튼이 옛 코드를 다시 제출한다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession);
    repo.results.addAll([
      const ApiException(ErrorCode.unknown, '일시적인 오류'),
      const ApiException(ErrorCode.unknown, '일시적인 오류'),
    ]);
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    await _enterOtp(tester, '1234');
    await tester.pumpAndSettle();
    expect(find.text('다시 시도'), findsOneWidget);

    scanner.emit(const BeaconOutOfRange());
    await tester.pumpAndSettle();
    scanner.emit(const BeaconDetected(-55));
    await tester.pumpAndSettle();

    expect(find.byType(AppOtpInput), findsOneWidget);
    expect(find.text('다시 시도'), findsNothing);
    // 이 픽스처가 실제로 만드는 문구를 검사해야 한다. 원래는 오답 문구
    // ('비밀번호가 올바르지 않습니다')를 검사했는데, `ErrorCode.unknown`은
    // 그 문구를 만들지 않으므로 **이 단언은 늘 참이었다** — 팝업 재개방 시
    // 오류 문구 초기화를 지워도 통과했다(리뷰 Minor 1).
    expect(
      find.text('일시적인 오류'),
      findsNothing,
      reason: '다시 열린 팝업이 이전 시도의 오류 문구를 끌고 오면 안 된다',
    );
  });

  // ---------------------------------------------------------------------
  // 리뷰 Important 5 — dispose 이후에 스캔이 다시 시작될 수 있다.
  // ---------------------------------------------------------------------
  testWidgets('구독 취소를 기다리는 동안 dispose되면 새 스캔을 시작하지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: `_startBeaconScan`이 `mounted`를
    // `await sub.cancel()` **앞에서만** 검사한다 — 그 await 중에 dispose가
    // 일어나면 `dispose()`가 `stop()`을 부른 뒤 continuation이 `watch()`로
    // 새 스캔을 만든다. 콜백은 무시되지만 그 스캔을 멈출 주체가 아무도 없다.
    final cancelGate = Completer<void>();
    final scanner = _SlowCancelBeaconScanner(cancelGate);
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession);
    final container = ProviderContainer(
      overrides: [
        sessionControllerProvider.overrideWith(() => _ReadySessionController(_profile)),
        beaconScannerProvider.overrideWithValue(scanner),
        beaconConfigRepositoryProvider.overrideWithValue(_FakeBeaconConfigRepository()),
        attendanceRepositoryProvider.overrideWithValue(repo),
        recordsRepositoryProvider.overrideWithValue(_RecordingRecordsRepository()),
      ],
    );
    addTearDown(container.dispose);

    final hostKey = GlobalKey<_ToggleHomeState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: _ToggleHome(key: hostKey, child: const HomeScreen())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(scanner.watchCallCount, 1);

    // 클럽이 바뀌어 스캔이 다시 시작된다 — 그 과정의 구독 취소가
    // cancelGate에 막힌다.
    (container.read(sessionControllerProvider.notifier) as _ReadySessionController).switchTo(
      _otherClubProfile,
    );
    await tester.pumpAndSettle();
    expect(scanner.watchCallCount, 1, reason: '취소가 아직 안 끝나 watch()에 도달하지 못했다');

    // 취소를 기다리는 그 창에서 화면이 사라진다.
    hostKey.currentState!.hide();
    await tester.pumpAndSettle();
    expect(scanner.stopCallCount, greaterThanOrEqualTo(1));

    cancelGate.complete();
    // `cancel()`이 돌려주는 Future의 연속은 루트 존 마이크로태스크라
    // fakeAsync의 플러시로는 이어지지 않는다 — 실기기와 같은 조건을 주기
    // 위해 실제 이벤트 루프를 한 바퀴 돌린다(그러지 않으면 이 테스트는
    // 가드가 없어도 통과한다).
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(
      scanner.watchCallCount,
      1,
      reason: 'dispose()가 stop()을 이미 부른 뒤에 시작된 스캔은 멈출 주체가 아무도 없다',
    );
  });

  // ---------------------------------------------------------------------
  // 리뷰 Important 6 — 완료 팝업이 홈의 생명주기에 묶여 있지 않다.
  // ---------------------------------------------------------------------
  testWidgets('출석완료 팝업이 떠 있는 상태에서 홈이 트리에서 빠지면 완료 팝업도 닫힌다', (tester) async {
    // 잡아야 할 잘못된 구현: `_shownPopup`이 코드·블루투스 팝업만 추적한다.
    // 완료 팝업을 띄우는 시점엔 이미 `none`이라 `dispose()`가 그것을 닫지
    // 못하고, 완료 팝업이 다음 화면 위에 그대로 남는다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession)
      ..results.add(AttendanceStatus.present);
    final container = ProviderContainer(
      overrides: [
        sessionControllerProvider.overrideWith(() => _ReadySessionController(_profile)),
        beaconScannerProvider.overrideWithValue(scanner),
        beaconConfigRepositoryProvider.overrideWithValue(_FakeBeaconConfigRepository()),
        attendanceRepositoryProvider.overrideWithValue(repo),
        recordsRepositoryProvider.overrideWithValue(_RecordingRecordsRepository()),
      ],
    );
    addTearDown(container.dispose);

    final routes = _RouteStackObserver();
    final hostKey = GlobalKey<_ToggleHomeState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          navigatorObservers: [routes],
          home: Scaffold(body: _ToggleHome(key: hostKey, child: const HomeScreen())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    await _enterOtp(tester, '1234');
    await tester.pumpAndSettle();
    expect(find.text('출석 완료!'), findsOneWidget);

    hostKey.currentState!.hide();
    await tester.pumpAndSettle();

    expect(find.text('출석 완료!'), findsNothing);
    _expectNoLeftoverPopupRoute(routes);
  });

  // 조정자 지시(2차) — 블루투스 꺼짐과 코드 입력 조건이 동시에 참이면
  // 블루투스가 이겨야 한다("죽은 라디오 위에서 코드 입력을 받는 건
  // 의미가 없다"). `BeaconScanState`가 sealed class라 오늘은 두 조건이
  // 실제로 동시에 참일 수 없어(위젯 테스트로는 이 우선순위를 직접 재현할
  // 수 없다) 상태 계산과 분리된 순수 함수로 뽑아 여기서 직접 검증한다.
  test('resolveHomePopupTarget: 블루투스 꺼짐과 코드 입력 조건이 동시에 참이면 블루투스가 이긴다', () {
    // 잡아야 할 잘못된 구현: 코드 입력 조건을 블루투스보다 먼저 검사해
    // (코드 입력이 우선하게) 만든다.
    final target = resolveHomePopupTarget(bluetoothOff: true, codeConditionRaw: true);

    expect(target, HomePopupTarget.bluetoothOff);
  });
}
