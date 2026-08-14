import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/dio_provider.dart';
import 'records_dto.dart';

abstract interface class RecordsRepository {
  Future<MonthlyRecords> fetch({required int clubId, required int year, required int month});
}

class HttpRecordsRepository implements RecordsRepository {
  const HttpRecordsRepository(this._client);

  final ApiClient _client;

  @override
  Future<MonthlyRecords> fetch({
    required int clubId,
    required int year,
    required int month,
  }) {
    return _client.get<MonthlyRecords>(
      '/clubs/$clubId/members/me/records',
      query: {'year': year, 'month': month},
      parse: (json) => MonthlyRecords.fromJson(json! as Map<String, dynamic>),
    );
  }
}

final recordsRepositoryProvider = Provider<RecordsRepository>((ref) {
  return HttpRecordsRepository(ref.watch(apiClientProvider));
});
