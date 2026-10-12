import 'package:shared_preferences/shared_preferences.dart';

abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

class PreferencesTokenStore implements TokenStore {
  PreferencesTokenStore({
    required SharedPreferencesAsync preferences,
    required String apiBaseUrl,
  }) {
    _preferences = preferences;
    _key = 'apex_rc.access_token.${apiBaseUrl.toLowerCase()}';
  }

  late final SharedPreferencesAsync _preferences;
  late final String _key;

  @override
  Future<String?> read() => _preferences.getString(_key);

  @override
  Future<void> write(String token) => _preferences.setString(_key, token);

  @override
  Future<void> clear() => _preferences.remove(_key);
}
