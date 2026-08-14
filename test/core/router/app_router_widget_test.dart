import 'package:beacon_app/components/nav/app_top_bar.dart';
import 'package:beacon_app/core/network/dio_provider.dart';
import 'package:beacon_app/core/router/app_router.dart';
import 'package:beacon_app/core/storage/token_store.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:beacon_app/features/attendance/data/attendance_dto.dart';
import 'package:beacon_app/features/attendance/data/attendance_repository.dart';
import 'package:beacon_app/features/attendance/presentation/home_screen.dart';
import 'package:beacon_app/features/auth/data/auth_dto.dart';
import 'package:beacon_app/features/auth/data/auth_repository.dart';
import 'package:beacon_app/features/auth/presentation/login_screen.dart';
import 'package:beacon_app/features/auth/presentation/signup_screen.dart';
import 'package:beacon_app/features/beacon/data/beacon_config_dto.dart';
import 'package:beacon_app/features/beacon/data/beacon_config_repository.dart';
import 'package:beacon_app/features/beacon/data/fake_beacon_scanner.dart';
import 'package:beacon_app/features/beacon/data/flutter_beacon_scanner.dart';
import 'package:beacon_app/features/beacon/domain/beacon_scanner.dart';
import 'package:beacon_app/features/club/presentation/invite_code_screen.dart';
import 'package:beacon_app/features/records/data/records_dto.dart';
import 'package:beacon_app/features/records/data/records_repository.dart';
import 'package:beacon_app/features/records/presentation/records_calendar.dart';
import 'package:beacon_app/features/records/presentation/records_screen.dart';
import 'package:beacon_app/features/records/presentation/session_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// `/home`이 이제 실제 `HomeScreen`이라 이 파일의 여러 테스트가 그 화면을
/// (탭 전환 등을 통해) 잠깐이라도 빌드한다. `HomeScreen`은 비콘 스캐너·
/// 비콘 설정·활성 세션·기록 리포지토리를 곧장 두드리므로, 이 테스트들이
/// 검증하려는 건 라우팅이지 그 화면의 동작이 아니다 — 실제 네트워크/플랫폼
/// 채널을 두드리지 않도록 아무 일도 하지 않는 페이크로 전부 막아 둔다.
class _NoopBeaconConfigRepository implements BeaconConfigRepository {
  @override
  Future<BeaconConfig> fetch(int clubId) async => const BeaconConfig(
    uuid: 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0',
    lateThresholdMinutes: 10,
    rssiStabilizationSeconds: 3,
    rssiThreshold: -70,
  );
}

class _NoopAttendanceRepository implements AttendanceRepository {
  @override
  Future<ActiveSession?> fetchActiveSession(int clubId) async => null;

  @override
  Future<AttendanceStatus> checkIn({
    required int clubId,
    required int sessionId,
    required String otpCode,
  }) {
    throw UnimplementedError('이 테스트 스위트는 출석 체크를 수행하지 않는다');
  }
}

class _NoopRecordsRepository implements RecordsRepository {
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
      present: 0,
      absent: 0,
      late: 0,
      etc: 0,
      attendanceRate: 0,
    );
  }
}

/// [_pumpRealRouter]와 `showAdmin` 리다이렉트 테스트가 공통으로 쓰는
/// `HomeScreen` 관련 override 4종. [scanner]/[attendanceRepository]를
/// 넘기면 그 인스턴스를 그대로 쓴다 — 팝업(블루투스 꺼짐/출석코드 입력/
/// 출석완료)이 하단 탭 셸을 실제로 덮는지 검증하는 테스트들이 비콘 상태를
/// 직접 조작하고 체크인 결과를 스크립트할 수 있어야 하기 때문이다.
List<Override> _homeScreenOverrides({
  BeaconScanner? scanner,
  AttendanceRepository? attendanceRepository,
  RecordsRepository? recordsRepository,
}) => [
  beaconScannerProvider.overrideWithValue(scanner ?? FakeBeaconScanner()),
  beaconConfigRepositoryProvider.overrideWithValue(_NoopBeaconConfigRepository()),
  attendanceRepositoryProvider.overrideWithValue(attendanceRepository ?? _NoopAttendanceRepository()),
  recordsRepositoryProvider.overrideWithValue(recordsRepository ?? _NoopRecordsRepository()),
];

/// 조회 호출을 세고, 기록이 **있는** 달을 돌려주는 페이크 — 기록 탭이
/// 숨어 있는 동안 조회를 날리지 않는지, 그리고 날짜 상세 시트가 탭을
/// 떠날 때 함께 닫히는지 검증하는 테스트가 쓴다.
class _CountingRecordsRepository implements RecordsRepository {
  int fetchCount = 0;

  @override
  Future<MonthlyRecords> fetch({
    required int clubId,
    required int year,
    required int month,
  }) async {
    fetchCount++;
    return MonthlyRecords(
      year: year,
      month: month,
      records: [
        AttendanceRecordItem(
          sessionId: 1,
          sessionName: '정기모임',
          // 어느 달이든 1일에는 기록이 있다 — 테스트가 탭할 날짜다.
          date: DateTime(year, month),
          status: AttendanceStatus.present,
        ),
      ],
      present: 1,
      absent: 0,
      late: 0,
      etc: 0,
      attendanceRate: 100,
    );
  }
}

/// 활성 세션을 항상 돌려주고, checkIn 호출은 [status]로 확정하는 페이크
/// — 완료 팝업이 하단 탭 셸을 덮는지 검증하는 테스트가 실제로 체크인
/// 흐름을 끝까지 태우기 위해 쓴다.
class _ActiveSessionAttendanceRepository implements AttendanceRepository {
  _ActiveSessionAttendanceRepository({required this.status});

  final AttendanceStatus status;

  @override
  Future<ActiveSession?> fetchActiveSession(int clubId) async =>
      const ActiveSession(sessionId: 88, sessionName: '정기모임', status: 'ACTIVE');

  @override
  Future<AttendanceStatus> checkIn({
    required int clubId,
    required int sessionId,
    required String otpCode,
  }) async => status;
}

/// `app_router_test.dart`는 `computeRedirect`가 문자열 `"/invite"`를
/// 돌려주는지만 확인하는 순수 함수 테스트다 — 그 문자열이 실제로 어떤
/// 화면과 연결돼 있는지는 전혀 검증하지 않는다. `GoRoute`가 라우트 배열에서
/// 통째로 빠지거나 다른 화면을 가리키게 바뀌어도 그 테스트들은 계속
/// 초록색이다. 이 파일은 실제 `appRouterProvider`(진짜 GoRouter)를 마운트해
/// 각 경로가 정말 그 화면을 렌더링하는지 확인한다.
///
/// 예전에는 `/invite` 하나만 이렇게 검증했다 — `/home`, `/login`, `/signup`
/// 은 `GoRoute`를 지워도 115개 테스트가 전부 통과했다.
class _ProfileAuthRepository implements AuthRepository {
  _ProfileAuthRepository(this.clubIds);

  final List<int> clubIds;

  @override
  Future<TokenResponse> login({required String stdId, required String password}) async =>
      const TokenResponse(accessToken: 'a', refreshToken: 'r');

  @override
  Future<void> signup({
    required String stdId,
    required String password,
    required String name,
  }) async {}

  @override
  Future<TokenResponse> refresh(String refreshToken) async =>
      const TokenResponse(accessToken: 'a', refreshToken: 'r');

  @override
  Future<void> logout() async {}

  @override
  Future<MemberProfile> fetchMe() async => MemberProfile(
        name: '김민준',
        stdId: '20250101',
        clubIds: clubIds,
        pushEnabled: true,
      );
}

/// 실제 `appRouterProvider`를 마운트하고 최초 리다이렉트가 끝날 때까지
/// 진행시킨다. [clubIds]가 null이면 저장된 토큰이 없는 상태(=SignedOut)를
/// 재현한다. [showAdmin]은 `showAdminTabProvider`를 override한다 — 기본값
/// false는 실제 앱과 동일하고, true는 관리자 탭·라우트 자체의 배선을
/// (가드와 분리해) 검증할 때 쓴다.
///
/// `container`도 함께 돌려주는 이유: `showAdminTabProvider`를 나중에
/// `container.updateOverrides(...)`로 바꿔치기해, 아무 내비게이션도 하지
/// 않았는데 provider 값만 바뀌었을 때 redirect가 스스로 재평가되는지
/// 검증하는 테스트가 있기 때문이다.
Future<({GoRouter router, ProviderContainer container})> _pumpRealRouter(
  WidgetTester tester, {
  List<int>? clubIds,
  bool showAdmin = false,
  BeaconScanner? scanner,
  AttendanceRepository? attendanceRepository,
  RecordsRepository? recordsRepository,
}) async {
  final store = InMemoryTokenStore();
  if (clubIds != null) await store.save(accessToken: 'a', refreshToken: 'r');

  final container = ProviderContainer(
    overrides: [
      tokenStoreProvider.overrideWithValue(store),
      authRepositoryProvider.overrideWithValue(_ProfileAuthRepository(clubIds ?? const [])),
      showAdminTabProvider.overrideWithValue(showAdmin),
      ..._homeScreenOverrides(
        scanner: scanner,
        attendanceRepository: attendanceRepository,
        recordsRepository: recordsRepository,
      ),
    ],
  );
  addTearDown(container.dispose);

  final router = container.read(appRouterProvider);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
    ),
  );

  // 세션 판별(비동기 refresh + fetchMe)이 끝나도록 한 박자 흘려보낸다.
  await tester.pump();
  await tester.pump();

  // computeRedirect의 최소 스플래시 노출 시간(1.5초) 판정은 시뮬레이션
  // 시계가 아니라 진짜 DateTime.now()를 쓴다 — tester.pump(duration)은
  // Timer만 진행시킬 뿐 실제 시간은 흐르지 않으므로, runAsync로 진짜 1.6초를
  // 흘려보내야 그 판정을 통과할 수 있다. 그런 다음 pump(duration)으로
  // _SessionListenable의 `Timer(minSplashDuration, notifyListeners)`를 실제로
  // 발화시켜 go_router가 redirect를 다시 평가하게 만든다.
  await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 1600)));
  await tester.pump(const Duration(milliseconds: 1600));
  await tester.pumpAndSettle();

  return (router: router, container: container);
}

void main() {
  testWidgets(
    '실제 appRouterProvider는 clubIds가 비어 있으면 /invite로 이동해 InviteCodeScreen을 렌더링한다',
    (tester) async {
      await _pumpRealRouter(tester, clubIds: const []);

      // `/invite` GoRoute가 라우트 트리에서 빠지거나 다른 화면을 가리키면
      // 여기서 InviteCodeScreen을 찾지 못해 이 expect가 실패한다 — 실제로
      // GoRoute를 지워서 확인했다: go_router가 예외를 던지지는 않고,
      // computeRedirect가 여전히 가리키는 "/invite" 경로에 매칭되는 화면이
      // 없으니 InviteCodeScreen이 그냥 렌더링되지 않는다(찾은 위젯 수 0).
      expect(find.byType(InviteCodeScreen), findsOneWidget);
    },
  );

  testWidgets('동아리가 있으면 /home으로 이동해 홈 화면을 렌더링한다', (tester) async {
    await _pumpRealRouter(tester, clubIds: const [7]);

    // `/home` GoRoute가 없거나 다른 화면을 가리키면 이 expect가 실패한다.
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  // 조정자 지시(2차) — 출석코드 입력·블루투스 꺼짐 팝업이 홈 화면 안의
  // `Positioned.fill` 오버레이였을 때는 그 스크림이 홈 화면(하단 탭 셸의
  // 중첩 네비게이터 안) 안에서만 그려져, `AppShell`의 상단 바·하단 탭
  // 바는 그대로 보이고 탭도 눌렸다. 지금은 `showAppPopup`이 항상
  // `useRootNavigator: true`로 다이얼로그를 띄우므로, 그 위로 상단
  // 바·하단 탭 바가 덮여야 한다 — `home_screen_test.dart`의 `_pumpHome`은
  // `AppShell` 자체가 없는 얇은 하네스라 이 회귀를 볼 수 없고, 실제
  // `appRouterProvider`(=진짜 `AppShell`)를 마운트하는 이 파일에서만
  // 검증할 수 있다.
  testWidgets('블루투스 꺼짐 팝업의 스크림이 하단 탭 셸을 덮어 탭이 눌리지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: 팝업을 다시 홈 화면 안 Positioned.fill로
    // 만들거나, 다이얼로그를 루트가 아닌 중첩 네비게이터에 붙인다 —
    // 어느 쪽이든 하단 탭 바가 그대로 눌린다.
    final scanner = FakeBeaconScanner();
    final (router: _, container: _) = await _pumpRealRouter(
      tester,
      clubIds: const [7],
      scanner: scanner,
    );

    scanner.emit(const BeaconBluetoothOff());
    await tester.pumpAndSettle();
    expect(find.text('블루투스가 꺼져 있어요'), findsOneWidget);

    // 하단 탭 바의 "기록" 탭을 눌러본다. 스크림이 탭 바를 실제로 덮고
    // 있다면 이 탭은 모달 배리어에 흡수돼 아무 효과가 없어야 한다.
    // warnIfMissed: false — 탭이 실제로 "기록" 위젯에 닿지 못하는 것 자체가
    // 이 테스트가 확인하려는 바다.
    await tester.tap(find.text('기록'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(
      find.byType(HomeScreen),
      findsOneWidget,
      reason: '탭이 실제로 눌렸다면 기록 화면으로 넘어갔을 것이다',
    );
    expect(find.byType(RecordsScreen), findsNothing);
    // 팝업도 여전히 떠 있어야 한다 — 탭이 무시된 것이지 팝업이 어쩌다
    // 닫힌 게 아니다.
    expect(find.text('블루투스가 꺼져 있어요'), findsOneWidget);
  });

  testWidgets('출석코드 입력 팝업의 스크림도 하단 탭 셸을 덮어 탭이 눌리지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: 위와 같은 원인 — 팝업이 중첩 네비게이터
    // 아래에 갇힌다.
    final scanner = FakeBeaconScanner();
    final repo = _ActiveSessionAttendanceRepository(status: AttendanceStatus.present);
    final (router: _, container: _) = await _pumpRealRouter(
      tester,
      clubIds: const [7],
      scanner: scanner,
      attendanceRepository: repo,
    );

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    expect(find.text('출석코드 입력'), findsOneWidget);

    await tester.tap(find.text('기록'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(RecordsScreen), findsNothing);
    expect(find.text('출석코드 입력'), findsOneWidget);
  });

  // 조정자가 명시적으로 요청한 검증 — 출석완료 팝업(`showAttendanceSuccessSheet`
  // → `showAppPopup`)은 최초 재작업 때부터 이미 다이얼로그 라우트였으니
  // `useRootNavigator`가 기본값(true)만으로 이미 셸을 덮고 있었어야 한다.
  // 프로즈로 "이미 됐을 것"이라 추측하지 않고 실제로 체크인까지 끝까지
  // 태워 확인한다.
  testWidgets('출석완료 팝업의 스크림도 하단 탭 셸을 덮어 탭이 눌리지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: showAppPopup이 useRootNavigator를 명시하지
    // 않아(또는 false로) 중첩 네비게이터에 갇힌다.
    final scanner = FakeBeaconScanner();
    final repo = _ActiveSessionAttendanceRepository(status: AttendanceStatus.present);
    final (router: _, container: _) = await _pumpRealRouter(
      tester,
      clubIds: const [7],
      scanner: scanner,
      attendanceRepository: repo,
    );

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    expect(find.text('출석코드 입력'), findsOneWidget);

    final fields = find.byType(TextField);
    for (var i = 0; i < 4; i++) {
      await tester.enterText(fields.at(i), '1');
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('출석 완료!'), findsOneWidget);

    await tester.tap(find.text('기록'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(RecordsScreen), findsNothing);
    expect(find.text('출석 완료!'), findsOneWidget);
  });

  // ---------------------------------------------------------------------
  // 리뷰 Important 3 — 홈 탭을 떠나도 스캔이 계속되고, 다른 탭 위로 팝업이
  // 뜬다.
  //
  // `StatefulShellRoute.indexedStack`은 숨은 브랜치를 dispose하지 않는다
  // (`Offstage` + `TickerMode(enabled: false)`로 감싼 채 살려 둔다) —
  // 그래서 `HomeScreen.dispose()`의 정리 로직은 탭 전환으로는 **아예 실행되지
  // 않는다**. 이 사실은 얇은 하네스(`home_screen_test.dart`의 `_pumpHome`)로는
  // 볼 수 없고, 진짜 셸을 마운트하는 이 파일에서만 검증할 수 있다.
  // ---------------------------------------------------------------------
  testWidgets('홈 탭을 떠나면 BLE 스캔이 멈추고, 돌아오면 다시 시작된다', (tester) async {
    // 잡아야 할 잘못된 구현: 정리를 `dispose()`에만 둔다 — 탭 전환으로는
    // dispose가 불리지 않으므로 숨은 홈이 계속 BLE를 돌린다(배터리).
    final scanner = FakeBeaconScanner();
    await _pumpRealRouter(tester, clubIds: const [7], scanner: scanner);

    expect(scanner.watchCallCount, 1);
    expect(scanner.stopCallCount, 0);

    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();
    expect(find.byType(RecordsScreen), findsOneWidget);

    expect(
      scanner.stopCallCount,
      greaterThanOrEqualTo(1),
      reason: '홈 탭이 보이지 않는 동안 BLE 스캔이 계속 돌 이유가 없다',
    );

    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();

    expect(
      scanner.watchCallCount,
      2,
      reason: '다시 보이면 스캔을 재개해야 한다 — 새 watch()라 안정화 스트릭도 0에서 다시 쌓인다',
    );
  });

  testWidgets('숨은 홈 화면은 기록 탭 위로 출석코드 팝업을 띄우지 않는다', (tester) async {
    // 잡아야 할 잘못된 구현: 숨은 홈이 비콘 스트림을 계속 구독한 채로
    // 있다가 범위 안에 들어오는 순간 루트 내비게이터에 코드 입력
    // 다이얼로그를 밀어 넣는다 — 사용자는 기록 화면을 보고 있는데 출석
    // 코드 팝업이 튀어나온다.
    final scanner = FakeBeaconScanner();
    final repo = _ActiveSessionAttendanceRepository(status: AttendanceStatus.present);
    await _pumpRealRouter(
      tester,
      clubIds: const [7],
      scanner: scanner,
      attendanceRepository: repo,
    );

    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();
    expect(find.byType(RecordsScreen), findsOneWidget);

    // 기록 탭을 보는 동안 사용자가 비콘 범위 안으로 들어왔다.
    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();

    expect(find.text('출석코드 입력'), findsNothing);
    expect(find.byType(RecordsScreen), findsOneWidget);
  });

  testWidgets('코드 입력 팝업이 떠 있는 채로 홈 탭을 떠나면 팝업도 함께 닫힌다', (tester) async {
    // 잡아야 할 잘못된 구현: 팝업 정리를 `dispose()`에만 둔다 — 탭 전환은
    // dispose를 부르지 않으므로, 루트 내비게이터에 붙은 팝업이 기록 화면
    // 위에 그대로 남아 앱을 막는다.
    final scanner = FakeBeaconScanner();
    final repo = _ActiveSessionAttendanceRepository(status: AttendanceStatus.present);
    final (:router, container: _) = await _pumpRealRouter(
      tester,
      clubIds: const [7],
      scanner: scanner,
      attendanceRepository: repo,
    );

    scanner.emit(const BeaconDetected(-60));
    await tester.pumpAndSettle();
    expect(find.text('출석코드 입력'), findsOneWidget);

    // 팝업의 스크림이 하단 탭 바를 덮고 있어 탭으로는 이동할 수 없다
    // (그건 별도 테스트가 고정한다) — 라우터로 직접 이동한다.
    router.go(AppRoutes.records);
    await tester.pumpAndSettle();

    expect(find.text('출석코드 입력'), findsNothing);
    expect(find.byType(RecordsScreen), findsOneWidget);
  });

  // ---------------------------------------------------------------------
  // 기록 탭도 홈 탭과 같은 가시성 함정 위에 있다(#12).
  //
  // `StatefulShellRoute.indexedStack`은 숨은 브랜치를 dispose하지 않고 계속
  // build한다 — 그래서 기록 화면도 (1) 숨은 채로 첫 조회를 날릴 수 있고,
  // (2) 자기가 띄운 바텀시트를 다른 탭 위에 남길 수 있다. 이 두 가지는
  // 얇은 하네스(`records_screen_test.dart`)로는 볼 수 없다 — 진짜 셸이
  // 있어야 `TickerMode`가 실제로 꺼진다.
  // ---------------------------------------------------------------------
  testWidgets('기록 탭을 떠났다 돌아오면 그 달을 다시 조회한다', (tester) async {
    // 잡아야 할 잘못된 구현: 최초 1회만 조회하고 끝낸다 — 홈에서 출석
    // 체크를 하고 기록 탭으로 넘어와도 요약 숫자와 배지가 옛것 그대로다.
    // (탭 전환으로는 dispose/initState가 불리지 않으므로 "다시 마운트되니까
    // 알아서 새로 받겠지"가 성립하지 않는다.)
    final records = _CountingRecordsRepository();
    await _pumpRealRouter(tester, clubIds: const [7], recordsRepository: records);

    // 홈 화면도 요약 카드용으로 이 리포지토리를 한 번 두드린다 — 기록 탭의
    // 조회만 세려면 그 시점의 값을 기준으로 잡아야 한다.
    final afterHomeBootstrap = records.fetchCount;

    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();
    expect(records.fetchCount, afterHomeBootstrap + 1, reason: '기록 탭이 처음 보일 때 조회한다');

    await tester.tap(find.text('마이'));
    await tester.pumpAndSettle();
    final afterLeaving = records.fetchCount;

    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();

    expect(records.fetchCount, afterLeaving + 1, reason: '다시 보이면 지금 보고 있는 달을 새로 조회해야 한다');
  });

  testWidgets('날짜 상세 시트가 떠 있는 채로 기록 탭을 떠나면 시트도 함께 닫힌다', (tester) async {
    // 잡아야 할 잘못된 구현: 시트를 `showModalBottomSheet`로만 띄우고 라우트를
    // 소유하지 않는다 — 탭 전환은 dispose를 부르지 않으므로 루트 내비게이터에
    // 붙은 시트가 홈 화면 위에 그대로 남아 앱을 막는다.
    final records = _CountingRecordsRepository();
    final (:router, container: _) = await _pumpRealRouter(
      tester,
      clubIds: const [7],
      recordsRepository: records,
    );

    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(of: find.byType(RecordsCalendar), matching: find.text('1')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SessionDetailSheetContent), findsOneWidget);

    // 시트의 스크림이 하단 탭 바를 덮고 있어 탭으로는 이동할 수 없다 —
    // 라우터로 직접 이동한다(코드 입력 팝업 테스트와 같은 이유).
    router.go(AppRoutes.home);
    await tester.pumpAndSettle();

    expect(find.byType(SessionDetailSheetContent), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  // Figma 실측(339:1498/326:1569 "상단 메뉴")에서 드러난 사실 — 홈 탭의
  // 상단 바는 고정 문구 "홈"이 아니라 로그인한 멤버의 이름을 보여준다.
  testWidgets('홈 탭의 상단 바는 고정 문구 대신 멤버 이름을 보여준다', (tester) async {
    // 잡아야 할 잘못된 구현: AppShell이 모든 탭에 고정 문구를 쓰던 기존
    // 방식대로 홈 탭에도 "홈"을 그대로 보여준다.
    await _pumpRealRouter(tester, clubIds: const [7]);

    // 하단 탭 라벨("홈")은 AppBottomNav가 항상 그리므로 그와 무관하게
    // 상단 바 제목만 확인한다 — AppTopBar 서브트리 안에서 찾는다.
    final topBarTitle = find.descendant(
      of: find.byType(AppTopBar),
      matching: find.text('김민준'),
    );
    expect(topBarTitle, findsOneWidget);
  });

  testWidgets('저장된 토큰이 없으면 /login으로 이동해 LoginScreen을 렌더링한다', (tester) async {
    await _pumpRealRouter(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('로그인 화면에서 회원가입을 누르면 /signup의 SignupScreen이 렌더링된다', (tester) async {
    await _pumpRealRouter(tester);
    expect(find.byType(LoginScreen), findsOneWidget);

    // 화면이 실제로 쓰는 경로(context.push(AppRoutes.signup))를 그대로 탄다.
    await tester.tap(find.text('회원가입'));
    await tester.pumpAndSettle();

    expect(find.byType(SignupScreen), findsOneWidget);
  });

  testWidgets('하단 탭 4개의 경로가 각각 올바른 화면을 렌더한다', (tester) async {
    // showAdmin: true로 관리자 라우트 가드를 우회해, 4개 브랜치 전부가
    // 실제로 올바른 화면과 연결돼 있는지를 가드와 분리해서 검증한다.
    // 가드 자체(showAdmin:false일 때 /admin이 막히는지)는 별도 테스트가
    // 다룬다. computeRedirect가 문자열을 반환하는지만 보는 것으로는
    // GoRoute가 트리에서 빠지거나 다른 화면을 가리키는 실수를 잡지 못한다
    // — 실제로 각 경로를 방문해 화면 텍스트를 찾는다.
    final (:router, container: _) = await _pumpRealRouter(
      tester,
      clubIds: const [7],
      showAdmin: true,
    );

    router.go(AppRoutes.home);
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);

    router.go(AppRoutes.records);
    await tester.pumpAndSettle();
    expect(find.byType(RecordsScreen), findsOneWidget);

    router.go(AppRoutes.admin);
    await tester.pumpAndSettle();
    expect(find.text('관리자 화면은 Phase 3에서 구현합니다'), findsOneWidget);

    router.go(AppRoutes.profile);
    await tester.pumpAndSettle();
    expect(find.text('마이페이지는 #13에서 구현합니다'), findsOneWidget);
  });

  testWidgets('탭을 전환했다 돌아오면 이전 탭의 스크롤 위치와 네비게이션 스택이 보존된다', (tester) async {
    final (:router, container: _) = await _pumpRealRouter(tester, clubIds: const [7]);

    // 기록 탭의 본문을 스크롤해 둔다. 예전에는 이 자리가 항목 30개짜리
    // 자리표시자 `ListView`였다 — 지금은 실제 기록 화면(달력 카드 + 요약
    // 카드 3장)이고, 800×600 테스트 화면에서는 그 내용이 넘쳐 실제로
    // 스크롤된다.
    router.go(AppRoutes.records);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -120));
    await tester.pumpAndSettle();
    final scrolledOffset = tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;
    expect(scrolledOffset, greaterThan(0));

    // 마이 탭으로 이동한 뒤, 그 안에서 비밀번호 변경 화면까지 한 단계 더
    // 들어간다 — 마이 탭의 네비게이션 스택이 [마이페이지, 비밀번호 변경]
    // 두 단계가 된다.
    await tester.tap(find.text('마이'));
    await tester.pumpAndSettle();
    expect(find.text('마이페이지는 #13에서 구현합니다'), findsOneWidget);

    router.push(AppRoutes.passwordChange);
    await tester.pumpAndSettle();
    expect(find.text('비밀번호 변경은 #13에서 구현합니다'), findsOneWidget);
    // 상단 바 제목도 현재 위치(=/profile/password)를 따라가야 한다.
    // navigationShell.currentIndex는 브랜치 전환 때만 바뀌므로(같은 마이
    // 브랜치 안에서 한 단계 더 들어간 것뿐이라 3 그대로), 제목을
    // currentIndex로 뽑으면 이 화면에서도 "마이페이지"가 그대로 남는다.
    expect(find.text('비밀번호 변경'), findsOneWidget);
    expect(find.text('마이페이지'), findsNothing);

    // 홈 탭으로 전환했다가...
    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);

    // ...다시 마이 탭으로 돌아오면, 루트(마이페이지)가 아니라 방금
    // 들어갔던 비밀번호 변경 화면이 그대로 남아있어야 한다.
    await tester.tap(find.text('마이'));
    await tester.pumpAndSettle();
    expect(find.text('비밀번호 변경은 #13에서 구현합니다'), findsOneWidget);
    expect(find.text('마이페이지는 #13에서 구현합니다'), findsNothing);

    // ...그리고 기록 탭으로 돌아오면 스크롤 위치도 그대로 보존돼 있어야
    // 한다. `IndexedStack` 대신 탭마다 매번 새로 빌드하면 스크롤 가능한
    // 위젯의 State(따라서 스크롤 위치)가 사라지고 0으로 다시 시작한다.
    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();
    final restoredOffset = tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;
    expect(restoredOffset, scrolledOffset);
  });

  // AppShell이 상단 바 제목을 state.uri.path가 아니라 .toString()으로
  // 뽑으면, 쿼리 문자열이 그대로 붙어 _titleFor의 정확 일치 switch가
  // 아무 case에도 걸리지 않아 제목이 빈 문자열이 된다.
  testWidgets('제목은 쿼리 문자열이 붙어도 정확히 표시된다', (tester) async {
    final (:router, container: _) = await _pumpRealRouter(tester, clubIds: const [7]);

    router.go('${AppRoutes.passwordChange}?source=notification');
    await tester.pumpAndSettle();

    expect(find.text('비밀번호 변경은 #13에서 구현합니다'), findsOneWidget);
    expect(find.text('비밀번호 변경'), findsOneWidget);
  });

  testWidgets('showAdmin: false 상태에서 /admin으로 이동하면 /home으로 차단된다', (tester) async {
    // showAdmin 기본값 false — 실제 앱과 동일한 상태.
    final (:router, container: _) = await _pumpRealRouter(tester, clubIds: const [7]);

    router.go(AppRoutes.admin);
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('관리자 화면은 Phase 3에서 구현합니다'), findsNothing);
  });

  // Codex가 찾은 결함: 라우터의 refreshListenable(_SessionListenable)이
  // sessionControllerProvider만 구독하고, showAdminTabProvider는
  // redirect 평가 시점에 값만 한 번 읽는다. 그래서 Phase 3에서 이
  // Provider가 실제 role 조회로 바뀐 뒤 — 사용자가 이미 /admin에 들어가
  // 있는 상태에서 role이 회수되면 — `AppShell`은 `ref.watch`라 탭은 바로
  // 사라지지만, 그 자체는 새 내비게이션이 아니라서 아무 redirect도
  // 재평가되지 않는다. 관리자 화면은 선택된 탭 없이 계속 남아 있다가,
  // 사용자가 뭔가 다른 내비게이션을 시도해야 비로소 튕겨난다. 이 테스트는
  // `container.updateOverrides`로 아무 내비게이션 없이 provider 값만
  // 바꿔, redirect가 스스로 재평가되는지 확인한다.
  testWidgets(
    'showAdmin이 /admin에 있는 동안 false로 바뀌면 내비게이션 없이도 /home으로 리다이렉트된다',
    (tester) async {
      final store = InMemoryTokenStore();
      await store.save(accessToken: 'a', refreshToken: 'r');

      final container = ProviderContainer(
        overrides: [
          tokenStoreProvider.overrideWithValue(store),
          authRepositoryProvider.overrideWithValue(_ProfileAuthRepository(const [7])),
          showAdminTabProvider.overrideWithValue(true),
          ..._homeScreenOverrides(),
        ],
      );
      addTearDown(container.dispose);

      final router = container.read(appRouterProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 1600)));
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();

      router.go(AppRoutes.admin);
      await tester.pumpAndSettle();
      expect(find.text('관리자 화면은 Phase 3에서 구현합니다'), findsOneWidget);

      // 여기서부터가 핵심이다 — router.go/push를 전혀 부르지 않는다.
      // provider override만 바꾼다(Phase 3의 실제 role 회수를 흉내낸다).
      container.updateOverrides([
        tokenStoreProvider.overrideWithValue(store),
        authRepositoryProvider.overrideWithValue(_ProfileAuthRepository(const [7])),
        showAdminTabProvider.overrideWithValue(false),
        ..._homeScreenOverrides(),
      ]);
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('관리자 화면은 Phase 3에서 구현합니다'), findsNothing);
    },
  );

  // readyAllowedLocations는 아무것도 라우트 트리와 구조적으로 묶어 두지
  // 않는다 — 탭을 추가하고 이 집합 갱신을 잊으면, 콜드 스타트 딥링크가
  // 조용히 /home으로 튕긴다. 예전 버전은 라우트 트리 "전체"를 훑어서
  // 4개(스플래시/로그인/회원가입/초대코드) 하드코딩 경로를 뺀 나머지와
  // 비교했는데, 그러면 (1) `/records`를 셸 밖(최상위 형제 라우트)으로
  // 옮겨도 여전히 registered에 잡혀 그냥 통과했다 — 셸 탭이 아니게 됐는데도.
  // 이 버전은 셸의 **branches만** 훑는다.
  test('readyAllowedLocations가 셸 브랜치에 실제로 등록된 경로와 정확히 일치한다', () {
    final container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        authRepositoryProvider.overrideWithValue(_ProfileAuthRepository(const [])),
      ],
    );
    addTearDown(container.dispose);

    final router = container.read(appRouterProvider);
    final shellRoute = _findShellRoute(router.configuration.routes);
    final shellPaths = _pathsIn(router, shellRoute.branches.expand((b) => b.routes).toList());

    expect(shellPaths, readyAllowedLocations);
  });

  // 위 테스트는 "경로 집합"만 본다 — 브랜치 개수나 순서가 달라져도 경로
  // 집합 자체는 같을 수 있다(예: 브랜치가 하나 없어졌는데 다른 브랜치가
  // 우연히 그 경로를 포함). `AppTab`에 탭을 추가하고 짝이 되는
  // `StatefulShellBranch`를 빠뜨리면, `AppBottomNav`엔 탭이 하나 더
  // 보이는데 `navigationShell.goBranch(그 인덱스)`는 범위를 벗어난
  // 브랜치를 가리키게 된다 — 이 테스트가 그 어긋남을 잡는다.
  test('셸 브랜치 개수·순서가 AppTab과 정확히 일치한다', () {
    final container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        authRepositoryProvider.overrideWithValue(_ProfileAuthRepository(const [])),
      ],
    );
    addTearDown(container.dispose);

    final router = container.read(appRouterProvider);
    final shellRoute = _findShellRoute(router.configuration.routes);

    expect(
      shellRoute.branches.length,
      AppTab.values.length,
      reason: 'AppTab 값 개수와 브랜치 개수가 어긋나면 범위를 벗어난 goBranch 호출이 생긴다',
    );

    for (var i = 0; i < AppTab.values.length; i++) {
      final branchPaths = _pathsIn(router, shellRoute.branches[i].routes);
      expect(
        branchPaths,
        contains(_basePathFor(AppTab.values[i])),
        reason:
            '브랜치 $i는 AppTab.${AppTab.values[i].name}의 기본 경로(${_basePathFor(AppTab.values[i])})를 '
            '포함해야 한다 — 아니면 브랜치 순서가 AppTab 순서와 어긋난 것이다',
      );
    }
  });
}

/// 라우트 트리(최상위 `routes`) 안에서 셸 라우트를 찾는다.
StatefulShellRoute _findShellRoute(List<RouteBase> routes) {
  for (final route in routes) {
    if (route is StatefulShellRoute) return route;
  }
  throw StateError('StatefulShellRoute를 찾지 못했다');
}

/// 주어진 라우트 목록(과 그 자손)에서 실제로 매칭되는 전체 경로를 전부
/// 모은다.
Set<String> _pathsIn(GoRouter router, List<RouteBase> routes) {
  final paths = <String>{};
  void walk(List<RouteBase> routes) {
    for (final route in routes) {
      if (route is GoRoute) {
        final path = router.configuration.locationForRoute(route);
        if (path != null) paths.add(path);
      }
      walk(route.routes);
    }
  }

  walk(routes);
  return paths;
}

/// `AppTab`이 자기 브랜치 안에서 대표로 갖고 있어야 할 최상위 경로.
String _basePathFor(AppTab tab) => switch (tab) {
  AppTab.home => AppRoutes.home,
  AppTab.records => AppRoutes.records,
  AppTab.admin => AppRoutes.admin,
  AppTab.profile => AppRoutes.profile,
};
