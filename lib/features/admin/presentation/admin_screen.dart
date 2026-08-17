import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../components/ui/app_logo.dart';
import '../../../components/ui/button.dart';
import '../../../components/ui/owned_routes.dart';
import '../../../components/ui/popup.dart';
import '../../../components/ui/sheet.dart';
import '../../../components/ui/toast.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/presentation/session_controller.dart';
import '../../beacon/data/beacon_config_dto.dart';
import '../../beacon/data/beacon_config_repository.dart';
import '../../club/data/club_settings_repository.dart';
import '../data/attendance_admin_dto.dart';
import '../data/beacon_psk_store.dart';
import '../data/club_member_repository.dart';
import '../data/session_dto.dart';
import '../data/session_repository.dart';
import 'admin_role_controller.dart';
import 'admin_session_card.dart';
import 'attendance_status_popup.dart';
import 'attendance_status_sheet.dart';
import 'beacon_psk_popup.dart';
import 'club_settings_sheet.dart';
import 'manual_attendance_popup.dart';
import 'member_actions_popup.dart';
import 'members_sheet.dart';
import 'session_form_popup.dart';

/// 멤버 검색 입력이 멎은 뒤 요청을 보내기까지 기다리는 시간.
///
/// 타이핑마다 보내면 목록이 계속 깜빡이고 서버에도 부담이다.
@visibleForTesting
const Duration memberSearchDebounce = Duration(milliseconds: 300);

/// 출석 현황 시트가 열려 있는 동안 목록을 다시 조회하는 간격.
///
/// 명세서가 MVP는 SSE가 아니라 **폴링 우선**으로 규정한다(#16). 30초인 이유:
/// 관리자는 부원이 하나씩 찍히는 것을 보고 있으므로 이보다 길면 "안 되는
/// 건가" 싶어지고, 더 짧으면 세션 하나에 요청이 계속 쌓인다.
///
/// **`ACTIVE` 세션에서만 돈다.** 끝난 세션의 출석 기록은 더 바뀌지 않으므로
/// 폴링은 그대로 낭비다.
@visibleForTesting
const Duration attendanceRefreshInterval = Duration(seconds: 30);

/// 관리자 세션 관리 화면(Figma `353:2033` "관리자 페이지").
///
/// 모바일 관리자 화면은 이것 하나뿐이다 — 출석 현황·멤버·설정은 Figma에
/// **웹(1440px)으로만** 그려져 있다(#16·#17·#18).
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  /// 목록 조회의 세대. 클럽이 바뀌거나 탭이 다시 보이면 증가한다 — 홈 화면의
  /// `_bootstrapGeneration`과 같은 이유로, 뒤늦게 도착한 응답이 새 목록을
  /// 덮어쓰지 않게 한다.
  int _generation = 0;

  bool _visible = true;
  int? _loadedClubId;

  List<AdminSession>? _sessions;
  bool _loadFailed = false;

  /// 세션을 **이 화면에서 시작했을 때만** 받는 출석 코드. 시작은 한 번뿐이라
  /// 화면을 다시 열면 서버가 다시 주지 않는다 — 그래서 세션 id에 묶어 둔다.
  final Map<int, String> _otpCodeBySession = {};

  int? _attendeeCount;
  bool _ending = false;
  bool _starting = false;

  late final NavigatorState _rootNavigator;

  /// 이 화면이 루트 내비게이터에 push한 팝업. 숨겨진 동안 push를 거부하는
  /// 것이 이 소유자의 책임이다(#47).
  late final OwnedRoutes _owned = OwnedRoutes(_rootNavigator);

  @override
  void initState() {
    super.initState();
    _rootNavigator = appPopupNavigatorOf(context);
  }

  @override
  void dispose() {
    _generation++;
    _stopAttendancePolling();
    _searchDebounce?.cancel();
    _memberSearch.dispose();
    _membersState.dispose();
    _clubName.dispose();
    _clubDescription.dispose();
    _settingsState.dispose();
    _attendanceState.dispose();
    _owned.closeAll();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible == _visible) return;
    _visible = visible;
    _owned.visible = visible;
    if (!visible) {
      _stopAttendancePolling();
      _attendanceSession = null;
      // 탭을 떠나면 열려 있던 폼을 닫는다 — 남겨 두면 다음 탭 위에 뜬다.
      final routes = _owned.take();
      WidgetsBinding.instance.addPostFrameCallback((_) => _owned.removeAll(routes));
    }
    // 다시 보이는 순간 목록을 새로 읽는다 — 다른 탭에 있는 동안 세션이
    // 시작·종료됐을 수 있다.
    if (visible) {
      final clubId = _loadedClubId;
      if (clubId != null) unawaited(_load(clubId));
    }
  }

  Future<void> _load(int clubId) async {
    final generation = ++_generation;
    try {
      final page = await ref.read(sessionRepositoryProvider).fetchSessions(clubId: clubId);
      if (!_isCurrent(generation)) return;
      setState(() {
        _sessions = page.sessions;
        _loadFailed = false;
      });
      await _refreshAttendeeCount(clubId, generation);
    } catch (_) {
      if (!_isCurrent(generation)) return;
      // 목록을 비운다 — 옛 목록을 남기면 이미 끝난 세션에 "출석 종료하기"가
      // 계속 떠 있다.
      setState(() {
        _sessions = null;
        _loadFailed = true;
      });
    }
  }

  /// 진행 중 세션의 출석 인원만 센다.
  ///
  /// 카드마다 세면 목록 하나에 요청이 N번 나간다 — 서버가 개수를 주는
  /// 엔드포인트를 두지 않아서(`SessionResponseDto`에 인원 필드가 없다)
  /// 진행 중 하나로 제한했다(#14 판정).
  Future<void> _refreshAttendeeCount(int clubId, int generation) async {
    final active = _activeSession;
    if (active == null) {
      if (_isCurrent(generation)) setState(() => _attendeeCount = null);
      return;
    }
    try {
      final count = await ref
          .read(sessionRepositoryProvider)
          .countAttendees(clubId: clubId, sessionId: active.sessionId);
      if (!_isCurrent(generation)) return;
      setState(() => _attendeeCount = count);
    } catch (_) {
      if (!_isCurrent(generation)) return;
      // 세지 못하면 "-"로 둔다 — 0으로 두면 아무도 출석하지 않은 것처럼 보인다.
      setState(() => _attendeeCount = null);
    }
  }

  bool _isCurrent(int generation) => mounted && generation == _generation;

  AdminSession? get _activeSession {
    final sessions = _sessions;
    if (sessions == null) return null;
    for (final session in sessions) {
      if (session.status == SessionStatus.active) return session;
    }
    return null;
  }

  Future<void> _endSession(int clubId, AdminSession session) async {
    if (_ending) return;
    setState(() => _ending = true);
    try {
      await ref.read(sessionRepositoryProvider).end(clubId: clubId, sessionId: session.sessionId);
      if (!mounted) return;
      _otpCodeBySession.remove(session.sessionId);
      await _load(clubId);
    } catch (error) {
      if (!mounted) return;
      showAppToast(context, '세션을 종료하지 못했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _ending = false);
    }
  }

  /// 시작 전에 비콘 PSK가 있는지 확인하고, 없으면 그 자리에서 묻는다.
  ///
  /// PSK는 서버가 주지 않는다 — 펌웨어에 구워진 값과 같아야 GATT 명령이
  /// 받아들여지므로 관리자에게 직접 받아 이 기기에만 저장한다. 관리자 설정
  /// 화면(#18)이 웹 전용이라 갈 곳이 없고, **PSK가 실제로 쓰이는 유일한
  /// 순간**이 여기다.
  /// 멤버 관리 시트의 상태. 시트는 별도 라우트라 이 화면의 `setState`로
  /// 다시 그려지지 않는다.
  final ValueNotifier<({List<ClubMember> members, bool loading, bool failed})> _membersState =
      ValueNotifier((members: const [], loading: false, failed: false));

  final TextEditingController _memberSearch = TextEditingController();

  /// 검색 입력마다 요청을 보내지 않기 위한 디바운스.
  Timer? _searchDebounce;

  /// 설정 시트의 상태. 시트는 별도 라우트 서브트리라 `setState`로는 다시
  /// 그려지지 않는다 — 멤버 시트와 같은 이유로 notifier를 쓴다.
  final ValueNotifier<
    ({
      String? inviteCode,
      BeaconConfig? beacon,
      bool hasPsk,
      bool loading,
      bool failed,
      bool savingClub,
      bool savingBeacon,
      bool workingInvite,
    })
  >
  _settingsState = ValueNotifier((
    inviteCode: null,
    beacon: null,
    hasPsk: false,
    loading: true,
    failed: false,
    savingClub: false,
    savingBeacon: false,
    workingInvite: false,
  ));

  /// 설정 조회·저장의 세대. 시트를 열 때마다 올라간다.
  ///
  /// 세션 목록(`_generation`)·출석 시트(`_attendanceSession`)와 같은 이유다 —
  /// `mounted`만 보면 **시트를 닫았다 다시 연 뒤** 뒤늦게 도착한 응답이
  /// 방금 입력한 값을 조용히 덮어쓴다.
  int _settingsGeneration = 0;

  final TextEditingController _clubName = TextEditingController();
  final TextEditingController _clubDescription = TextEditingController();

  /// 내 `memberId`. 역할 변경 요청의 `requesterId`이고, 자기 자신을 강등·
  /// 제외하지 못하게 막는 기준이다. `GET /members/me`에 `memberId`가 없어
  /// 멤버 목록에서 학번으로 찾는다.
  int? _myMemberId;

  /// 출석 현황 폴링 타이머. 시트가 닫히면 멈춘다.
  Timer? _attendanceTimer;

  /// 열려 있는 출석 현황 시트가 보고 있는 세션과 그 기록.
  ///
  /// 시트 안에서 상태를 바꾸면 목록이 즉시 갱신돼야 한다 — 다시 열게 하면
  /// 관리자가 바뀌었는지 확인할 방법이 없다.
  AdminSession? _attendanceSession;

  /// 시트는 **별도 라우트 서브트리**라 이 화면의 `setState`로는 다시 그려지지
  /// 않는다 — 기록 화면이 세션 상세 시트에 쓰는 것과 같은 방식으로,
  /// 시트가 구독할 수 있는 notifier에 담는다.
  final ValueNotifier<({List<AdminAttendanceRecord> records, bool loading, bool failed})>
  _attendanceState = ValueNotifier((records: const [], loading: false, failed: false));

  /// 멤버 관리를 시트로 연다.
  void _openMembers(int clubId) {
    _membersState.value = (members: const [], loading: true, failed: false);
    _memberSearch.clear();

    _owned.push(
      buildAppSheetRoute<void>(
        context: context,
        navigator: _rootNavigator,
        builder: (_) => ListenableBuilder(
          listenable: _membersState,
          builder: (context, _) {
            final state = _membersState.value;
            return MembersSheetContent(
              members: state.members,
              searchController: _memberSearch,
              isLoading: state.loading,
              loadFailed: state.failed,
              onSearchChanged: (value) => _onMemberSearchChanged(clubId, value),
              onTapMember: (member) => _openMemberActions(clubId, member),
            );
          },
        ),
      ),
    );
    unawaited(_loadMembers(clubId));
  }

  /// 타이핑마다 요청을 보내지 않는다 — 한 글자에 한 번씩 나가면 목록이
  /// 계속 깜빡이고 서버에도 부담이다.
  void _onMemberSearchChanged(int clubId, String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(memberSearchDebounce, () {
      unawaited(_loadMembers(clubId, search: value));
    });
  }

  Future<void> _loadMembers(int clubId, {String? search}) async {
    try {
      final members = await ref
          .read(clubMemberRepositoryProvider)
          .fetchMembers(clubId, search: search);
      if (!mounted) return;
      _myMemberId ??= _findMyMemberId(members);
      // 리포지토리가 준 목록을 그대로 넣지 않고 복사한다. [ValueNotifier]는
      // 값이 **같으면** 알리지 않는데, 레코드 비교는 리스트를 참조로 본다 —
      // 같은 인스턴스를 돌려주는 구현을 만나면 다시 읽어도 화면이 그대로다.
      // 복사본은 매번 다른 인스턴스라 반드시 다시 그려지고, 덤으로 바깥에서
      // 목록을 건드려도 화면 상태가 흔들리지 않는다.
      _membersState.value = (
        members: List<ClubMember>.unmodifiable(members),
        loading: false,
        failed: false,
      );
    } catch (_) {
      if (!mounted) return;
      _membersState.value = (members: const [], loading: false, failed: true);
    }
  }

  /// 목록에서 나를 찾는다 — 학번이 유일한 키다.
  ///
  /// 검색으로 걸러진 목록에는 내가 없을 수 있으므로, 한 번 찾은 뒤에는
  /// 덮어쓰지 않는다(`??=`).
  int? _findMyMemberId(List<ClubMember> members) {
    final session = ref.read(sessionControllerProvider).value;
    if (session is! SessionReady) return null;
    for (final member in members) {
      if (member.stdId == session.profile.stdId) return member.memberId;
    }
    return null;
  }

  void _openMemberActions(int clubId, ClubMember member) {
    _owned.push(
      buildAppPopupRoute<void>(
        context: context,
        navigator: _rootNavigator,
        builder: (_) => MemberActionsPopupContent(
          member: member,
          // 관리자가 스스로를 강등하거나 제외하면 그 동아리에 관리자가
          // 없어질 수 있고, 되돌릴 방법이 앱 안에 없다.
          isSelf: _myMemberId != null && member.memberId == _myMemberId,
          // `closeAll`이 아니다 — 시트와 팝업은 같은 소유 목록에 들어 있어서
          // 팝업만 닫으려던 호출이 그 밑의 시트까지 닫는다.
          onCancel: _owned.closeTop,
          onToggleRole: () => unawaited(_toggleRole(clubId, member)),
          onRemove: () => _confirmRemoveMember(clubId, member),
        ),
      ),
    );
  }

  /// 열려 있는 시트를 그대로 두고 목록만 다시 읽는다.
  ///
  /// 시트를 닫았다 다시 여는 방식(`closeAll` + `_openMembers`)을 쓰지 않는
  /// 이유: 시트가 [ListenableBuilder]로 [_membersState]를 보고 있어 값만
  /// 갈아 끼우면 알아서 다시 그려진다. 닫았다 열면 화면이 한 번 깜빡이고,
  /// 무엇보다 실패했을 때 돌아갈 자리가 사라진다.
  ///
  /// 검색어를 함께 넘긴다 — 안 넘기면 입력칸에는 검색어가 남은 채 목록만
  /// 전체로 돌아가 둘이 어긋난다.
  Future<void> _refreshMembers(int clubId) =>
      _loadMembers(clubId, search: _memberSearch.text);

  Future<void> _toggleRole(int clubId, ClubMember member) async {
    final requesterId = _myMemberId;
    // 팝업만 닫는다. 실패하면 관리자는 시트에서 곧바로 다시 시도할 수 있어야
    // 한다 — 시트까지 닫으면 토스트만 뜨고 목록을 처음부터 다시 연다.
    _owned.closeTop();
    if (requesterId == null) {
      if (mounted && _visible) showAppToast(context, '내 정보를 확인하지 못했습니다.');
      return;
    }
    try {
      await ref.read(clubMemberRepositoryProvider).updateRole(
        clubId: clubId,
        requesterId: requesterId,
        targetMemberId: member.memberId,
        newRole: member.role == ClubRole.admin ? ClubRole.member : ClubRole.admin,
      );
      if (!mounted) return;
      await _refreshMembers(clubId);
    } catch (_) {
      if (!mounted || !_visible) return;
      showAppToast(context, '역할을 바꾸지 못했습니다.');
    }
  }

  void _confirmRemoveMember(int clubId, ClubMember member) {
    // 액션 팝업만 걷어내고 확인 팝업을 시트 위에 얹는다.
    _owned.closeTop();

    // `isSelf`는 `_myMemberId`가 아직 null이면 무조건 false가 되어 자기 행에도
    // 제외 버튼이 그대로 보인다. 누가 나인지 모르는 채로 되돌릴 수 없는 삭제를
    // 보내지 않는다 — [_toggleRole]이 `requesterId == null`에서 하는 것과 같다.
    if (_myMemberId == null) {
      if (mounted && _visible) showAppToast(context, '내 정보를 확인하지 못했습니다.');
      return;
    }

    _owned.push(
      buildAppPopupRoute<void>(
        context: context,
        navigator: _rootNavigator,
        builder: (_) => MemberRemoveConfirmContent(
          member: member,
          onCancel: _owned.closeTop,
          onConfirm: () async {
            _owned.closeTop();
            try {
              await ref
                  .read(clubMemberRepositoryProvider)
                  .removeMember(clubId: clubId, memberId: member.memberId);
              if (!mounted) return;
              await _refreshMembers(clubId);
            } catch (_) {
              if (!mounted || !_visible) return;
              showAppToast(context, '멤버를 제외하지 못했습니다.');
            }
          },
        ),
      ),
    );
  }

  /// 세션의 출석 현황을 시트로 연다.
  ///
  /// 화면이 아니라 시트인 이유: 라우터의 `readyAllowedLocations`가 정확
  /// 일치로 판정해서 `/admin/sessions/:id/attendance` 같은 파라미터 경로를
  /// 그대로 받지 못한다. 기록 화면이 세션 상세에 쓰는 시트 패턴을 따랐다.
  void _openAttendance(int clubId, AdminSession session) {
    _attendanceSession = session;
    _attendanceState.value = (records: const [], loading: true, failed: false);
    _startAttendancePolling(clubId, session);

    _owned.push(
      buildAppSheetRoute<void>(
        context: context,
        navigator: _rootNavigator,
        builder: (_) => ListenableBuilder(
          listenable: _attendanceState,
          builder: (context, _) {
            final state = _attendanceState.value;
            return AttendanceStatusSheetContent(
              sessionName: session.sessionName,
              records: state.records,
              isLoading: state.loading,
              loadFailed: state.failed,
              onTapRecord: (record) => _openStatusChange(clubId, session, record),
              onAddManual: () => _openManualAttendance(clubId, session),
            );
          },
        ),
      ),
    );
    unawaited(_loadAttendance(clubId, session));
  }

  /// `ACTIVE` 세션에 대해서만 폴링을 건다.
  void _startAttendancePolling(int clubId, AdminSession session) {
    _stopAttendancePolling();
    if (session.status != SessionStatus.active) return;
    _attendanceTimer = Timer.periodic(attendanceRefreshInterval, (_) {
      // 시트가 닫혔거나 다른 세션으로 바뀌었으면 멈춘다.
      if (!mounted || _attendanceSession?.sessionId != session.sessionId) {
        _stopAttendancePolling();
        return;
      }
      unawaited(_loadAttendance(clubId, session, silent: true));
    });
  }

  void _stopAttendancePolling() {
    _attendanceTimer?.cancel();
    _attendanceTimer = null;
  }

  /// [silent]면 로딩 표시로 되돌리지 않는다 — 폴링 때마다 목록이 스피너로
  /// 깜빡이면 관리자가 읽고 있던 줄을 놓친다.
  Future<void> _loadAttendance(
    int clubId,
    AdminSession session, {
    bool silent = false,
  }) async {
    try {
      final records = await ref
          .read(sessionRepositoryProvider)
          .fetchAttendance(clubId: clubId, sessionId: session.sessionId);
      if (!mounted || _attendanceSession?.sessionId != session.sessionId) return;
      _attendanceState.value = (records: records, loading: false, failed: false);
    } catch (_) {
      if (!mounted || _attendanceSession?.sessionId != session.sessionId) return;
      // 폴링 중 일시적 실패로 이미 보고 있던 목록을 지우지 않는다 — 다음
      // 주기에 회복한다.
      if (silent) return;
      _attendanceState.value = (records: const [], loading: false, failed: true);
    }
  }

  /// 아직 기록이 없는 부원만 골라 손으로 출석 처리한다.
  Future<void> _openManualAttendance(int clubId, AdminSession session) async {
    List<ClubMember> members;
    try {
      members = await ref.read(clubMemberRepositoryProvider).fetchMembers(clubId);
    } catch (_) {
      if (!mounted || !_visible) return;
      showAppToast(context, '부원 목록을 불러오지 못했습니다.');
      return;
    }
    if (!mounted) return;

    // 이미 기록이 있는 부원은 후보에서 뺀다 — 그건 상태 변경으로 할 일이고,
    // 여기서 또 넣으면 서버가 중복으로 거절하거나 기존 기록을 덮어쓴다.
    final recorded = _attendanceState.value.records.map((record) => record.memberId).toSet();
    final candidates = members.where((member) => !recorded.contains(member.memberId)).toList();

    _owned.push(
      buildAppPopupRoute<void>(
        context: context,
        navigator: _rootNavigator,
        builder: (_) => ManualAttendancePopupContent(
          candidates: candidates,
          onCancel: _owned.closeAll,
          onSubmit: (memberId, status) async {
            await ref.read(sessionRepositoryProvider).addManualAttendance(
              clubId: clubId,
              sessionId: session.sessionId,
              memberId: memberId,
              status: status,
            );
            if (!mounted) return;
            _owned.closeAll();
            _openAttendance(clubId, session);
          },
        ),
      ),
    );
  }

  void _openStatusChange(int clubId, AdminSession session, AdminAttendanceRecord record) {
    _owned.push(
      buildAppPopupRoute<void>(
        context: context,
        navigator: _rootNavigator,
        builder: (_) => AttendanceStatusPopupContent(
          record: record,
          // `remove(take().last)`가 아니다 — `take()`가 추적을 통째로 비워서
          // 밑의 출석 시트가 주인 없는 라우트가 되고, 탭을 떠날 때 아무도
          // 그걸 닫지 않아 다음 화면 위에 남는다(#41과 같은 결함).
          onCancel: _owned.closeTop,
          onSubmit: (status, note) async {
            await ref.read(sessionRepositoryProvider).updateAttendanceStatus(
              clubId: clubId,
              sessionId: session.sessionId,
              recordId: record.recordId,
              status: status,
              adminNote: note,
            );
            if (!mounted) return;
            _owned.closeAll();
            // 시트를 다시 열어 갱신된 목록을 보여준다 — 닫아 버리면 관리자가
            // 바뀌었는지 확인할 방법이 없다.
            _openAttendance(clubId, session);
          },
        ),
      ),
    );
  }


  // ---- 설정 -------------------------------------------------------------

  void _openSettings(int clubId) {
    final generation = ++_settingsGeneration;
    _settingsState.value = (
      inviteCode: null,
      beacon: null,
      hasPsk: false,
      loading: true,
      failed: false,
      savingClub: false,
      savingBeacon: false,
      workingInvite: false,
    );

    _owned.push(
      buildAppSheetRoute<void>(
        context: context,
        navigator: _rootNavigator,
        builder: (_) => ListenableBuilder(
          listenable: _settingsState,
          builder: (context, _) {
            final state = _settingsState.value;
            return ClubSettingsSheetContent(
              clubName: _clubName,
              clubDescription: _clubDescription,
              inviteCode: state.inviteCode,
              beacon: state.beacon,
              hasPsk: state.hasPsk,
              isLoading: state.loading,
              loadFailed: state.failed,
              savingClub: state.savingClub,
              savingBeacon: state.savingBeacon,
              workingInviteCode: state.workingInvite,
              onSaveClub: () => unawaited(_saveClub(clubId)),
              onIssueInviteCode: () => unawaited(_issueInviteCode(clubId)),
              onRevokeInviteCode: () => unawaited(_revokeInviteCode(clubId)),
              onSaveBeacon: (config) => unawaited(_saveBeacon(clubId, config)),
              onEditPsk: _openPskEditor,
            );
          },
        ),
      ),
    );
    unawaited(_loadSettings(clubId, generation));
  }

  /// 동아리·초대코드·비콘·PSK를 한 번에 읽는다.
  ///
  /// 초대코드만 실패해도 화면 전체를 못 쓰게 만들지는 않는다 — 코드가 없는
  /// 것과 못 읽은 것은 리포지토리가 이미 구분해 준다. 반대로 동아리 정보나
  /// 비콘 설정을 못 읽으면 편집할 대상이 없으므로 실패로 다룬다.
  Future<void> _loadSettings(int clubId, int generation) async {
    try {
      final results = await Future.wait([
        ref.read(clubSettingsRepositoryProvider).fetchClub(clubId),
        ref.read(beaconConfigRepositoryProvider).fetch(clubId),
      ]);
      if (!_isCurrentSettings(generation)) return;

      final club = results[0] as ClubDetail;
      final beacon = results[1] as BeaconConfig;
      _clubName.text = club.clubName;
      _clubDescription.text = club.clubDescription ?? '';

      final code = await _readInviteCode(clubId);
      final hasPsk = await _readHasPsk();
      if (!_isCurrentSettings(generation)) return;

      _settingsState.value = (
        inviteCode: code,
        beacon: beacon,
        hasPsk: hasPsk,
        loading: false,
        failed: false,
        savingClub: false,
        savingBeacon: false,
        workingInvite: false,
      );
    } catch (_) {
      if (!_isCurrentSettings(generation)) return;
      _settingsState.value = (
        inviteCode: null,
        beacon: null,
        hasPsk: false,
        loading: false,
        failed: true,
        savingClub: false,
        savingBeacon: false,
        workingInvite: false,
      );
    }
  }

  /// 이 화면이 보일 때만 토스트를 띄운다.
  ///
  /// `showAppToast(context, ...)`를 await 뒤에서 직접 부르면 분석기가
  /// `_isCurrentSettings` 안의 `mounted` 검사를 꿰뚫어 보지 못해
  /// `use_build_context_synchronously`로 경고한다. 검사와 사용을 한 곳에
  /// 붙여 두면 그 경고가 정당하게 사라진다.
  void _settingsToast(String message) {
    if (!mounted || !_visible) return;
    showAppToast(context, message);
  }

  /// 이 응답이 아직 최신인지. 시트를 닫았다 다시 열면 세대가 올라가므로,
  /// 그 전에 띄운 요청의 결과는 여기서 버려진다.
  bool _isCurrentSettings(int generation) =>
      mounted && generation == _settingsGeneration;

  /// 초대코드를 못 읽는 것은 설정 화면 전체를 막을 이유가 아니다.
  Future<String?> _readInviteCode(int clubId) async {
    try {
      return await ref.read(clubSettingsRepositoryProvider).fetchInviteCode(clubId);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _readHasPsk() async {
    try {
      final psk = await ref.read(beaconPskStoreProvider).read();
      return psk != null && isValidBeaconPsk(psk);
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveClub(int clubId) async {
    final generation = _settingsGeneration;
    final name = _clubName.text.trim();
    if (name.isEmpty) {
      _settingsToast('동아리명을 입력해주세요.');
      return;
    }
    if (_settingsState.value.savingClub) return;
    _settingsState.value = (
      inviteCode: _settingsState.value.inviteCode,
      beacon: _settingsState.value.beacon,
      hasPsk: _settingsState.value.hasPsk,
      loading: false,
      failed: false,
      savingClub: true,
      savingBeacon: _settingsState.value.savingBeacon,
      workingInvite: _settingsState.value.workingInvite,
    );

    try {
      await ref.read(clubSettingsRepositoryProvider).updateClub(
        clubId: clubId,
        clubName: name,
        clubDescription: _clubDescription.text.trim(),
      );
      // 응답이 수정된 동아리가 아니라 문자열이라, 무엇이 저장됐는지는
      // 다시 읽어야만 알 수 있다.
      final club = await ref.read(clubSettingsRepositoryProvider).fetchClub(clubId);
      if (!_isCurrentSettings(generation)) return;
      _clubName.text = club.clubName;
      _clubDescription.text = club.clubDescription ?? '';
      _setSettings(savingClub: false);
      _settingsToast('동아리 정보를 저장했습니다.');
    } catch (_) {
      if (!_isCurrentSettings(generation)) return;
      _setSettings(savingClub: false);
      _settingsToast('동아리 정보를 저장하지 못했습니다.');
    }
  }

  Future<void> _issueInviteCode(int clubId) async {
    final generation = _settingsGeneration;
    if (_settingsState.value.workingInvite) return;
    _setSettings(workingInvite: true);
    try {
      final code = await ref.read(clubSettingsRepositoryProvider).issueInviteCode(clubId);
      if (!_isCurrentSettings(generation)) return;
      _setSettings(workingInvite: false, inviteCode: code, hasInviteCode: true);
    } catch (_) {
      if (!_isCurrentSettings(generation)) return;
      _setSettings(workingInvite: false);
      _settingsToast('초대코드를 발급하지 못했습니다.');
    }
  }

  Future<void> _revokeInviteCode(int clubId) async {
    final generation = _settingsGeneration;
    if (_settingsState.value.workingInvite) return;
    _setSettings(workingInvite: true);
    try {
      await ref.read(clubSettingsRepositoryProvider).revokeInviteCode(clubId);
      if (!_isCurrentSettings(generation)) return;
      _setSettings(workingInvite: false, inviteCode: null, hasInviteCode: true);
    } catch (_) {
      if (!_isCurrentSettings(generation)) return;
      _setSettings(workingInvite: false);
      _settingsToast('초대코드를 무효화하지 못했습니다.');
    }
  }

  Future<void> _saveBeacon(int clubId, BeaconConfig config) async {
    final generation = _settingsGeneration;
    if (_settingsState.value.savingBeacon) return;
    _setSettings(savingBeacon: true);
    try {
      final saved = await ref.read(beaconConfigRepositoryProvider).update(clubId, config);
      if (!_isCurrentSettings(generation)) return;
      // 서버가 다듬은 값이 있으면 그게 화면에 반영돼야 한다.
      _setSettings(savingBeacon: false, beacon: saved, hasBeacon: true);
      _settingsToast('비콘 설정을 저장했습니다.');
    } catch (_) {
      if (!_isCurrentSettings(generation)) return;
      _setSettings(savingBeacon: false);
      _settingsToast('비콘 설정을 저장하지 못했습니다.');
    }
  }

  /// 설정 상태를 부분 갱신한다.
  ///
  /// `inviteCode`/`beacon`은 **null 자체가 의미 있는 값**이라(코드 없음,
  /// 아직 못 읽음) `??`로는 "안 바꿈"과 구별할 수 없다. 바꿀 때만 짝이 되는
  /// `hasInviteCode`/`hasBeacon`을 함께 켠다.
  void _setSettings({
    bool? savingClub,
    bool? savingBeacon,
    bool? workingInvite,
    bool hasInviteCode = false,
    String? inviteCode,
    bool hasBeacon = false,
    BeaconConfig? beacon,
    bool? hasPsk,
  }) {
    final now = _settingsState.value;
    _settingsState.value = (
      inviteCode: hasInviteCode ? inviteCode : now.inviteCode,
      beacon: hasBeacon ? beacon : now.beacon,
      hasPsk: hasPsk ?? now.hasPsk,
      loading: now.loading,
      failed: now.failed,
      savingClub: savingClub ?? now.savingClub,
      savingBeacon: savingBeacon ?? now.savingBeacon,
      workingInvite: workingInvite ?? now.workingInvite,
    );
  }

  /// 설정에서 PSK를 다시 입력받는다. 세션 시작 흐름([_ensurePsk])과 달리
  /// 저장만 하고 아무것도 시작하지 않는다.
  void _openPskEditor() {
    final store = ref.read(beaconPskStoreProvider);
    _owned.push(
      buildAppPopupRoute<void>(
        context: context,
        navigator: _rootNavigator,
        builder: (_) => BeaconPskPopupContent(
          submitLabel: '저장',
          onCancel: _owned.closeTop,
          onSubmit: (psk) async {
            _owned.closeTop();
            try {
              await store.save(psk);
            } catch (_) {
              _settingsToast('PSK를 저장하지 못했습니다.');
              return;
            }
            if (!mounted) return;
            _setSettings(hasPsk: true);
            _settingsToast('PSK를 저장했습니다.');
          },
        ),
      ),
    );
  }

  Future<void> _ensurePsk(int clubId, AdminSession session) async {
    final store = ref.read(beaconPskStoreProvider);
    String? existing;
    try {
      existing = await store.read();
    } catch (_) {
      existing = null;
    }
    if (!mounted) return;

    if (existing != null && isValidBeaconPsk(existing)) {
      await _startSession(clubId, session);
      return;
    }

    _owned.push(
      buildAppPopupRoute<void>(
        context: context,
        navigator: _rootNavigator,
        builder: (_) => BeaconPskPopupContent(
          initial: existing,
          onCancel: _owned.closeAll,
          onSubmit: (psk) async {
            _owned.closeAll();
            try {
              await store.save(psk);
            } catch (_) {
              // 검증은 팝업이 이미 했다 — 저장 자체가 실패하면(보안 저장소
              // 오류) 시작은 계속 진행한다. PSK 없이도 서버 세션은 열린다.
            }
            if (!mounted) return;
            await _startSession(clubId, session);
          },
        ),
      ),
    );
  }

  /// 세션을 시작하고 출석 코드를 받아 둔다.
  ///
  /// 응답의 `uuid`는 #15의 GATT 명령 페이로드가 쓴다 — BLE 전송이 아직
  /// 없어서 지금은 코드만 화면에 띄운다.
  Future<void> _startSession(int clubId, AdminSession session) async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final result = await ref
          .read(sessionRepositoryProvider)
          .start(clubId: clubId, sessionId: session.sessionId);
      if (!mounted) return;
      _otpCodeBySession[session.sessionId] = result.otpCode;
      await _load(clubId);
    } catch (_) {
      if (!mounted || !_visible) return;
      showAppToast(context, '세션을 시작하지 못했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _openForm(int clubId, {AdminSession? initial}) {
    _owned.push(
      buildAppPopupRoute<void>(
        context: context,
        navigator: _rootNavigator,
        builder: (context) => SessionFormPopupContent(
          initial: initial,
          onCancel: _owned.closeAll,
          onSubmit: (draft) async {
            final repository = ref.read(sessionRepositoryProvider);
            if (initial == null) {
              await repository.create(clubId: clubId, draft: draft);
            } else {
              await repository.update(
                clubId: clubId,
                sessionId: initial.sessionId,
                draft: draft,
              );
            }
            if (!mounted) return;
            _owned.closeAll();
            await _load(clubId);
          },
        ),
      ),
    );
  }

  /// 이미 만들어진 세션의 수정·삭제. Figma에 이 진입점이 없어(모바일
  /// 디자인은 목록 하나뿐이다) 카드 탭으로 열도록 했다(#14에 기록).
  void _openActions(int clubId, AdminSession session) {
    _owned.push(
      buildAppPopupRoute<void>(
        context: context,
        navigator: _rootNavigator,
        builder: (context) => _SessionActionsContent(
          sessionName: session.sessionName,
          onAttendance: () {
            _owned.closeAll();
            _openAttendance(clubId, session);
          },
          onEdit: () {
            _owned.closeAll();
            _openForm(clubId, initial: session);
          },
          onDelete: () async {
            _owned.closeAll();
            await _confirmDelete(clubId, session);
          },
          onCancel: _owned.closeAll,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(int clubId, AdminSession session) async {
    _owned.push(
      buildAppPopupRoute<void>(
        context: context,
        navigator: _rootNavigator,
        // 팝업 빌더의 context를 가리면 아래 콜백의 `context`가 이미 닫힌
        // 팝업의 것이 된다 — 토스트는 이 화면(State)의 context로 띄운다.
        builder: (_) => _DeleteConfirmContent(
          sessionName: session.sessionName,
          onCancel: _owned.closeAll,
          onConfirm: () async {
            _owned.closeAll();
            try {
              await ref
                  .read(sessionRepositoryProvider)
                  .delete(clubId: clubId, sessionId: session.sessionId);
              if (!mounted) return;
              await _load(clubId);
            } catch (_) {
              if (!mounted || !_visible) return;
              showAppToast(context, '세션을 삭제하지 못했습니다.');
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    final session = ref.watch(sessionControllerProvider).value;
    final clubId = session is SessionReady ? session.profile.clubIds.firstOrNull : null;

    if (clubId != null && _loadedClubId != clubId) {
      _loadedClubId = clubId;
      // build 중에는 setState를 부를 수 없으므로 조회는 프레임 뒤로 미룬다.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_load(clubId));
      });
    }

    final memberCount = ref.watch(clubMemberCountProvider).value;
    final sessions = _sessions;

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 62 - 47),
            _AdminTopBar(
              onMembers: clubId == null ? null : () => _openMembers(clubId),
              onSettings: clubId == null ? null : () => _openSettings(clubId),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: sessions == null
                  ? Center(
                      child: _loadFailed
                          ? Text(
                              '세션을 불러오지 못했습니다',
                              style: typography.body2.copyWith(color: colors.gray2),
                            )
                          : const CircularProgressIndicator(),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 10, 24, 110),
                      itemCount: sessions.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = sessions[index];
                        if (item.status == SessionStatus.active) {
                          return ActiveSessionCard(
                            session: item,
                            otpCode: _otpCodeBySession[item.sessionId],
                            attendeeCount: _attendeeCount,
                            memberCount: memberCount,
                            isEnding: _ending,
                            onEnd: clubId == null
                                ? () {}
                                : () => unawaited(_endSession(clubId, item)),
                            onTap: clubId == null ? () {} : () => _openActions(clubId, item),
                          );
                        }
                        return EndedSessionCard(
                          session: item,
                          onTap: clubId == null ? () {} : () => _openActions(clubId, item),
                          onStart: item.status == SessionStatus.scheduled && clubId != null
                              ? () => unawaited(_ensurePsk(clubId, item))
                              : null,
                          isStarting: _starting,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: clubId == null
          ? null
          : _CreateSessionButton(
              key: const ValueKey('admin_create_session'),
              onPressed: () => _openForm(clubId),
            ),
    );
  }
}

class _AdminTopBar extends StatelessWidget {
  const _AdminTopBar({this.onMembers, this.onSettings});

  /// 멤버 관리 진입점. Figma 모바일 관리자 화면(`353:2033`)에는 이 자리에
  /// 알림 벨만 있고 멤버 관리로 가는 길이 없다 — 웹에만 있는 화면이라
  /// 모바일 진입점을 새로 만들어야 했다(#17).
  final VoidCallback? onMembers;

  /// 설정 진입점. 멤버 관리와 같은 사정이다 — 웹에만 있는 화면이라
  /// (`356:2127`) 모바일 진입점을 새로 만들어야 했다(#18).
  final VoidCallback? onSettings;

  /// 세션을 시작하고 출석 코드를 받아 둔다.
  ///
  /// 응답의 `uuid`는 #15의 GATT 명령 페이로드가 쓴다 — BLE 전송이 아직
  /// 없어서 지금은 코드만 화면에 띄운다.
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const AppLogo(),
          Text(
            '관리자',
            // 실측(`I356:1469;340:1908`)은 18px인데 AppTypography에 18px
            // 토큰이 없다 — 상단 바는 세 화면이 공유하므로 기존 토큰
            // (title4=20)을 쓰지 않고 body2를 키워 맞추면 오히려 어긋난다.
            // 가장 가까운 title4로 두고 리포트에 남긴다.
            style: typography.title4.copyWith(color: colors.gray3),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: onMembers,
                behavior: HitTestBehavior.opaque,
                child: Text(
                  '멤버',
                  style: typography.body2.copyWith(color: colors.gray3),
                ),
              ),
              const SizedBox(width: 14),
              GestureDetector(
                onTap: onSettings,
                behavior: HitTestBehavior.opaque,
                child: Text(
                  '설정',
                  style: typography.body2.copyWith(color: colors.gray3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CreateSessionButton extends StatelessWidget {
  const _CreateSessionButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  /// 세션을 시작하고 출석 코드를 받아 둔다.
  ///
  /// 응답의 `uuid`는 #15의 GATT 명령 페이로드가 쓴다 — BLE 전송이 아직
  /// 없어서 지금은 코드만 화면에 띄운다.
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 64,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.main,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            // 실측(`353:2119`): 2px 10px 12px 1px rgba(84,162,234,0.2).
            BoxShadow(
              color: colors.main.withValues(alpha: 0.2),
              offset: const Offset(2, 10),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: SvgPicture.asset(
          'assets/icons/add-large-fill.svg',
          width: 24,
          height: 24,
          colorFilter: ColorFilter.mode(colors.bg, BlendMode.srcIn),
        ),
      ),
    );
  }
}

/// 세션 카드를 눌렀을 때의 수정·삭제 선택. Figma에 이 진입점이 없어
/// 다른 팝업들과 같은 구성(제목 + 세로 버튼)으로 맞췄다.
class _SessionActionsContent extends StatelessWidget {
  const _SessionActionsContent({
    required this.sessionName,
    required this.onAttendance,
    required this.onEdit,
    required this.onDelete,
    required this.onCancel,
  });

  final String sessionName;
  final VoidCallback onAttendance;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          sessionName,
          textAlign: TextAlign.center,
          style: typography.title4.copyWith(color: colors.gray3),
        ),
        const SizedBox(height: 24),
        AppButton(label: '출석 현황', size: ButtonSize.md, onPressed: onAttendance),
        const SizedBox(height: 12),
        AppButton(label: '수정하기', size: ButtonSize.md, onPressed: onEdit),
        const SizedBox(height: 12),
        AppButton.destructive(label: '삭제하기', size: ButtonSize.md, onPressed: onDelete),
        const SizedBox(height: 12),
        AppButton.cancel(label: '취소', size: ButtonSize.md, onPressed: onCancel),
      ],
    );
  }
}

/// 삭제 확인. 확인 없이 지우면 되돌릴 방법이 없다.
class _DeleteConfirmContent extends StatelessWidget {
  const _DeleteConfirmContent({
    required this.sessionName,
    required this.onConfirm,
    required this.onCancel,
  });

  final String sessionName;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '세션 삭제',
          textAlign: TextAlign.center,
          style: typography.title4.copyWith(color: colors.gray3),
        ),
        const SizedBox(height: 12),
        Text(
          '$sessionName을(를) 삭제할까요?\n삭제한 세션은 되돌릴 수 없습니다.',
          textAlign: TextAlign.center,
          style: typography.body3.copyWith(color: colors.gray2),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: AppButton.cancel(label: '취소', size: ButtonSize.md, onPressed: onCancel),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppButton.destructive(
                label: '삭제',
                size: ButtonSize.md,
                onPressed: onConfirm,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
