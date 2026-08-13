import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../components/ui/button.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import 'session_controller.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  final String serviceName = '마모키';

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
              Text(
                'Beacon',
                style: typography.title3.copyWith(color: colors.main),
              ),
              const SizedBox(height: 12),
              Text(
                serviceName,
                style: typography.body2.copyWith(color: colors.gray2),
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
