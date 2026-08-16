import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:beacon_app/features/attendance/data/attendance_dto.dart';
import 'package:beacon_app/features/attendance/data/attendance_repository.dart';
import 'package:beacon_app/features/attendance/presentation/home_screen.dart';
import 'package:beacon_app/features/auth/data/auth_dto.dart';
import 'package:beacon_app/features/auth/presentation/session_controller.dart';
import 'package:beacon_app/features/beacon/data/beacon_config_dto.dart';
import 'package:beacon_app/features/beacon/data/beacon_config_repository.dart';
import 'package:beacon_app/features/beacon/data/fake_beacon_scanner.dart';
import 'package:beacon_app/features/beacon/data/flutter_beacon_scanner.dart'
    show beaconScannerProvider;
import 'package:beacon_app/features/records/data/records_dto.dart';
import 'package:beacon_app/features/records/data/records_repository.dart';
import 'package:beacon_app/features/records/presentation/records_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// **홈과 기록이 같은 시각에 대해 같은 달을 여는지** 두 화면을 실제로 띄워
/// 맞춰 본다.
///
/// 이 파일이 따로 있는 이유: 처음에는 홈 테스트 안에서
/// `expect(homeRecords.requested.single, (toKst(clock()).year, ...))`처럼
/// **기댓값을 프로덕션과 같은 `toKst` 호출로 계산**했다. 그러면 `toKst`가
/// 무엇을 하든 양변이 함께 움직여서 **어떤 오프셋 변이도 잡지 못한다** —
/// `kstOffset`을 0으로 만들어도, 기록 화면에서 KST를 통째로 걷어내도
/// 통과했다(리뷰 Minor 1). 두 화면을 각각 띄워 **서로** 비교해야 의미가 있다.
void main() {
  /// KST 9월 1일 00:00 — UTC로는 8월 31일 15:00이라 두 달이 갈린다.
  DateTime boundary() => DateTime.utc(2026, 8, 31, 15);

  testWidgets('경계 시각에 두 화면이 같은 (year, month)를 조회한다', (tester) async {
    final homeRequests = <(int, int)>[];
    final recordsRequests = <(int, int)>[];

    await _pumpHome(tester, clock: boundary, onFetch: homeRequests.add);
    await _pumpRecords(tester, clock: boundary, onFetch: recordsRequests.add);

    expect(homeRequests, isNotEmpty, reason: '홈이 요약 카드를 조회하지 않았다');
    expect(recordsRequests, isNotEmpty, reason: '기록 화면이 조회하지 않았다');
    expect(
      homeRequests.first,
      recordsRequests.first,
      reason: '같은 시각인데 두 화면이 다른 달을 가리키면 라벨은 같고 내용만 다르다',
    );
    // 어느 쪽이 맞는지도 못박는다 — 둘 다 UTC 기준(8월)으로 틀렸는데 서로
    // 일치하기만 하는 구현을 배제한다.
    expect(homeRequests.first, (2026, 9));
  });
}

class _CollectingRecordsRepository implements RecordsRepository {
  _CollectingRecordsRepository(this.onFetch);

  final void Function((int, int)) onFetch;

  @override
  Future<MonthlyRecords> fetch({
    required int clubId,
    required int year,
    required int month,
  }) async {
    onFetch((year, month));
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

class _ReadySessionController extends SessionController {
  @override
  Future<SessionState> build() async => SessionReady(
    const MemberProfile(name: '김민준', stdId: '20250101', clubIds: [7], pushEnabled: true),
  );
}

class _NoActiveSessionRepository implements AttendanceRepository {
  @override
  Future<ActiveSession?> fetchActiveSession(int clubId) async => null;

  @override
  Future<AttendanceStatus> checkIn({
    required int clubId,
    required int sessionId,
    required String otpCode,
  }) async => AttendanceStatus.present;
}

class _FakeBeaconConfigRepository implements BeaconConfigRepository {
  @override
  Future<BeaconConfig> fetch(int clubId) async => const BeaconConfig(
    uuid: '11111111-1111-1111-1111-111111111111',
    lateThresholdMinutes: 10,
    rssiStabilizationSeconds: 3,
    rssiThreshold: -70,
  );
}

ProviderContainer _container(RecordsRepository records, {bool withAttendance = false}) {
  return ProviderContainer(
    overrides: [
      sessionControllerProvider.overrideWith(_ReadySessionController.new),
      recordsRepositoryProvider.overrideWithValue(records),
      if (withAttendance) ...[
        beaconScannerProvider.overrideWithValue(FakeBeaconScanner()),
        beaconConfigRepositoryProvider.overrideWithValue(_FakeBeaconConfigRepository()),
        attendanceRepositoryProvider.overrideWithValue(_NoActiveSessionRepository()),
      ],
    ],
  );
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required DateTime Function() clock,
  required void Function((int, int)) onFetch,
}) async {
  final container = _container(_CollectingRecordsRepository(onFetch), withAttendance: true);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: HomeScreen(clock: clock)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpRecords(
  WidgetTester tester, {
  required DateTime Function() clock,
  required void Function((int, int)) onFetch,
}) async {
  final container = _container(_CollectingRecordsRepository(onFetch));
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: RecordsScreen(clock: clock)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
