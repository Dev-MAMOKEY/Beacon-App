import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../components/ui/app_logo.dart';
import '../../../components/ui/button.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import 'session_controller.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  /// Figma `333:1477`("온보딩")의 로고 아래 문구.
  ///
  /// 명세서는 여기에 **서비스 이름 "마모키"** 를 적으라고 했고 Phase 1은 그
  /// 대로 구현했다. Figma는 같은 자리에 **태그라인 "간편한 동아리 출석"** 을
  /// 둔다. 이 프로젝트는 충돌 시 Figma를 따르기로 정했고, #48에서 조정자
  /// 판정으로 Figma 쪽을 택했다.
  static const String tagline = '간편한 동아리 출석';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final typography = Theme.of(context).extension<AppTypography>()!;

    // 세션 판별에 실패했을 때만 값이 채워진다. 로딩 중이거나 정상 상태일
    // 때는 null이라 재시도 UI가 보이지 않는다. build()는 예외를 던지지
    // 않도록 만들었으므로 hasError는 정상 경로에서 발생하지 않아야 하지만,
    // 방어적으로도 같은 재시도 UI를 보여준다 — 그렇지 않으면 사용자가
    // 메시지도 버튼도 없는 스플래시에 그대로 갇힌다.
    final session = ref.watch(sessionControllerProvider);
    final failure = session.value;
    final message = session.hasError
        ? '문제가 발생했습니다. 다시 시도해주세요.'
        : (failure is SessionUnavailable ? failure.message : null);

    return Scaffold(
      backgroundColor: colors.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Figma 실측(`333:1478`): 106.045 × 82. 간격 10.
              const AppLogo(height: 82),
              const SizedBox(height: 10),
              Text(
                tagline,
                textAlign: TextAlign.center,
                // 실측(`334:1495`): title7(SemiBold 14, 자간 0.7) / main.
                style: typography.title7.copyWith(color: colors.main),
              ),
              if (message != null) ...[
                const SizedBox(height: 24),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: typography.body3.copyWith(color: colors.gray2),
                ),
                const SizedBox(height: 16),
                AppButton.ghost(
                  label: '재시도',
                  size: ButtonSize.md,
                  onPressed: () => ref.invalidate(sessionControllerProvider),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
