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
import 'manual_attendance_popup.dart';
import 'session_form_popup.dart';

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
          onCancel: () => _owned.remove(_owned.take().last),
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
            const _AdminTopBar(),
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
  const _AdminTopBar();

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
          SvgPicture.asset(
            'assets/icons/notification.svg',
            width: 24,
            height: 24,
            colorFilter: ColorFilter.mode(colors.gray3, BlendMode.srcIn),
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
