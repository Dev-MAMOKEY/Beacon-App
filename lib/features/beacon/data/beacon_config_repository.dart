import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/dio_provider.dart';
import 'beacon_config_dto.dart';

abstract interface class BeaconConfigRepository {
  Future<BeaconConfig> fetch(int clubId);
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
}

final beaconConfigRepositoryProvider = Provider<BeaconConfigRepository>((ref) {
  return HttpBeaconConfigRepository(ref.watch(apiClientProvider));
});
