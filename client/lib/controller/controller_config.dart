abstract final class ControllerConfig {
  static const String webSocketUrl = String.fromEnvironment(
    'CONTROLLER_WS_URL',
  );

  static Uri? parse(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !const {'ws', 'wss'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      return null;
    }
    return uri;
  }
}
