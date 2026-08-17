import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/dio_provider.dart';

/// 마이페이지가 실제로 쓰는 것만 노출한다. 조회(`GET /members/me`)는
/// `AuthRepository.fetchMe`가 이미 갖고 있고 그 결과는 `SessionController`가
/// 들고 있으므로 여기 다시 두지 않는다.
abstract interface class ProfileRepository {
  /// `PATCH /members/me`. 명세서상 `name`이 **필수**라, 알림 토글만 바꿀
  /// 때도 현재 이름을 함께 보내야 한다(안 보내면 400).
  ///
  /// [title]·[pushEnabled]는 null이면 본문에서 아예 빠진다 — `null`을 값으로
  /// 실어 보내면 서버가 "그 필드를 비워달라"는 요청으로 읽을 수 있다.
  Future<void> updateProfile({
    required String name,
    String? title,
    bool? pushEnabled,
  });

  /// `PATCH /members/me/fcm-token`. 발급·갱신된 FCM 토큰을 서버에 등록한다.
  ///
  /// 실패해도 앱의 다른 기능은 그대로 동작한다 — 알림만 못 받는다. 그래서
  /// 호출부가 조용히 삼키는데, **그만큼 토큰이 실제로 등록됐는지 확인할
  /// 방법이 앱 안에 없다.** 이 메서드 자체는 테스트로 고정한다.
  Future<void> updateFcmToken(String token);

  /// `PATCH /members/me/password`. 서버가 현재 비밀번호를 검증하고
  /// **다른 기기의** refresh token만 무효화한다 — 이 기기의 세션은 유지된다.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmNewPassword,
  });
}

class HttpProfileRepository implements ProfileRepository {
  const HttpProfileRepository(this._client);

  final ApiClient _client;

  @override
  Future<void> updateProfile({
    required String name,
    String? title,
    bool? pushEnabled,
  }) {
    return _client.patch<void>(
      '/members/me',
      body: {
        'name': name,
        // null-aware 요소 — null이면 그 키 자체가 본문에서 빠진다.
        'title': ?title,
        'pushEnabled': ?pushEnabled,
      },
      parse: (_) {},
    );
  }

  @override
  Future<void> updateFcmToken(String token) {
    return _client.patch<void>(
      '/members/me/fcm-token',
      body: {'fcmToken': token},
      parse: (_) {},
    );
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmNewPassword,
  }) {
    return _client.patch<void>(
      '/members/me/password',
      body: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
        'confirmNewPassword': confirmNewPassword,
      },
      parse: (_) {},
    );
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return HttpProfileRepository(ref.watch(apiClientProvider));
});
