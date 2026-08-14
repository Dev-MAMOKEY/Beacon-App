import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// 프로젝트 공용 바텀시트 프리미티브. 이 화면(#11, 출석 완료 표시)이 처음
/// 만들고, #12(기록 캘린더의 날짜 상세)가 그대로 재사용한다.
///
/// `showModalBottomSheet`를 얇게 감싸기만 한다 — 배경색·모서리 반경·핸들
/// 인디케이터처럼 화면마다 반복될 장식만 여기서 표준화하고, 내용은 전부
/// 호출부의 [child]에 맡긴다.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  final colors = Theme.of(context).extension<AppColors>()!;

  return showModalBottomSheet<T>(
    context: context,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(24),
        topRight: Radius.circular(24),
      ),
    ),
    builder: (context) => AppSheet(child: Builder(builder: builder)),
  );
}

/// 시트 본문을 감싸는 뼈대 — 상단 드래그 핸들과 안전 영역만 표준화한다.
class AppSheet extends StatelessWidget {
  const AppSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.gray4,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}
