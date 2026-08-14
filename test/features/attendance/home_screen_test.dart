import 'package:beacon_app/components/ui/button.dart';
import 'package:beacon_app/components/ui/otp_input.dart';
import 'package:beacon_app/core/network/api_exception.dart';
import 'package:beacon_app/core/network/error_code.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:beacon_app/features/attendance/data/attendance_dto.dart';
import 'package:beacon_app/features/attendance/data/attendance_repository.dart';
import 'package:beacon_app/features/attendance/presentation/home_screen.dart';
import 'package:beacon_app/features/auth/data/auth_dto.dart';
import 'package:beacon_app/features/auth/presentation/session_controller.dart';
import 'package:beacon_app/features/beacon/data/beacon_config_dto.dart';
import 'package:beacon_app/features/beacon/data/beacon_config_repository.dart';
import 'package:beacon_app/features/beacon/data/beacon_settings.dart';
import 'package:beacon_app/features/beacon/data/fake_beacon_scanner.dart';
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

const _beaconConfig = BeaconConfig(
  uuid: 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0',
  lateThresholdMinutes: 10,
  rssiStabilizationSeconds: 3,
  rssiThreshold: -70,
);

const _activeSession = ActiveSession(
  sessionId: 88,
  sessionName: '정기모임',
  status: 'ACTIVE',
);

/// `SessionController.build()`가 곧장 `SessionReady`를 돌려주게 하는
/// 테스트 더블 — 토큰 저장소·인증 리포지토리를 전부 배선할 필요 없이
/// clubId를 곧장 확정할 수 있다.
class _ReadySessionController extends SessionController {
  _ReadySessionController(this.profile);

  final MemberProfile profile;

  @override
  Future<SessionState> build() async => SessionReady(profile);
}

class _FakeBeaconConfigRepository implements BeaconConfigRepository {
  @override
  Future<BeaconConfig> fetch(int clubId) async => _beaconConfig;
}

/// checkIn 호출을 스크립트로 넣고, 실제로 전달된 인자를 기록하는 페이크.
class _ScriptedAttendanceRepository implements AttendanceRepository {
  _ScriptedAttendanceRepository({this.activeSession});

  ActiveSession? activeSession;
  final List<Object> results = []; // AttendanceStatus 또는 ApiException
  final List<(int clubId, int sessionId, String otpCode)> checkInArgs = [];
  int _callIndex = 0;

  @override
  Future<ActiveSession?> fetchActiveSession(int clubId) async => activeSession;

  @override
  Future<AttendanceStatus> checkIn({
    required int clubId,
    required int sessionId,
    required String otpCode,
  }) async {
    checkInArgs.add((clubId, sessionId, otpCode));
    final result = results[_callIndex];
    _callIndex++;
    if (result is ApiException) throw result;
    return result as AttendanceStatus;
  }
}

class _EmptyRecordsRepository implements RecordsRepository {
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

Future<ProviderContainer> _pumpHome(
  WidgetTester tester, {
  required FakeBeaconScanner scanner,
  required _ScriptedAttendanceRepository attendanceRepository,
  BeaconConfigRepository? beaconConfigRepository,
  RecordsRepository? recordsRepository,
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
      recordsRepositoryProvider.overrideWithValue(recordsRepository ?? _EmptyRecordsRepository()),
      ...extraOverrides,
    ],
  );
  addTearDown(container.dispose);

  // 실제 앱에서는 AppShell의 Scaffold 안에서 렌더되므로(app_router.dart),
  // 여기서도 Scaffold로 감싼다 — 그렇지 않으면 AppOtpInput의 TextField가
  // Material 조상을 찾지 못해 예외를 던진다.
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: HomeScreen()),
      ),
    ),
  );
  // 1) 세션 판별(SessionController.build) 완료, 2) 그 결과로 홈 화면이
  // bootstrap을 시작, 3) bootstrap의 각 Future(비콘 설정 조회 → watch 구독
  // 시작, 활성 세션 조회, 기록 조회) 완료까지 흘려보낸다.
  await tester.pumpAndSettle();

  return container;
}

Future<void> _enterOtp(WidgetTester tester, String code) async {
  final fields = find.byType(TextField);
  for (var i = 0; i < code.length; i++) {
    await tester.enterText(fields.at(i), code[i]);
    await tester.pump();
  }
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

    // 홈 화면을 트리에서 완전히 제거해 dispose를 유발한다.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(scanner.stopCallCount, greaterThanOrEqualTo(1));
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
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconBluetoothOff());
    await tester.pumpAndSettle();
    expect(find.text('블루투스가 꺼져 있어요'), findsOneWidget);

    scanner.emit(const BeaconScanning());
    await tester.pumpAndSettle();

    expect(find.text('블루투스가 꺼져 있어요'), findsNothing);
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
}
