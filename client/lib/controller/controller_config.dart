abstract final class ControllerConfig {
  static const bool allowUsbRelay = bool.fromEnvironment('ALLOW_USB_RELAY');

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
