enum ApiFailureKind { http, network, timeout, invalidResponse }

class ApiException implements Exception {
  const ApiException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.code,
  });

  final ApiFailureKind kind;
  final String message;
  final int? statusCode;
  final String? code;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;

  String get userMessage {
    if (kind == ApiFailureKind.timeout) {
      return 'Máy chủ phản hồi quá lâu. Hãy thử lại.';
    }
    if (kind == ApiFailureKind.network) {
      return 'Không thể kết nối đến máy chủ. Hãy kiểm tra mạng và thử lại.';
    }
    if (kind == ApiFailureKind.invalidResponse) {
      return 'Máy chủ gửi dữ liệu không hợp lệ.';
    }
    return switch (statusCode) {
      400 => 'Dữ liệu chưa hợp lệ. Hãy kiểm tra lại các trường.',
      401 => 'Tên đăng nhập hoặc mật khẩu không đúng, hoặc phiên đã hết hạn.',
      403 => 'Tài khoản hiện tại không có quyền thực hiện thao tác này.',
      404 => 'Không tìm thấy dữ liệu. Hãy tải lại danh sách.',
      409 => 'Thông tin này đã được sử dụng.',
      _ when statusCode != null && statusCode! >= 500 =>
        'Máy chủ đang gặp sự cố. Hãy thử lại sau.',
      _ => 'Yêu cầu chưa thực hiện được. Hãy thử lại.',
    };
  }

  @override
  String toString() => 'ApiException($statusCode, $kind): $message';
}
