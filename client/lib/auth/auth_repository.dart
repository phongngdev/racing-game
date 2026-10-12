import '../api/api_client.dart';
import 'session_user.dart';

abstract interface class AuthRepository {
  Future<String> login(String username, String password);
  Future<String> googleLogin(String idToken, {String? linkPassword});
  Future<void> register(String username, String email, String password);
  Future<void> requestPasswordReset(String email);
  Future<void> resetPassword(String email, String otp, String newPassword);
  Future<SessionUser> me();
}

class HttpAuthRepository implements AuthRepository {
  const HttpAuthRepository(this._api);

  final ApiClient _api;

  @override
  Future<String> login(String username, String password) async {
    final response = await _api.post('/auth/login', {
      'username': username,
      'password': password,
    });
    if (response is! Map<String, dynamic> ||
        response['accessToken'] is! String) {
      throw const FormatException(
        'The API returned an invalid login response.',
      );
    }
    return response['accessToken'] as String;
  }

  @override
  Future<String> googleLogin(String idToken, {String? linkPassword}) async {
    final response = await _api.post('/auth/google', {
      'idToken': idToken,
      'linkPassword': ?linkPassword,
    });
    if (response is! Map<String, dynamic> ||
        response['accessToken'] is! String) {
      throw const FormatException(
        'The API returned an invalid Google login response.',
      );
    }
    return response['accessToken'] as String;
  }

  @override
  Future<void> register(String username, String email, String password) async {
    await _api.post('/auth/register', {
      'username': username,
      'email': email,
      'password': password,
    });
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    await _api.post('/auth/forgot-password', {'email': email});
  }

  @override
  Future<void> resetPassword(
    String email,
    String otp,
    String newPassword,
  ) async {
    await _api.post('/auth/reset-password', {
      'email': email,
      'otp': otp,
      'newPassword': newPassword,
    });
  }

  @override
  Future<SessionUser> me() async {
    final response = await _api.get('/auth/me');
    if (response is! Map<String, dynamic>) {
      throw const FormatException('The API returned an invalid user profile.');
    }
    return SessionUser.fromJson(response);
  }
}
