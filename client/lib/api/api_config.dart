abstract final class ApiConfig {
  static const String baseUrl = String.fromEnvironment('API_BASE_URL');

  static Uri? get uri {
    final value = baseUrl.trim();
    if (value.isEmpty) return null;

    final parsed = Uri.tryParse(value);
    if (parsed == null ||
        !const {'http', 'https'}.contains(parsed.scheme) ||
        parsed.host.isEmpty ||
        (parsed.path.isNotEmpty && parsed.path != '/') ||
        parsed.hasQuery ||
        parsed.hasFragment ||
        parsed.userInfo.isNotEmpty) {
      return null;
    }
    return parsed.replace(path: '', query: null, fragment: null);
  }

  static String? get configurationError => uri == null
      ? 'Chưa cấu hình API_BASE_URL. Hãy chạy ứng dụng với --dart-define=API_BASE_URL=http://<host>:3000.'
      : null;
}
