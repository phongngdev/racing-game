import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_client.dart';
import 'api/api_config.dart';
import 'auth/auth_controller.dart';
import 'auth/auth_repository.dart';
import 'auth/token_store.dart';
import 'catalog/catalog_repository.dart';

class AppServices {
  AppServices({
    required this.auth,
    required this.catalog,
    required this.apiClient,
  });

  final AuthController auth;
  final CatalogRepository catalog;
  final ApiClient apiClient;

  factory AppServices.createDefault() {
    late final AuthController auth;
    final baseUri = ApiConfig.uri ?? Uri.parse('https://api.invalid');
    final apiClient = ApiClient(
      baseUri: baseUri,
      readAccessToken: () => auth.accessToken,
      client: http.Client(),
      onUnauthorized: (token) => auth.expireIfCurrent(token),
    );
    auth = AuthController(
      repository: HttpAuthRepository(apiClient),
      tokenStore: PreferencesTokenStore(
        preferences: SharedPreferencesAsync(),
        apiBaseUrl: ApiConfig.baseUrl,
      ),
      configurationError: ApiConfig.configurationError,
    );
    return AppServices(
      auth: auth,
      catalog: HttpCatalogRepository(apiClient),
      apiClient: apiClient,
    );
  }

  void dispose() {
    auth.dispose();
    apiClient.close();
  }
}
