import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/dio_provider.dart';

abstract interface class ClubRepository {
  Future<void> joinByInviteCode(String code);
}

class HttpClubRepository implements ClubRepository {
  const HttpClubRepository(this._client);

  final ApiClient _client;

  /// `POST /clubs/join`은 `{clubId, inviteCode}`를 받지만, clubId는 사용자가
  /// 알 수 없고 필수도 아니므로 inviteCode만 보낸다.
  @override
  Future<void> joinByInviteCode(String code) {
    return _client.post<void>(
      '/clubs/join',
      body: {'inviteCode': code},
      parse: (_) {},
    );
  }
}

final clubRepositoryProvider = Provider<ClubRepository>((ref) {
  return HttpClubRepository(ref.watch(apiClientProvider));
});
