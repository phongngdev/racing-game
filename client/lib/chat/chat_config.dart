abstract final class ChatConfig {
  static const baseUrl = String.fromEnvironment(
    'LM_STUDIO_URL',
    defaultValue: 'http://127.0.0.1:1234/v1',
  );
  static const model = String.fromEnvironment(
    'LM_STUDIO_MODEL',
    defaultValue: 'google/gemma-4-e2b',
  );
  static const requestTimeout = Duration(seconds: 90);
  static const maxContextMessages = 20;
  static const maxTokens = 512;
  static const maxImageDimension = 1280;
  static const maxImageBytes = 5 * 1024 * 1024;
  static const maxSourceImageBytes = 10 * 1024 * 1024;
  static const defaultImagePrompt =
      'Hãy phân tích ảnh này bằng tiếng Việt. Mô tả nội dung chính và những chi tiết đáng chú ý, chỉ dựa trên những gì nhìn thấy.';

  static const systemInstruction = '''
Bạn là trợ lý thân thiện, nói tiếng Việt tự nhiên.
Đáp đúng điều người dùng muốn trước. Khi họ chào hỏi hoặc nói chuyện xã giao, hãy đáp lại ngắn gọn như cuộc trò chuyện bình thường; đừng tự hỏi họ muốn tìm hiểu màn hình nào, và đừng liệt kê chức năng nếu họ chưa hỏi.
Bạn có thể hướng dẫn cách dùng Apex RC khi phù hợp. Ứng dụng có các màn hình Kết nối, Tinh chỉnh, Đường đua, Va chạm và Kết quả.
Chỉ hỏi thêm khi thật sự cần thông tin để trả lời. Nếu người dùng muốn trò chuyện ngoài ứng dụng, hãy phản hồi tự nhiên và thân thiện.
Khi người dùng hỏi tiếp về ảnh cũ nhưng ảnh không có trong lượt hiện tại, hãy nói rõ bạn không còn xem trực tiếp được ảnh đó và mời họ gửi lại nếu cần phân tích chi tiết.
Ứng dụng là bản demo: không tuyên bố đã đọc dữ liệu trực tiếp, telemetry, tài khoản hoặc đã điều khiển xe.
''';
}
