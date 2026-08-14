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

Future<ProviderContainer> _pumpHome(
  WidgetTester tester, {
  required FakeBeaconScanner scanner,
  required _ScriptedAttendanceRepository attendanceRepository,
  BeaconConfigRepository? beaconConfigRepository,
  RecordsRepository? recordsRepository,
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

  testWidgets('블루투스 꺼짐 상태에서 설정 열기 버튼이 렌더된다', (tester) async {
    // 잡아야 할 잘못된 구현: 비콘 상태를 무시하고 항상 같은 화면을 그린다
    // — BluetoothOff여도 "설정 열기" 버튼이 나타나지 않는다.
    final scanner = FakeBeaconScanner();
    final repo = _ScriptedAttendanceRepository(activeSession: _activeSession);
    await _pumpHome(tester, scanner: scanner, attendanceRepository: repo);

    scanner.emit(const BeaconBluetoothOff());
    await tester.pumpAndSettle();

    expect(find.text('설정 열기'), findsOneWidget);
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
    expect(find.text('출석 완료'), findsNothing);
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

    expect(find.text('출석 완료'), findsOneWidget);
    expect(find.text('지각 처리되었습니다'), findsNothing);
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

    expect(find.text('출석 완료'), findsOneWidget);

    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    expect(find.text('출석 완료'), findsNothing, reason: '완료 시트가 닫혀 있어야 한다');
    // 비콘은 여전히 감지 상태(Detected)이고 활성 세션도 그대로지만, 이미
    // 출석을 마쳤으므로 입력란은 다시 열리면 안 된다.
    expect(find.byType(AppOtpInput), findsNothing);
  });
}
