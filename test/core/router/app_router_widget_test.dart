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
import 'package:beacon_app/features/club/presentation/invite_code_screen.dart';
import 'package:beacon_app/features/records/data/records_dto.dart';
import 'package:beacon_app/features/records/data/records_repository.dart';
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
/// `HomeScreen` 관련 override 4종.
List<Override> _homeScreenOverrides() => [
  beaconScannerProvider.overrideWithValue(FakeBeaconScanner()),
  beaconConfigRepositoryProvider.overrideWithValue(_NoopBeaconConfigRepository()),
  attendanceRepositoryProvider.overrideWithValue(_NoopAttendanceRepository()),
  recordsRepositoryProvider.overrideWithValue(_NoopRecordsRepository()),
];

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
}) async {
  final store = InMemoryTokenStore();
  if (clubIds != null) await store.save(accessToken: 'a', refreshToken: 'r');

  final container = ProviderContainer(
    overrides: [
      tokenStoreProvider.overrideWithValue(store),
      authRepositoryProvider.overrideWithValue(_ProfileAuthRepository(clubIds ?? const [])),
      showAdminTabProvider.overrideWithValue(showAdmin),
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
    expect(find.text('기록 화면은 #12에서 구현합니다'), findsOneWidget);

    router.go(AppRoutes.admin);
    await tester.pumpAndSettle();
    expect(find.text('관리자 화면은 Phase 3에서 구현합니다'), findsOneWidget);

    router.go(AppRoutes.profile);
    await tester.pumpAndSettle();
    expect(find.text('마이페이지는 #13에서 구현합니다'), findsOneWidget);
  });

  testWidgets('탭을 전환했다 돌아오면 이전 탭의 스크롤 위치와 네비게이션 스택이 보존된다', (tester) async {
    final (:router, container: _) = await _pumpRealRouter(tester, clubIds: const [7]);

    // 기록 탭에서 목록을 스크롤해 둔다.
    router.go(AppRoutes.records);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -600));
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
