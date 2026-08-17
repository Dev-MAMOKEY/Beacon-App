import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_svg/flutter_svg.dart';

import '../../../components/ui/button.dart';
import '../../../components/ui/otp_input.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/error_code.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/presentation/session_controller.dart';
import '../data/club_repository.dart';

/// 대문자로 바꾸되 선택 영역과 IME 조합(composing) 구간은 그대로 보존한다.
/// `TextEditingController.value`를 직접 새로 만들어 덮어쓰면 캐럿이 항상
/// 끝으로 튀고 조합 중이던 글자가 끊기므로, 포매터 체인 안에서 텍스트만
/// 바꾼다. 이 포매터보다 먼저 적용되는 `FilteringTextInputFormatter.allow`가
/// A-Z/a-z/0-9만 남기므로 여기서 하는 `toUpperCase()`는 항상 길이를
/// 보존한다(독일어 ß→SS처럼 길이가 늘어나는 대소문자 변환은 애초에 입력에
/// 남아있는 문자 범위 밖이라 들어올 수 없다) — 그래서 원래 selection/
/// composing 오프셋을 그대로 재사용해도 안전하다.
class _UpperCaseTextFormatter extends TextInputFormatter {
  const _UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
      composing: newValue.composing,
    );
  }
}

/// 명세서: 스킵 불가 화면. 동아리 소속이 없으면 여기서 막힌다.
class InviteCodeScreen extends ConsumerStatefulWidget {
  const InviteCodeScreen({super.key});

  static const int codeLength = 6;

  /// 스크롤 뷰의 위아래 패딩. 최소 높이를 계산할 때 그만큼 빼야 화면이 꼭
  /// 맞는 경우에도 불필요한 스크롤이 생기지 않는다.
  static const double _verticalPadding = 32;

  @override
  ConsumerState<InviteCodeScreen> createState() => _InviteCodeScreenState();
}

class _InviteCodeScreenState extends ConsumerState<InviteCodeScreen> {
  /// 지금까지 입력된 코드. Figma가 단일 입력 칸이 아니라 6칸 그리드
  /// (`289:3271`)라 `AppOtpInput`이 글자를 모아 준다(#61).
  String _code = '';

  final AppOtpController _otpController = AppOtpController();

  String? _error;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _code.length == InviteCodeScreen.codeLength && !_isSubmitting;

  Future<void> _submit() async {
    // 재진입 방지: _isSubmitting은 다음 프레임에 가서야 버튼의 disabled에
    // 반영된다. 그 전에 두 번 탭하면(같은 프레임 안에서) 가입 요청이 중복
    // 전송될 수 있으므로 함수 진입 시점에 한 번 더 막는다.
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await ref.read(clubRepositoryProvider).joinByInviteCode(_code);
      // await 이후에는 화면이 이미 사라졌을 수 있다(예: 세션이 다른 경로로
      // 이미 갱신되어 라우터가 이 화면을 밀어냈다). 이미 사라진 화면을
      // 대신해 세션을 바꾸지 않도록, ref를 다시 쓰기 전에 반드시 mounted를
      // 확인한다.
      if (!mounted) return;
      await _advanceAfterJoin();
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == ErrorCode.alreadyClubMember) {
        // 이미 그 동아리의 멤버라는 응답은 가입이 실제로는 이뤄졌다는
        // 긍정적 증거다 — 예를 들어 서버는 가입을 커밋했는데 응답이 유실돼
        // 클라이언트가 실패로 보고, 사용자가 같은 코드로 재시도한 경우다.
        // 성공 경로와 동일하게 처리해 세션을 다시 읽어 홈으로 보낸다.
        await _advanceAfterJoin();
        return;
      }
      setState(() {
        // 코드 자체가 잘못됐을 때만 입력을 비운다. 그 외 에러(네트워크
        // 단절, 서버 오류 등)에서 입력을 지우면 사용자가 처음부터 다시
        // 타이핑해야 하는데, 방금 입력한 코드가 실제로는 맞는 코드였을 수
        // 있다 — 지우는 건 적대적이다.
        if (error.code == ErrorCode.invalidInviteCode) {
          _code = '';
          _otpController.shake();
        }
        _error = error.code == ErrorCode.invalidInviteCode
            ? '유효하지 않은 초대코드입니다. 관리자에게 다시 확인해주세요'
            : error.message;
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// 가입 성공, 또는 ALREADY_CLUB_MEMBER처럼 성공과 동등하게 취급하는
  /// 경우의 공통 후속 처리. 프로필을 다시 읽으면 clubIds가 채워져 라우터가
  /// 홈으로 보낸다.
  Future<void> _advanceAfterJoin() {
    return ref.read(sessionControllerProvider.notifier).refreshProfile();
  }

  // 대문자 변환은 이제 TextInputFormatter(_UpperCaseTextFormatter)가 맡는다
  // — 선택 영역과 IME 조합 구간을 보존하기 위해서다. 여기서는 지난 제출의
  // 에러 메시지만 지운다 — 사용자가 코드를 고치기 시작하면 지난 실패
  // 메시지는 더 이상 유효하지 않다.
  void _onCodeChanged(String value) {
    setState(() {
      _code = value;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Scaffold(
      backgroundColor: colors.bg,
      // 고정 Column + Spacer만 쓰면 키보드가 올라온 작은 화면에서 세로
      // 공간이 모자라 오버플로가 난다(다른 화면들은 전부 스크롤 뷰를 쓴다).
      // 스크롤 가능하게 감싸되, 화면이 충분히 클 때는 지금처럼 확인 버튼이
      // 바닥에 붙어 있도록 최소 높이를 가용 높이로 잡아준다 — 그래야 Spacer가
      // 남은 공간을 그대로 먹는다. IntrinsicHeight는 스크롤 뷰의 무한 높이
      // 제약 안에서도 Spacer(Expanded)가 동작하게 하기 위해 필요하다.
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: InviteCodeScreen._verticalPadding,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(
                  0,
                  constraints.maxHeight - InviteCodeScreen._verticalPadding * 2,
                ),
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Figma `289:3262` "타이틀" — 제목과 부제가 별개 요소다.
                    // Phase 1은 두 줄을 한 덩어리(title3 / gray3)로 그렸다.
                    const SizedBox(height: 80),
                    Text(
                      '초대코드',
                      // 실측(`289:3264`): title2(SemiBold 28) / main.
                      style: typography.title2.copyWith(color: colors.main),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '관리자에게 받은 6자리 초대코드를 입력해주세요',
                      // 실측(`289:3266`): body2(16) / gray2.
                      style: typography.body2.copyWith(color: colors.gray2),
                    ),
                    const SizedBox(height: 40),
                    // 실측(`289:3271`): 6칸 균등 분할 정사각, 간격 12,
                    // 반경 14, 흰 배경.
                    AppOtpInput(
                      length: InviteCodeScreen.codeLength,
                      controller: _otpController,
                      enabled: !_isSubmitting,
                      stretchCells: true,
                      gap: 12,
                      cellRadius: 14,
                      fillColor: colors.white,
                      keyboardType: TextInputType.text,
                      semanticsLabel: '초대코드',
                      // 순서가 중요하다: 먼저 영문/숫자만 남기고 그다음
                      // 대문자로 바꾼다(Phase 1의 규칙을 그대로 옮겼다).
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                        const _UpperCaseTextFormatter(),
                      ],
                      onChanged: _onCodeChanged,
                      onCompleted: _onCodeChanged,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: typography.body3.copyWith(color: colors.red),
                      ),
                    ],
                    const SizedBox(height: 36),
                    // 실측(`318:1459`) "알림 문구" — 흰 배경, 반경 16,
                    // 좌우 20·상하 16, 아이콘 20, 아이콘–제목 간격 9,
                    // 제목–본문 간격 7, 본문 줄 간격 4.
                    const _RequirementCard(),
                    const Spacer(),
                    AppButton(
                      // 실측(`289:3287`): 라벨이 "확인"이 아니라 "승인요청"
                      // 이고 셰브론이 붙는다.
                      label: '승인요청',
                      isLoading: _isSubmitting,
                      onPressed: _canSubmit ? _submit : null,
                      trailing: SvgPicture.asset(
                        'assets/icons/chevron-right.svg',
                        width: 7.78,
                        height: 12.73,
                        colorFilter: ColorFilter.mode(colors.bg, BlendMode.srcIn),
                      ),
                    ),
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

/// Figma `318:1459` "알림 문구" — 초대코드가 없는 사용자를 위한 안내 카드.
/// Phase 1 구현에는 이 요소가 아예 없었다(#61).
class _RequirementCard extends StatelessWidget {
  const _RequirementCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SvgPicture.asset(
                'assets/icons/error-warning-line.svg',
                width: 20,
                height: 20,
                colorFilter: ColorFilter.mode(colors.gray2, BlendMode.srcIn),
              ),
              const SizedBox(width: 9),
              Text(
                // 실측(`318:1463`)은 대문자 "REQUIREMENT"다.
                'REQUIREMENT',
                style: typography.title7.copyWith(color: colors.gray2),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            '코드가 없으신가요? 담당 관리자에게 문의하여 6자리\n인증 코드를 발급받으세요.',
            style: typography.body3.copyWith(color: colors.gray2, height: 1.3),
          ),
        ],
      ),
    );
  }
}
