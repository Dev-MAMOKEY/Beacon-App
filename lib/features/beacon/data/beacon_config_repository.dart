import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/dio_provider.dart';
import 'beacon_config_dto.dart';

abstract interface class BeaconConfigRepository {
  Future<BeaconConfig> fetch(int clubId);

  /// 전체 교체. 응답도 비콘 설정이라 저장된 값을 그대로 돌려받는다 —
  /// 서버가 다듬은 값이 있으면 그게 화면에 반영돼야 한다.
  Future<BeaconConfig> update(int clubId, BeaconConfig config);
}

class HttpBeaconConfigRepository implements BeaconConfigRepository {
  const HttpBeaconConfigRepository(this._client);

  final ApiClient _client;

  @override
  Future<BeaconConfig> fetch(int clubId) {
    return _client.get<BeaconConfig>(
      '/clubs/$clubId/beacon',
      parse: (json) => BeaconConfig.fromJson(json! as Map<String, dynamic>),
    );
  }

  @override
  Future<BeaconConfig> update(int clubId, BeaconConfig config) {
    return _client.put<BeaconConfig>(
      '/clubs/$clubId/beacon',
      body: config.toJson(),
      parse: (json) => BeaconConfig.fromJson(json! as Map<String, dynamic>),
    );
  }
}

final beaconConfigRepositoryProvider = Provider<BeaconConfigRepository>((ref) {
  return HttpBeaconConfigRepository(ref.watch(apiClientProvider));
});
