import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/network/error_code.dart';

part 'club_settings_repository.g.dart';

/// `GET /clubs/{clubId}`의 응답.
@JsonSerializable(createToJson: false)
class ClubDetail {
  const ClubDetail({
    required this.id,
    required this.clubName,
    this.clubDescription,
    this.createdAt,
  });

  factory ClubDetail.fromJson(Map<String, dynamic> json) => _$ClubDetailFromJson(json);

  final int id;
  final String clubName;

  /// 설명은 비어 있을 수 있다.
  final String? clubDescription;

  final DateTime? createdAt;
}

abstract interface class ClubSettingsRepository {
  Future<ClubDetail> fetchClub(int clubId);

  /// `PATCH /clubs/{clubId}`.
  ///
  /// 응답이 수정된 동아리가 아니라 **문자열**(`RsDataString`)이다 — 서버가
  /// 무엇을 저장했는지 응답만 봐서는 알 수 없으므로, 화면은 저장 뒤
  /// [fetchClub]으로 다시 읽어야 한다.
  Future<void> updateClub({
    required int clubId,
    required String clubName,
    required String clubDescription,
  });

  /// 현재 유효한 초대코드. 없으면 null.
  ///
  /// 서버는 코드가 없을 때 `data: null`이 아니라 **400
  /// `INVALID_INVITE_CODE`**로 답한다. 그걸 그대로 올리면 "아직 코드를 안
  /// 만들었다"가 화면에서 오류로 보인다 — 여기서 null로 접는다.
  Future<String?> fetchInviteCode(int clubId);

  /// 새 코드를 발급한다. **기존 유효 코드는 서버가 자동으로 무효화한다** —
  /// "생성"이 아니라 "재발급"이다.
  Future<String> issueInviteCode(int clubId);

  /// 무효화한다. 이미 유효한 코드가 없으면 서버가 400
  /// `INVALID_INVITE_CODE`로 답하는데, **원하던 상태에 이미 도달한 것**이라
  /// 실패로 다루지 않는다.
  Future<void> revokeInviteCode(int clubId);
}

class HttpClubSettingsRepository implements ClubSettingsRepository {
  const HttpClubSettingsRepository(this._client);

  final ApiClient _client;

  @override
  Future<ClubDetail> fetchClub(int clubId) {
    return _client.get<ClubDetail>(
      '/clubs/$clubId',
      parse: (json) => ClubDetail.fromJson(json! as Map<String, dynamic>),
    );
  }

  @override
  Future<void> updateClub({
    required int clubId,
    required String clubName,
    required String clubDescription,
  }) {
    return _client.patch<void>(
      '/clubs/$clubId',
      body: {'clubName': clubName, 'clubDescription': clubDescription},
      parse: (_) {},
    );
  }

  @override
  Future<String?> fetchInviteCode(int clubId) async {
    try {
      return await _client.get<String?>(
        '/clubs/$clubId/invite-code',
        parse: (json) => (json as Map<String, dynamic>?)?['inviteCode'] as String?,
      );
    } on ApiException catch (error) {
      // **이 코드 하나만** 접는다. `CLUB_NOT_FOUND`·권한 오류·네트워크 실패를
      // 함께 삼키면 "코드가 없음"과 "못 읽었음"이 화면에서 같아 보인다.
      if (error.code == ErrorCode.invalidInviteCode) return null;
      rethrow;
    }
  }

  @override
  Future<String> issueInviteCode(int clubId) {
    return _client.post<String>(
      '/clubs/$clubId/invite-code',
      parse: (json) {
        final code = (json! as Map<String, dynamic>)['inviteCode'] as String?;
        if (code == null || code.isEmpty) {
          // 빈 코드를 화면에 띄우면 관리자가 그걸 그대로 공유한다.
          throw const FormatException('발급된 초대코드가 비어 있습니다.');
        }
        return code;
      },
    );
  }

  @override
  Future<void> revokeInviteCode(int clubId) async {
    try {
      await _client.delete<void>('/clubs/$clubId/invite-code', parse: (_) {});
    } on ApiException catch (error) {
      if (error.code == ErrorCode.invalidInviteCode) return;
      rethrow;
    }
  }
}

final clubSettingsRepositoryProvider = Provider<ClubSettingsRepository>((ref) {
  return HttpClubSettingsRepository(ref.watch(apiClientProvider));
});
