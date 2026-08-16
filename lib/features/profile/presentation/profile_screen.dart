import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../components/ui/app_switch.dart';
import '../../../components/ui/button.dart';
import '../../../components/ui/card.dart';
import '../../../components/ui/input.dart';
import '../../../components/ui/popup.dart';
import '../../../components/ui/toast.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/data/auth_dto.dart';
import '../../auth/presentation/auth_form_validator.dart';
import '../../auth/presentation/session_controller.dart';
import '../data/profile_repository.dart';
import 'password_change_popup.dart';

/// 마이페이지(이슈 #13, Figma `353:1542` "마이 페이지").
///
/// 위에서부터 프로필(아바타·이름·학번), 리스트 카드 2장(알림 허용 토글 /
/// 비밀번호 변경), 그리고 아래에 붙는 로그아웃 버튼이다. 상단 바·하단 탭
/// 바는 `AppShell`이 그린다.
///
/// 같은 프레임의 변형인 `405:2244`는 구조가 완전히 같고 `변경 알림`
/// (`405:2325`, "비밀번호가 변경되었어요") 토스트 하나만 더 떠 있다 —
/// 비밀번호 변경 **직후**의 마이페이지다. 즉 비밀번호 변경의 성공 지점은
/// 별도 화면이 아니라 이 화면 위이고, 그것이 비밀번호 변경을 팝업으로
/// 구현한 근거 중 하나다(`password_change_popup.dart` 주석 참고).
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  /// 마이 탭이 지금 실제로 사용자에게 보이는지.
  ///
  /// `StatefulShellRoute.indexedStack`은 선택되지 않은 브랜치를 dispose하지
  /// 않고 `Offstage` + `TickerMode(enabled: false)`로 감싼 채 살려 둔다 —
  /// 그래서 이 화면이 띄운 팝업은 탭을 옮겨도 저절로 닫히지 않고 다음 탭
  /// 위에 그대로 남는다. 근거는 `home_screen.dart`의 `_visible` 주석에
  /// 자세히 적혀 있다.
  bool _visible = true;

  /// 이 화면이 루트 내비게이터에 push한 팝업 라우트. 한 번에 하나만 뜬다
  /// (이름 변경 / 비밀번호 변경 / 로그아웃 확인).
  ///
  /// `Navigator.pop()`이 아니라 라우트 객체를 들고 있는 이유: pop은 "스택
  /// 맨 위"를 닫을 뿐 정체성을 모르므로, 우리 팝업 위에 다른 루트 라우트가
  /// 얹혀 있으면 엉뚱한 것을 닫는다(`records_screen.dart`와 같은 이유).
  Route<void>? _popupRoute;

  /// 진행 중인 알림 토글 요청의 세대. `dispose()` 이후에 도착하는 응답을
  /// 무효화하는 용도로 남는다.
  int _pushGeneration = 0;

  /// **서버가 마지막으로 확인해 준** 알림 값. 실패 시 되돌릴 기준이다.
  ///
  /// 눌린 시점의 `profile.pushEnabled`를 붙잡아 두면 안 된다 — 앞선 토글이
  /// 이미 낙관적으로 써 넣은 값이라 "되돌리기"가 확인되지 않은 값으로
  /// 되돌아간다. 실제로 토글을 두 번 눌러 **둘 다 실패**하면 화면은 ON,
  /// 서버는 OFF로 갈라졌다(리뷰 Critical 1).
  bool? _confirmedPushEnabled;

  /// 사용자가 가장 최근에 원한 알림 값. 요청이 떠 있는 동안 눌린 값을 여기
  /// 모아 두었다가 순서대로 하나씩 보낸다.
  bool? _desiredPushEnabled;

  /// 알림 토글 요청이 떠 있는지. **쓰기를 직렬화하는 것이 핵심이다** —
  /// 세대 검사는 늦게 도착한 *응답*만 버릴 뿐 서버 도착 순서를 정하지
  /// 못한다. 켜기·끄기를 연달아 보내면 뒤에 보낸 요청이 서버에 먼저 닿아
  /// 서버는 ON, 화면은 OFF로 끝날 수 있다(리뷰 Critical 1의 역순 성공).
  bool _pushInFlight = false;

  /// `dispose()` 시점에는 이 화면의 엘리먼트가 트리에서 빠지는 중이라
  /// `Navigator.of(context)`를 신뢰할 수 없다 — 미리 잡아 둔다. 팝업은 루트
  /// 내비게이터(=`AppShell` 바깥)에 붙어 있어 이 화면과 독립적으로
  /// 살아남으므로, 명시적으로 닫지 않으면 다음 화면 위로 샌다.
  late final NavigatorState _rootNavigator;

  @override
  void initState() {
    super.initState();
    _rootNavigator = appPopupNavigatorOf(context);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible == _visible) return;
    _visible = visible;
    if (!visible) _detachPopup();
  }

  @override
  void dispose() {
    // 이 시점 이후에 도착하는 토글 응답을 전부 무효화한다.
    _pushGeneration++;
    // 여기서는 프레임 뒤로 미룰 수 없다 — 이 State는 곧 사라지고, 미뤄 둔
    // 콜백이 돌 때쯤이면 팝업을 닫을 주체가 아무도 없다.
    _closePopup();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // 팝업 라우트 소유
  // ---------------------------------------------------------------------

  void _openPopup(WidgetBuilder builder) {
    // 두 팝업이 겹쳐 쌓이는 일은 없어야 한다.
    _closePopup();
    final route = buildAppPopupRoute<void>(
      context: context,
      navigator: _rootNavigator,
      builder: builder,
    );
    _popupRoute = route;
    unawaited(
      _rootNavigator.push<void>(route).then((_) {
        // 이미 다른 팝업으로 바뀐 뒤에 도착한 옛 팝업의 완료가 현재 추적을
        // 지우지 않도록 정체성으로 판정한다.
        if (identical(_popupRoute, route)) _popupRoute = null;
      }),
    );
  }

  Route<void>? _takePopup() {
    final route = _popupRoute;
    _popupRoute = null;
    return route;
  }

  void _removePopupRoute(Route<void>? route) {
    if (route != null && route.isActive) _rootNavigator.removeRoute(route);
  }

  /// 지금 당장 닫는다. `dispose()`와 비동기 완료 지점에서 쓴다.
  void _closePopup() => _removePopupRoute(_takePopup());

  /// 추적만 지금 끊고 실제 제거는 이 프레임이 끝난 뒤로 미룬다.
  /// `didChangeDependencies()`는 빌드 단계라 내비게이션을 할 수 없다.
  void _detachPopup() {
    final route = _takePopup();
    if (route == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _removePopupRoute(route));
  }

  // ---------------------------------------------------------------------
  // 동작
  // ---------------------------------------------------------------------

  /// 알림 토글. 낙관적으로 먼저 반영하고, 서버가 거절하면 **서버가 마지막으로
  /// 확인해 준 값으로** 되돌린 뒤 토스트로 알린다(요구사항 3).
  ///
  /// 요청은 [_drainPushQueue]가 **한 번에 하나씩** 보낸다. 겹쳐 보내면
  /// 서버 도착 순서를 우리가 정할 수 없어, 응답을 아무리 잘 걸러도 서버와
  /// 화면이 갈라진다.
  void _onPushToggled(MemberProfile profile, bool next) {
    _confirmedPushEnabled ??= profile.pushEnabled;
    if (next == _desiredPushEnabled ||
        (_desiredPushEnabled == null && next == _confirmedPushEnabled)) {
      return;
    }

    _desiredPushEnabled = next;
    ref.read(sessionControllerProvider.notifier).applyProfileChange(pushEnabled: next);
    unawaited(_drainPushQueue());
  }

  /// 원하는 값과 확인된 값이 같아질 때까지 순차 전송한다. 중간에 여러 번
  /// 눌린 값은 [_desiredPushEnabled] 하나로 합쳐지므로, 세 번 눌러도 서버로
  /// 나가는 요청은 최대 두 번이다.
  Future<void> _drainPushQueue() async {
    if (_pushInFlight) return;
    _pushInFlight = true;
    final generation = _pushGeneration;
    try {
      while (true) {
        final target = _desiredPushEnabled;
        if (target == null || target == _confirmedPushEnabled) return;

        try {
          // `name`은 `PATCH /members/me`의 **필수** 필드다. 붙잡아 둔 값이
          // 아니라 **보내는 시점**의 세션에서 읽는다 — 토글이 떠 있는 동안
          // 이름이 바뀌면, 붙잡아 둔 옛 이름이 서버의 이름을 되돌린다
          // (리뷰 Important 3).
          await ref.read(profileRepositoryProvider).updateProfile(
                name: _currentName() ?? '',
                pushEnabled: target,
              );
        } catch (error) {
          // `ApiException`만 잡으면 그 밖의 예외가 새어 낙관적 값이 적용된
          // 채로 남고 처리되지 않은 비동기 오류가 된다 — 홈 화면이 이미
          // 같은 지적을 받아 고쳤다(리뷰 Important 4).
          if (!mounted || generation != _pushGeneration) return;
          final confirmed = _confirmedPushEnabled;
          final desired = _desiredPushEnabled;
          _desiredPushEnabled = null;
          if (confirmed != null) {
            ref
                .read(sessionControllerProvider.notifier)
                .applyProfileChange(pushEnabled: confirmed);
          }
          // 사용자가 이미 마음을 바꿔 확인된 값과 같아졌다면 알릴 게 없다 —
          // 켰다가 곧바로 끈 뒤 켜기 요청이 실패한 경우, 최종 의도(끄기)는
          // 그대로 만족된 상태다.
          if (desired == confirmed) return;
          // 숨겨진 탭에서 토스트를 띄우면 `AppShell`의 `Scaffold`가 하나뿐이라
          // 사용자가 지금 보고 있는 **다른 탭 위에** 뜬다(리뷰 Critical 2).
          // 되돌리기는 전역 상태라 그대로 두고, 알림만 참는다.
          if (_visible) {
            showAppToast(
              context,
              error is ApiException ? error.message : '알림 설정을 바꾸지 못했어요.',
            );
          }
          return;
        }

        if (!mounted || generation != _pushGeneration) return;
        _confirmedPushEnabled = target;
        if (_desiredPushEnabled == target) _desiredPushEnabled = null;
      }
    } finally {
      _pushInFlight = false;
    }
  }

  /// 지금 세션이 들고 있는 이름. 세션이 `SessionReady`가 아닌 순간은
  /// 이론상 이 화면에 도달할 수 없지만 방어적으로 null을 돌려준다.
  String? _currentName() {
    final state = ref.read(sessionControllerProvider).value;
    return state is SessionReady ? state.profile.name : null;
  }

  void _openNameChangePopup(MemberProfile profile) {
    _openPopup(
      (context) => _NameChangePopupContent(
        initialName: profile.name,
        onCancel: _closePopup,
        onChanged: (name) {
          _closePopup();
          if (!mounted) return;
          ref.read(sessionControllerProvider.notifier).applyProfileChange(name: name);
        },
      ),
    );
  }

  void _openPasswordChangePopup() {
    _openPopup(
      (context) => PasswordChangePopupContent(
        onCancel: _closePopup,
        onChanged: () {
          _closePopup();
          if (!mounted) return;
          // Figma `405:2325` "변경 알림"의 문구 그대로.
          showAppToast(context, '비밀번호가 변경되었어요');
        },
      ),
    );
  }

  /// 로그아웃 확인 팝업. **Figma에 이 팝업은 없다** — 파일 전체의 팝업은
  /// 출석코드·출석완료·블루투스·이름 변경·비밀번호 변경 다섯 개뿐이다.
  /// 확인 없이 즉시 로그아웃하지 말라는 것은 요구사항이므로, 같은 파일의
  /// 다른 팝업들이 쓰는 구성(제목 + 취소/실행 2단 버튼)을 그대로 따랐다.
  void _openLogoutConfirmPopup() {
    _openPopup(
      (context) => _LogoutConfirmPopupContent(
        onCancel: _closePopup,
        onConfirm: () {
          _closePopup();
          if (!mounted) return;
          // 토큰 저장소를 직접 건드리지 않는다 — 서버 로그아웃·토큰 정리·
          // 세션 상태 전환이 전부 이 한 호출 안에 있다(요구사항 4).
          unawaited(ref.read(sessionControllerProvider.notifier).signOut());
        },
      ),
    );
  }

  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final session = ref.watch(sessionControllerProvider).value;

    if (session is! SessionReady) {
      return ColoredBox(
        color: colors.bg,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    final profile = session.profile;

    return ColoredBox(
      color: colors.bg,
      child: SafeArea(
        top: false,
        // Figma의 "리스트"(`353:1569`)는 남은 높이를 다 쓰고 그 안에서
        // 카드 묶음과 로그아웃 버튼을 위아래 끝으로 밀어낸다. 그대로
        // `Spacer` 하나로 옮기면 화면이 낮을 때 오버플로가 나므로(위젯
        // 테스트에서는 오버플로가 곧 실패다), 내용이 뷰포트보다 크면
        // 스크롤로 넘어가는 표준 조합을 쓴다: 최소 높이를 뷰포트로 묶고
        // `IntrinsicHeight`가 그 안에서 `Spacer`를 살린다.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 상단 바와 프로필 사이 24(`353:1542`의 gap).
                    const SizedBox(height: 24),
                    _ProfileHeader(
                      name: profile.name,
                      stdId: profile.stdId,
                      onEditName: () => _openNameChangePopup(profile),
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _MenuCard(
                        iconAsset: 'assets/icons/time-line.svg',
                        title: '알림 허용',
                        subtitle: '알림을 꺼놓으면 불편해요',
                        trailing: AppSwitch(
                          value: profile.pushEnabled,
                          semanticLabel: '알림 허용',
                          onChanged: (next) => _onPushToggled(profile, next),
                        ),
                      ),
                    ),
                    // 카드 사이 10(`353:1719`의 gap).
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _MenuCard(
                        iconAsset: 'assets/icons/lock-line.svg',
                        title: '비밀번호 변경',
                        subtitle: '3개월에 한번씩 비밀번호 변경이 가능해요',
                        onTap: _openPasswordChangePopup,
                        trailing: SvgPicture.asset(
                          'assets/icons/arrow-right-s-line.svg',
                          width: 28,
                          height: 28,
                          colorFilter: ColorFilter.mode(colors.gray1, BlendMode.srcIn),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: AppButton(
                        label: '로그아웃',
                        onPressed: _openLogoutConfirmPopup,
                        // Figma 버튼 컴포넌트 `317:1419`("속성 1=버튼")는
                        // 라벨 뒤에 셰브론을 단다 — 로그아웃 버튼이 그
                        // variant다.
                        trailing: SvgPicture.asset(
                          'assets/icons/chevron-right.svg',
                          width: 7.78,
                          height: 12.73,
                          colorFilter: ColorFilter.mode(colors.bg, BlendMode.srcIn),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 프로필 머리(Figma `353:1556` "마이"). 아바타 84, 그 아래 16 띄우고
/// 이름(+연필) / 학번 순이다.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.name,
    required this.stdId,
    required this.onEditName,
  });

  final String name;
  final String stdId;
  final VoidCallback onEditName;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Column(
      children: [
        const SizedBox(height: 10),
        const _Avatar(),
        const SizedBox(height: 16),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name, style: typography.body1.copyWith(color: colors.gray3)),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: '이름 변경',
              child: GestureDetector(
                onTap: onEditName,
                behavior: HitTestBehavior.opaque,
                child: SvgPicture.asset(
                  'assets/icons/pencil-line.svg',
                  width: 24,
                  height: 24,
                  colorFilter: ColorFilter.mode(colors.gray1, BlendMode.srcIn),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        // 학번은 표시만 한다 — 수정 수단이 없다(요구사항 1).
        Text(stdId, style: typography.body2.copyWith(color: colors.gray2)),
      ],
    );
  }
}

/// 아바타(Figma `353:1558`). 원본 에셋은 `main` 배경 원과 흰 사람 실루엣이
/// 한 파일에 들어 있어 색이 두 개다 — 에셋에 16진수 색을 두지 않는다는
/// 규칙(`app_theme_test.dart`) 때문에 사람 실루엣만 중립 색으로 내보내고,
/// 원 배경은 여기서 토큰으로 칠한다. 실루엣은 원 밖으로 삐져나가도록 그려져
/// 있어(y가 84를 넘는다) 원형 클립이 필요하다 — 원본의 `clipPath`가 하던
/// 일이다.
class _Avatar extends StatelessWidget {
  const _Avatar();

  static const double size = 84;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    return ClipOval(
      child: ColoredBox(
        color: colors.main,
        child: SvgPicture.asset(
          'assets/icons/profile-avatar.svg',
          width: size,
          height: size,
          colorFilter: ColorFilter.mode(colors.white, BlendMode.srcIn),
        ),
      ),
    );
  }
}

/// 리스트 카드(Figma `353:1571`·`353:1709` "알림 수신"). 높이 88 = 패딩
/// 20 + 아이콘 배지 48 + 패딩 20.
class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.iconAsset,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  final String iconAsset;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    final card = AppCard(
      borderRadius: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.iconBadge,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SvgPicture.asset(
                    iconAsset,
                    width: 24,
                    height: 24,
                    colorFilter: ColorFilter.mode(colors.main, BlendMode.srcIn),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: typography.title6.copyWith(color: colors.gray3)),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: typography.body4.copyWith(color: colors.gray2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          trailing,
        ],
      ),
    );

    if (onTap == null) return card;
    // 라벨을 따로 주지 않는다 — 카드 안의 제목·부제가 이미 읽힌다.
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: card,
      ),
    );
  }
}

/// 이름 변경 팝업(Figma `353:1646` "이름 변경 팝업", 342×227).
///
/// `PasswordChangePopupContent`와 같은 이유로 자기 상태를 스스로 들고 있고,
/// 닫기만 호출자(`ProfileScreen`)에게 맡긴다.
class _NameChangePopupContent extends ConsumerStatefulWidget {
  const _NameChangePopupContent({
    required this.initialName,
    required this.onCancel,
    required this.onChanged,
  });

  final String initialName;
  final VoidCallback onCancel;
  final ValueChanged<String> onChanged;

  @override
  ConsumerState<_NameChangePopupContent> createState() => _NameChangePopupContentState();
}

class _NameChangePopupContentState extends ConsumerState<_NameChangePopupContent> {
  late final TextEditingController _name = TextEditingController(text: widget.initialName);

  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final name = _name.text.trim();
    // Phase 1의 정본 검증을 그대로 쓴다 — `^[가-힣a-zA-Z]{2,20}$`는 서버
    // 스키마에서 온 규칙이라 화면마다 다시 쓰면 어긋난다.
    final error = AuthFormValidator.name(name);
    setState(() => _error = error);
    if (error != null) return;

    setState(() => _submitting = true);
    try {
      // 토글을 함께 보내지 않는다 — `pushEnabled`가 빠지면 서버는 그 값을
      // 건드리지 않는다.
      await ref.read(profileRepositoryProvider).updateProfile(name: name);
    } on ApiException catch (apiError) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = apiError.message;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _submitting = false);
    widget.onChanged(name);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '이름 변경',
          textAlign: TextAlign.center,
          style: typography.title4.copyWith(color: colors.gray3),
        ),
        const SizedBox(height: 16),
        AppInput(
          controller: _name,
          hint: '이름을 입력하세요',
          errorText: _error,
          prefix: SvgPicture.asset(
            'assets/icons/user-line.svg',
            width: 16,
            height: 21,
            colorFilter: ColorFilter.mode(colors.gray1, BlendMode.srcIn),
          ),
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: 16),
        PopupActionButtons(
          cancelLabel: '취소',
          confirmLabel: '수정하기',
          onCancel: _submitting ? null : widget.onCancel,
          onConfirm: _submit,
          isLoading: _submitting,
        ),
      ],
    );
  }
}

/// 로그아웃 확인 팝업. Figma에 없는 화면이라 다른 팝업들의 구성(제목 +
/// 취소/실행 2단 버튼)을 따랐다 — `ProfileScreen._openLogoutConfirmPopup`
/// 주석 참고.
class _LogoutConfirmPopupContent extends StatelessWidget {
  const _LogoutConfirmPopupContent({required this.onCancel, required this.onConfirm});

  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '로그아웃',
          textAlign: TextAlign.center,
          style: typography.title4.copyWith(color: colors.gray3),
        ),
        const SizedBox(height: 16),
        Text(
          '정말 로그아웃할까요?',
          textAlign: TextAlign.center,
          style: typography.body2.copyWith(color: colors.gray2),
        ),
        const SizedBox(height: 24),
        PopupActionButtons(
          cancelLabel: '취소',
          confirmLabel: '로그아웃',
          onCancel: onCancel,
          onConfirm: onConfirm,
        ),
      ],
    );
  }
}
