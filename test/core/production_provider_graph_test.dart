import 'package:beacon_app/core/network/api_client.dart';
import 'package:beacon_app/core/network/dio_provider.dart';
import 'package:beacon_app/core/router/app_router.dart';
import 'package:beacon_app/features/attendance/data/attendance_repository.dart';
import 'package:beacon_app/features/attendance/presentation/attendance_controller.dart';
import 'package:beacon_app/features/auth/data/auth_repository.dart';
import 'package:beacon_app/features/beacon/data/beacon_config_repository.dart';
import 'package:beacon_app/features/beacon/data/flutter_beacon_scanner.dart';
import 'package:beacon_app/features/beacon/domain/beacon_scanner.dart';
import 'package:beacon_app/features/club/data/club_repository.dart';
import 'package:beacon_app/features/profile/data/profile_repository.dart';
import 'package:beacon_app/features/records/data/records_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// **프로덕션 프로바이더 배선을 실제로 지나는 유일한 테스트다.**
///
/// 이 파일이 필요한 이유: 이 프로젝트의 화면·컨트롤러 테스트는 전부 관련
/// 프로바이더를 가짜로 덮는다. 그래서 프로바이더가 무엇을 돌려주든 스위트가
/// 초록이다 — 리뷰에서 `beaconScannerProvider`를 `FakeBeaconScanner()`로
/// 바꿔도 380개가 전부 통과했고, **릴리즈 앱은 실제 BLE를 한 번도 스캔하지
/// 않는 상태**가 됐다.
///
/// 같은 유형이 그 뒤로 두 번 더 나왔다. 스캐너의 만료 타이머 기본값
/// `Timer.new`를 `Duration(days: 365)`로 바꿔도, 홈의 기본 시계
/// `DateTime.now`를 1999년으로 고정해도 전 스위트가 초록이었다 — 모든
/// 테스트가 그 주입점을 덮고 있었기 때문이다.
///
/// **테스트 편의를 위한 주입점이 곧 검증 사각지대가 된다.** 그 주입점의
/// 프로덕션 기본값을 지나는 검사가 어딘가에 하나는 있어야 한다.
///
/// 여기서는 타입만 확인한다 — 진짜 네트워크나 BLE를 부르지 않으면서
/// "무엇이 배선돼 있는가"를 고정하는 것이 목적이다.
void main() {
  late ProviderContainer container;

  setUpAll(() {
    // 실제 앱은 `main()`에서 `.env`를 읽는다. 그 로드가 없으면
    // `apiClientProvider`가 곧장 던진다 — 그 사실 자체도 프로덕션 배선의
    // 일부이므로 여기서 흉내 내지 않고 실제 로더를 쓴다. 호스트 값은
    // 무엇이든 상관없다(요청을 보내지 않는다).
    dotenv.loadFromString(envString: 'API_BASE_URL=https://example.invalid');
  });

  setUp(() {
    // 실사용과 같은 컨테이너다. **어떤 override도 주지 않는다** — 그게
    // 이 파일의 전부다.
    container = ProviderContainer();
  });

  tearDown(() => container.dispose());

  test('프로바이더가 전부 실제 구현을 돌려준다', () {
    // 표로 두는 이유: 프로바이더가 하나 늘 때 이 목록에 줄을 더하지 않으면
    // 그 프로바이더는 다시 사각지대가 된다. 개별 테스트로 흩어 두면 빠진
    // 것을 알아채기 어렵다.
    // 기댓값을 **읽어 온 값에서 계산하지 않는다** — `type: read().runtimeType`
    // 처럼 쓰면 양변이 함께 움직여 어떤 변이도 잡지 못한다(처음에 `dioProvider`
    // 를 그렇게 썼다가 알아챘다). 각 줄은 리터럴 매처여야 한다.
    final expectations = <String, ({Object Function() read, Matcher matcher})>{
      'beaconScannerProvider': (
        read: () => container.read(beaconScannerProvider),
        matcher: isA<FlutterBeaconScanner>(),
      ),
      'apiClientProvider': (
        read: () => container.read(apiClientProvider),
        matcher: isA<ApiClient>(),
      ),
      // `Dio()`는 플랫폼별 구현(`DioForNative`)을 돌려주므로 인터페이스로 본다.
      'dioProvider': (read: () => container.read(dioProvider), matcher: isA<Dio>()),
      'attendanceRepositoryProvider': (
        read: () => container.read(attendanceRepositoryProvider),
        matcher: isA<HttpAttendanceRepository>(),
      ),
      'attendanceControllerProvider': (
        read: () => container.read(attendanceControllerProvider),
        matcher: isA<AttendanceController>(),
      ),
      'authRepositoryProvider': (
        read: () => container.read(authRepositoryProvider),
        matcher: isA<HttpAuthRepository>(),
      ),
      'beaconConfigRepositoryProvider': (
        read: () => container.read(beaconConfigRepositoryProvider),
        matcher: isA<HttpBeaconConfigRepository>(),
      ),
      'clubRepositoryProvider': (
        read: () => container.read(clubRepositoryProvider),
        matcher: isA<HttpClubRepository>(),
      ),
      'profileRepositoryProvider': (
        read: () => container.read(profileRepositoryProvider),
        matcher: isA<HttpProfileRepository>(),
      ),
      'recordsRepositoryProvider': (
        read: () => container.read(recordsRepositoryProvider),
        matcher: isA<HttpRecordsRepository>(),
      ),
    };

    for (final entry in expectations.entries) {
      expect(
        entry.value.read(),
        entry.value.matcher,
        reason: '${entry.key}가 프로덕션 구현을 돌려주지 않는다',
      );
    }
  });

  test('beaconScannerProvider는 테스트 더블을 돌려주지 않는다', () {
    // 위 표가 타입 이름을 확인하지만, 그것만으로는 "가짜로 바뀌었다"를
    // 읽는 사람이 알아채기 어렵다. 이 검사는 의도를 이름으로 남긴다 —
    // 실제로 이 배선이 가짜로 바뀐 채 380개가 통과한 적이 있다.
    final scanner = container.read(beaconScannerProvider);
    expect(scanner, isA<BeaconScanner>());
    expect(
      scanner.runtimeType.toString(),
      isNot(contains('Fake')),
      reason: '릴리즈 앱이 실제 BLE를 스캔하지 않게 된다',
    );
  });

  test('showAdminTabProvider의 기본값은 false다', () {
    // 관리자 UI 노출 기본값은 안전한 쪽이어야 한다. 이 값도 화면 테스트가
    // 전부 덮어쓰므로 기본값을 지나는 검사가 여기 말고는 없다.
    expect(container.read(showAdminTabProvider), isFalse);
  });
}
