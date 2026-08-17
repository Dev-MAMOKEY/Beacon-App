import 'package:beacon_app/core/network/api_exception.dart';
import 'package:beacon_app/core/network/error_code.dart';
import 'package:beacon_app/core/theme/app_theme.dart';
import 'package:beacon_app/features/admin/data/beacon_psk_store.dart';
import 'package:beacon_app/features/admin/data/club_member_repository.dart';
import 'package:beacon_app/features/admin/data/attendance_admin_dto.dart';
import 'package:beacon_app/features/admin/data/session_dto.dart';
import 'package:beacon_app/features/admin/data/session_repository.dart';
import 'package:beacon_app/features/admin/presentation/admin_screen.dart';
import 'package:beacon_app/features/admin/presentation/beacon_psk_popup.dart';
import 'package:beacon_app/features/admin/presentation/club_settings_sheet.dart';
import 'package:beacon_app/features/attendance/data/attendance_dto.dart';
import 'package:beacon_app/features/auth/data/auth_dto.dart';
import 'package:beacon_app/features/auth/presentation/session_controller.dart';
import 'package:beacon_app/features/beacon/data/beacon_config_dto.dart';
import 'package:beacon_app/features/beacon/data/beacon_config_repository.dart';
import 'package:beacon_app/features/club/data/club_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _storedBeacon = BeaconConfig(
  uuid: 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0',
  lateThresholdMinutes: 10,
  rssiStabilizationSeconds: 3,
  rssiThreshold: -70,
);

class _FakeSettingsRepository implements ClubSettingsRepository {
  _FakeSettingsRepository({
    this.code,
    this.failUpdate = false,
    this.failIssue = false,
  });

  ClubDetail club = const ClubDetail(
    id: 7,
    clubName: '마모키',
    clubDescription: '비콘 동아리',
  );
  String? code;
  final bool failUpdate;
  final bool failIssue;

  final List<({String name, String description})> updates = [];
  int issued = 0;
  int revoked = 0;

  @override
  Future<ClubDetail> fetchClub(int clubId) async => club;

  @override
  Future<void> updateClub({
    required int clubId,
    required String clubName,
    required String clubDescription,
  }) async {
    updates.add((name: clubName, description: clubDescription));
    if (failUpdate) throw ApiException(ErrorCode.unknown, '실패');
    // 서버가 **손질해서** 저장한다. 보낸 값과 다르게 만들어 두지 않으면,
    // "다시 읽어서 채웠다"와 "내가 친 값이 그냥 남아 있다"를 테스트가
    // 구별하지 못한다.
    club = ClubDetail(
      id: clubId,
      clubName: clubName,
      clubDescription: '[서버] $clubDescription',
    );
  }

  @override
  Future<String?> fetchInviteCode(int clubId) async => code;

  @override
  Future<String> issueInviteCode(int clubId) async {
    issued++;
    if (failIssue) throw ApiException(ErrorCode.unknown, '실패');
    return code = 'NEW${issued.toString().padLeft(5, '0')}';
  }

  @override
  Future<void> revokeInviteCode(int clubId) async {
    revoked++;
    code = null;
  }
}

class _FakeBeaconRepository implements BeaconConfigRepository {
  _FakeBeaconRepository({this.failFetch = false});

  BeaconConfig stored = _storedBeacon;
  final bool failFetch;
  final List<BeaconConfig> saved = [];

  @override
  Future<BeaconConfig> fetch(int clubId) async {
    if (failFetch) throw ApiException(ErrorCode.unknown, '실패');
    return stored;
  }

  /// 서버가 지각 기준을 5분 단위로 올림해 저장한다고 치자. 보낸 값을
  /// 그대로 돌려주면 "응답을 반영한다"와 "보낸 값을 그냥 쓴다"를 테스트가
  /// 구별하지 못한다.
  @override
  Future<BeaconConfig> update(int clubId, BeaconConfig config) async {
    saved.add(config);
    return stored = config.copyWith(
      lateThresholdMinutes: ((config.lateThresholdMinutes + 4) ~/ 5) * 5,
    );
  }
}

class _FakePskStore implements BeaconPskStore {
  _FakePskStore([this.stored]);

  String? stored;
  final List<String> saved = [];

  @override
  Future<String?> read() async => stored;

  @override
  Future<void> save(String psk) async {
    saved.add(psk);
    stored = psk;
  }

  @override
  Future<void> clear() async => stored = null;
}

class _EmptySessionRepository implements SessionRepository {
  @override
  Future<SessionPage> fetchSessions({
    required int clubId,
    SessionStatus? status,
    int page = 0,
    int size = 20,
  }) async => const SessionPage(sessions: [], isLast: true);

  @override
  Future<int> countAttendees({required int clubId, required int sessionId}) async => 0;

  @override
  Future<List<AdminAttendanceRecord>> fetchAttendance({
    required int clubId,
    required int sessionId,
  }) async => const [];

  @override
  Future<void> updateAttendanceStatus({
    required int clubId,
    required int sessionId,
    required int recordId,
    required AttendanceStatus status,
    String? adminNote,
  }) async {}

  @override
  Future<void> addManualAttendance({
    required int clubId,
    required int sessionId,
    required int memberId,
    required AttendanceStatus status,
    String? adminNote,
  }) async {}

  // 이 더블은 세션을 건드리지 않는 설정 화면 테스트 전용이다 — 부르면
  // 테스트가 잘못 짜인 것이므로 조용히 성공하지 않고 바로 터뜨린다.
  @override
  Future<void> create({required int clubId, required SessionDraft draft}) async =>
      throw UnimplementedError();

  @override
  Future<void> update({
    required int clubId,
    required int sessionId,
    required SessionDraft draft,
  }) async => throw UnimplementedError();

  @override
  Future<void> delete({required int clubId, required int sessionId}) async =>
      throw UnimplementedError();

  @override
  Future<SessionStartResult> start({required int clubId, required int sessionId}) async =>
      throw UnimplementedError();

  @override
  Future<void> end({required int clubId, required int sessionId}) async =>
      throw UnimplementedError();
}

class _NoMemberRepository implements ClubMemberRepository {
  @override
  Future<List<ClubMember>> fetchMembers(int clubId, {String? search}) async => const [];

  @override
  Future<void> updateRole({
    required int clubId,
    required int requesterId,
    required int targetMemberId,
    required ClubRole newRole,
  }) async => throw UnimplementedError();

  @override
  Future<void> removeMember({required int clubId, required int memberId}) async =>
      throw UnimplementedError();
}

class _ReadySessionController extends SessionController {
  @override
  Future<SessionState> build() async => const SessionReady(
    MemberProfile(name: '김민준', stdId: '20250101', clubIds: [7], pushEnabled: true),
  );
}

Future<void> _openSettings(
  WidgetTester tester, {
  _FakeSettingsRepository? settings,
  _FakeBeaconRepository? beacon,
  _FakePskStore? psk,
}) async {
  final container = ProviderContainer(
    overrides: [
      sessionControllerProvider.overrideWith(_ReadySessionController.new),
      sessionRepositoryProvider.overrideWithValue(_EmptySessionRepository()),
      clubMemberRepositoryProvider.overrideWithValue(_NoMemberRepository()),
      clubSettingsRepositoryProvider.overrideWithValue(
        settings ?? _FakeSettingsRepository(),
      ),
      beaconConfigRepositoryProvider.overrideWithValue(beacon ?? _FakeBeaconRepository()),
      beaconPskStoreProvider.overrideWithValue(psk ?? _FakePskStore()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildAppTheme(), home: const AdminScreen()),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('설정'));
  await tester.pumpAndSettle();
}

/// 시트 안에서만 찾는다 — 상단 바에도 "설정"이 있다.
Finder _inSheet(String text) => find.descendant(
  of: find.byType(ClubSettingsSheetContent),
  matching: find.text(text),
);

/// 시트는 세로로 길어 버튼이 화면 밖에 있다. 스크롤해 올린 뒤 누른다 —
/// 그냥 [WidgetTester.tap]을 부르면 "밖에 있다"며 실패한다.
Future<void> _tapInSheet(WidgetTester tester, String label) async {
  await tester.ensureVisible(_inSheet(label));
  await tester.pumpAndSettle();
  await tester.tap(_inSheet(label));
  await tester.pumpAndSettle();
}

/// 편집할 입력칸도 화면 밖일 수 있다.
Future<void> _enterInSheet(WidgetTester tester, String current, String next) async {
  final field = find.widgetWithText(TextField, current);
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, next);
  await tester.pumpAndSettle();
}

void main() {
  group('동아리 정보', () {
    testWidgets('현재 값을 채워서 연다', (tester) async {
      // 빈 칸으로 열면 관리자가 기존 설명을 모른 채 덮어쓴다.
      await _openSettings(tester);

      expect(find.widgetWithText(TextField, '마모키'), findsOneWidget);
      expect(find.widgetWithText(TextField, '비콘 동아리'), findsOneWidget);
    });

    testWidgets('이름과 설명을 함께 저장한다', (tester) async {
      final settings = _FakeSettingsRepository();
      await _openSettings(tester, settings: settings);

      await _enterInSheet(tester, '마모키', '새이름');
      await _tapInSheet(tester, '동아리 정보 저장');

      expect(settings.updates, [(name: '새이름', description: '비콘 동아리')]);
    });

    testWidgets('빈 이름은 보내지 않는다', (tester) async {
      // 서버가 거절하더라도 왕복 한 번이 그냥 낭비다. 무엇보다 이름 없는
      // 동아리를 만들 수 있는지 서버 스펙이 말해 주지 않는다.
      final settings = _FakeSettingsRepository();
      await _openSettings(tester, settings: settings);

      await _enterInSheet(tester, '마모키', '   ');
      await _tapInSheet(tester, '동아리 정보 저장');

      expect(settings.updates, isEmpty);
      expect(find.text('동아리명을 입력해주세요.'), findsOneWidget);
    });

    testWidgets('저장한 뒤 서버에서 다시 읽어 화면을 채운다', (tester) async {
      // `PATCH /clubs/{id}`의 응답은 수정된 동아리가 아니라 문자열이라,
      // 무엇이 저장됐는지는 다시 읽어야만 알 수 있다.
      final settings = _FakeSettingsRepository();
      await _openSettings(tester, settings: settings);

      await _enterInSheet(tester, '비콘 동아리', '바뀐 설명');
      await _tapInSheet(tester, '동아리 정보 저장');

      expect(settings.updates.single.description, '바뀐 설명', reason: '보낸 값');
      expect(
        find.widgetWithText(TextField, '[서버] 바뀐 설명'),
        findsOneWidget,
        reason: '화면에는 서버가 저장한 값이 보여야 한다',
      );
    });

    testWidgets('저장에 실패하면 알려준다', (tester) async {
      final settings = _FakeSettingsRepository(failUpdate: true);
      await _openSettings(tester, settings: settings);

      await _tapInSheet(tester, '동아리 정보 저장');

      expect(find.text('동아리 정보를 저장하지 못했습니다.'), findsOneWidget);
    });
  });

  group('초대코드', () {
    testWidgets('코드가 없으면 발급 버튼만 보인다', (tester) async {
      await _openSettings(tester, settings: _FakeSettingsRepository());

      expect(_inSheet('아직 발급된 코드가 없습니다.'), findsOneWidget);
      expect(_inSheet('코드 발급'), findsOneWidget);
      expect(_inSheet('복사하기'), findsNothing, reason: '복사할 것이 없다');
      expect(_inSheet('코드 무효화'), findsNothing, reason: '무효화할 것이 없다');
    });

    testWidgets('코드가 있으면 코드와 세 동작이 보인다', (tester) async {
      await _openSettings(tester, settings: _FakeSettingsRepository(code: 'ABCD1234'));

      expect(_inSheet('ABCD1234'), findsOneWidget);
      expect(_inSheet('복사하기'), findsOneWidget);
      expect(_inSheet('다시 만들기'), findsOneWidget, reason: '기존 코드는 서버가 자동 무효화한다');
      expect(_inSheet('코드 무효화'), findsOneWidget);
    });

    testWidgets('발급하면 새 코드가 바로 보인다', (tester) async {
      final settings = _FakeSettingsRepository();
      await _openSettings(tester, settings: settings);

      await _tapInSheet(tester, '코드 발급');

      expect(settings.issued, 1);
      expect(_inSheet('NEW00001'), findsOneWidget);
    });

    testWidgets('무효화하면 코드가 사라진다', (tester) async {
      final settings = _FakeSettingsRepository(code: 'ABCD1234');
      await _openSettings(tester, settings: settings);

      await _tapInSheet(tester, '코드 무효화');

      expect(settings.revoked, 1);
      expect(_inSheet('ABCD1234'), findsNothing);
      expect(_inSheet('아직 발급된 코드가 없습니다.'), findsOneWidget);
    });

    testWidgets('발급에 실패하면 코드를 지어내지 않는다', (tester) async {
      final settings = _FakeSettingsRepository(failIssue: true);
      await _openSettings(tester, settings: settings);

      await _tapInSheet(tester, '코드 발급');

      expect(find.text('초대코드를 발급하지 못했습니다.'), findsOneWidget);
      expect(_inSheet('아직 발급된 코드가 없습니다.'), findsOneWidget);
    });
  });

  group('비콘 설정', () {
    testWidgets('네 값을 모두 채워서 연다', (tester) async {
      await _openSettings(tester);

      expect(
        find.widgetWithText(TextField, 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, '10'), findsOneWidget, reason: '지각 기준');
      expect(find.widgetWithText(TextField, '3'), findsOneWidget, reason: '안정화 시간');
      expect(_inSheet('-70dBm'), findsOneWidget);
    });

    testWidgets('uuid만 바꿔도 나머지 세 값을 함께 보낸다', (tester) async {
      // `PUT`은 네 필드가 전부 required인 **전체 교체**다. uuid만 담아 보내면
      // 지각 기준·안정화 시간·임계값이 함께 사라진다.
      final beacon = _FakeBeaconRepository();
      await _openSettings(tester, beacon: beacon);

      await _enterInSheet(tester, 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0', '11111111-2222-3333-4444-555555555555');
      await _tapInSheet(tester, '비콘 설정 저장');

      expect(beacon.saved, hasLength(1));
      final sent = beacon.saved.single;
      expect(sent.uuid, '11111111-2222-3333-4444-555555555555');
      expect(sent.lateThresholdMinutes, 10);
      expect(sent.rssiStabilizationSeconds, 3);
      expect(sent.rssiThreshold, -70);
    });

    testWidgets('편집한 값이 각각 전달된다', (tester) async {
      // 한 칸만 바꿔 보면, **전달되지 않는 칸**이 있어도 원래 값과 같아서
      // 눈치채지 못한다. 셋을 한꺼번에 바꿔 각각을 본다.
      final beacon = _FakeBeaconRepository();
      await _openSettings(tester, beacon: beacon);

      await _enterInSheet(tester, 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0', 'NEW-UUID');
      await _enterInSheet(tester, '10', '20');
      await _enterInSheet(tester, '3', '7');
      await _tapInSheet(tester, '비콘 설정 저장');

      final sent = beacon.saved.single;
      expect(sent.uuid, 'NEW-UUID');
      expect(sent.lateThresholdMinutes, 20);
      expect(sent.rssiStabilizationSeconds, 7);
    });

    testWidgets('빈 UUID는 보내지 않는다', (tester) async {
      // 서버가 받아 저장하면 다음 조회에서 FormatException이 나고, 비콘
      // 설정을 읽는 모든 화면(부원 홈 포함)이 통째로 죽는다.
      final beacon = _FakeBeaconRepository();
      await _openSettings(tester, beacon: beacon);

      await _enterInSheet(tester, 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0', '  ');
      await _tapInSheet(tester, '비콘 설정 저장');

      expect(beacon.saved, isEmpty);
      expect(_inSheet('UUID를 입력해주세요.'), findsOneWidget);
    });

    testWidgets('안정화 시간 0초는 보내지 않는다', (tester) async {
      // 0이면 첫 샘플이 곧바로 조건을 만족해 안정화 보장 자체가 사라진다.
      final beacon = _FakeBeaconRepository();
      await _openSettings(tester, beacon: beacon);

      await _enterInSheet(tester, '3', '0');
      await _tapInSheet(tester, '비콘 설정 저장');

      expect(beacon.saved, isEmpty);
      expect(_inSheet('RSSI 안정화 시간은 1초 이상이어야 합니다.'), findsOneWidget);
    });

    testWidgets('숫자가 아닌 지각 기준은 보내지 않는다', (tester) async {
      final beacon = _FakeBeaconRepository();
      await _openSettings(tester, beacon: beacon);

      await _enterInSheet(tester, '10', '나중에');
      await _tapInSheet(tester, '비콘 설정 저장');

      expect(beacon.saved, isEmpty);
      expect(_inSheet('지각 시간 기준은 0 이상의 숫자여야 합니다.'), findsOneWidget);
    });

    testWidgets('슬라이더는 음수 범위를 벗어나지 않는다', (tester) async {
      // `rssiThreshold >= 0`은 서버가 거절하는 값이자, 통과하면 모든 판독을
      // 무조건 합격시켜 안정화 조건을 무의미하게 만드는 값이다. 숫자를 직접
      // 치게 두지 않고 슬라이더로 계약을 지킨다.
      expect(maxRssiThreshold, lessThan(0));
      expect(minRssiThreshold, lessThan(maxRssiThreshold));

      await _openSettings(tester);
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.min, minRssiThreshold.toDouble());
      expect(slider.max, maxRssiThreshold.toDouble());
    });

    testWidgets('서버가 다듬은 값을 화면에 반영한다', (tester) async {
      // 보낸 값을 그대로 쓰면 서버가 조정한 값과 화면이 어긋난다.
      final beacon = _FakeBeaconRepository();
      await _openSettings(tester, beacon: beacon);

      await _enterInSheet(tester, '10', '23');
      await _tapInSheet(tester, '비콘 설정 저장');

      expect(beacon.saved.single.lateThresholdMinutes, 23, reason: '보낸 값');
      expect(
        find.widgetWithText(TextField, '25'),
        findsOneWidget,
        reason: '서버가 25로 올려 저장했으면 칸에도 25가 보여야 한다',
      );
      expect(find.text('비콘 설정을 저장했습니다.'), findsOneWidget);
    });

    testWidgets('비콘 설정을 못 읽으면 설정 화면 전체가 실패로 보인다', (tester) async {
      // 편집할 대상이 없는데 빈 폼을 보여 주면, 저장하는 순간 다른 값들이
      // 기본값으로 덮인다.
      await _openSettings(tester, beacon: _FakeBeaconRepository(failFetch: true));

      expect(find.text('설정을 불러오지 못했습니다'), findsOneWidget);
    });
  });

  group('비콘 PSK', () {
    testWidgets('저장돼 있지 않으면 그렇게 말한다', (tester) async {
      await _openSettings(tester, psk: _FakePskStore());

      expect(_inSheet('아직 저장돼 있지 않습니다. 세션을 시작하려면 필요합니다.'), findsOneWidget);
      expect(_inSheet('PSK 입력'), findsOneWidget);
    });

    testWidgets('저장돼 있어도 값 자체는 보여주지 않는다', (tester) async {
      // 이 값을 아는 사람은 누구나 그 동아리 비콘에 출석 시작을 명령할 수 있다.
      const psk = '000102030405060708090a0b0c0d0e0f';
      await _openSettings(tester, psk: _FakePskStore(psk));

      expect(_inSheet('이 기기에 저장돼 있습니다.'), findsOneWidget);
      expect(find.text(psk), findsNothing, reason: 'PSK 원문이 화면에 나오면 안 된다');
    });

    testWidgets('형식이 맞는 PSK만 저장한다', (tester) async {
      final store = _FakePskStore();
      await _openSettings(tester, psk: store);

      await _tapInSheet(tester, 'PSK 입력');
      await tester.enterText(find.byType(TextField).last, 'not-hex');
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(store.saved, isEmpty);
    });

    testWidgets('저장하면 상태 문구가 바뀐다', (tester) async {
      final store = _FakePskStore();
      await _openSettings(tester, psk: store);

      await _tapInSheet(tester, 'PSK 입력');
      await tester.enterText(
        find.byType(TextField).last,
        '00112233445566778899aabbccddeeff',
      );
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(store.saved, ['00112233445566778899aabbccddeeff']);
      expect(find.byType(BeaconPskPopupContent), findsNothing);
      expect(_inSheet('이 기기에 저장돼 있습니다.'), findsOneWidget);
    });

    testWidgets('PSK 팝업을 취소해도 설정 시트는 남는다', (tester) async {
      // #17에서 고친 것과 같은 결함 — `closeAll`은 시트까지 닫는다.
      await _openSettings(tester);

      await _tapInSheet(tester, 'PSK 입력');
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(find.byType(BeaconPskPopupContent), findsNothing);
      expect(find.byType(ClubSettingsSheetContent), findsOneWidget);
    });
  });
}
