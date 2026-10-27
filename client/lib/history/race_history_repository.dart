import '../api/api_client.dart';
import 'race_history.dart';

abstract interface class RaceHistoryRepository {
  Future<RaceHistory> save(RaceHistorySubmission submission);
  Future<RaceHistoryListResult> list({String? cursor});
  Future<RaceHistory> findOne(String id);
}

class HttpRaceHistoryRepository implements RaceHistoryRepository {
  const HttpRaceHistoryRepository(this._api);

  final ApiClient _api;

  @override
  Future<RaceHistory> save(RaceHistorySubmission submission) async {
    final response = await _api.post('/race-histories', submission.toJson());
    if (response is! Map<String, dynamic>) {
      throw const FormatException('The API returned invalid race history.');
    }
    return RaceHistory.fromJson(response);
  }

  @override
  Future<RaceHistoryListResult> list({String? cursor}) async {
    final response = await _api.get(
      '/race-histories/me?limit=20${cursor == null ? '' : '&cursor=$cursor'}',
    );
    if (response is! Map<String, dynamic>) {
      throw const FormatException('The API returned an invalid history list.');
    }
    return RaceHistoryListResult.fromJson(response);
  }

  @override
  Future<RaceHistory> findOne(String id) async {
    final response = await _api.get('/race-histories/$id');
    if (response is! Map<String, dynamic>) {
      throw const FormatException('The API returned invalid race history.');
    }
    return RaceHistory.fromJson(response);
  }
}
