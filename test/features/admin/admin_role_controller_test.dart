import 'package:beacon_app/core/router/app_router.dart';
import 'package:beacon_app/features/admin/data/club_member_repository.dart';
import 'package:beacon_app/features/admin/presentation/admin_role_controller.dart';
import 'package:beacon_app/features/auth/data/auth_dto.dart';
import 'package:beacon_app/features/auth/presentation/session_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 관리자 탭 노출과 `/admin` 진입이 이 판정 하나에 달려 있다. 틀리는 방향이
/// 둘인데 무게가 다르다 — 관리자에게 탭이 안 보이는 것은 불편이고, **부원
/// 에게 보이는 것은 권한 누출**이다. 그래서 확인되지 않은 모든 상태는
/// false로 수렴해야 한다.
class _StubMemberRepository implements ClubMemberRepository {
  _StubMemberRepository(this._members, {this.throws = false});

  final List<ClubMember> _members;
  final bool throws;
  final List<int> requestedClubIds = [];

  @override
  Future<List<ClubMember>> fetchMembers(int clubId) async {
    requestedClubIds.add(clubId);
    if (throws) throw Exception('조회 실패');
    return _members;
  }
}

class _ReadySessionController extends SessionController {
  _ReadySessionController(this._state);

  final SessionState _state;

  @override
  Future<SessionState> build() async => _state;
}

const _profile = MemberProfile(
  name: '김민준',
  stdId: '20250101',
  clubIds: [7],
  pushEnabled: true,
);

ProviderContainer _container(SessionState session, ClubMemberRepository repo) {
  final container = ProviderContainer(
    overrides: [
      sessionControllerProvider.overrideWith(() => _ReadySessionController(session)),
      clubMemberRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  ClubMember member(String stdId, ClubRole role) =>
      ClubMember(memberId: 1, name: '아무개', stdId: stdId, role: role);

  test('내 학번의 역할이 ADMIN이면 참이다', () async {
    final container = _container(
      const SessionReady(_profile),
      _StubMemberRepository([
        member('99999999', ClubRole.member),
        member('20250101', ClubRole.admin),
      ]),
    );

    expect(await container.read(isClubAdminProvider.future), isTrue);
  });

  test('내 학번의 역할이 MEMBER면 거짓이다', () async {
    // 잡아야 할 잘못된 구현: 목록에 ADMIN이 **한 명이라도** 있으면 참으로
    // 친다 — 동아리에 관리자가 있다는 사실과 내가 관리자인 것은 다르다.
    final container = _container(
      const SessionReady(_profile),
      _StubMemberRepository([
        member('99999999', ClubRole.admin),
        member('20250101', ClubRole.member),
      ]),
    );

    expect(await container.read(isClubAdminProvider.future), isFalse);
  });

  test('목록에 내가 없으면 거짓이다', () async {
    final container = _container(
      const SessionReady(_profile),
      _StubMemberRepository([member('99999999', ClubRole.admin)]),
    );

    expect(await container.read(isClubAdminProvider.future), isFalse);
  });

  test('조회가 실패하면 거짓이다', () async {
    // 잡아야 할 잘못된 구현: 실패를 그대로 던진다 — 그러면 화면이 오류
    // 상태로 굳거나, 반대로 낙관적으로 참을 돌려주면 권한이 샌다.
    final container = _container(
      const SessionReady(_profile),
      _StubMemberRepository(const [], throws: true),
    );

    expect(await container.read(isClubAdminProvider.future), isFalse);
  });

  test('로그인 전에는 조회하지 않고 거짓이다', () async {
    final repo = _StubMemberRepository([member('20250101', ClubRole.admin)]);
    final container = _container(const SessionSignedOut(), repo);

    expect(await container.read(isClubAdminProvider.future), isFalse);
    expect(repo.requestedClubIds, isEmpty, reason: '로그인 전에 멤버 목록을 부르면 401이다');
  });

  test('showAdminTabProvider는 확인되기 전까지 거짓이다', () async {
    // 잡아야 할 잘못된 구현: 로딩 중을 참으로 다룬다 — 부원 화면에 관리자
    // 탭이 잠깐 떴다 사라진다.
    final container = _container(
      const SessionReady(_profile),
      _StubMemberRepository([member('20250101', ClubRole.admin)]),
    );

    expect(container.read(showAdminTabProvider), isFalse, reason: '아직 로딩 중이다');

    await container.read(isClubAdminProvider.future);

    expect(container.read(showAdminTabProvider), isTrue);
  });

  test('전체 인원 수는 멤버 목록의 길이다', () async {
    final container = _container(
      const SessionReady(_profile),
      _StubMemberRepository([
        member('1', ClubRole.admin),
        member('2', ClubRole.member),
        member('3', ClubRole.member),
      ]),
    );

    expect(await container.read(clubMemberCountProvider.future), 3);
  });

  test('인원 조회가 실패하면 null이다 — 틀린 분모를 지어내지 않는다', () async {
    final container = _container(
      const SessionReady(_profile),
      _StubMemberRepository(const [], throws: true),
    );

    expect(await container.read(clubMemberCountProvider.future), isNull);
  });
}
