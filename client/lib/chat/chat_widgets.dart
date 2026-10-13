import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chat_controller.dart';
import 'chat_message.dart';

class ChatbotHost extends StatefulWidget {
  const ChatbotHost({super.key, required this.controller, required this.wide});

  final ChatController controller;
  final bool wide;

  @override
  State<ChatbotHost> createState() => _ChatbotHostState();
}

class _ChatbotHostState extends State<ChatbotHost> {
  final _draftController = TextEditingController();
  bool _panelOpen = false;

  @override
  void dispose() {
    _draftController.dispose();
    super.dispose();
  }

  void _open() {
    if (widget.wide) {
      setState(() => _panelOpen = true);
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatPage(
          controller: widget.controller,
          draftController: _draftController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final maxWidth = math.max(0.0, constraints.maxWidth - 32);
      final maxHeight = math.max(0.0, constraints.maxHeight - 32);
      return Stack(
        children: [
          if (widget.wide && _panelOpen)
            Positioned(
              right: 16,
              bottom: 88,
              child: SizedBox(
                width: math.min(380, maxWidth),
                height: math.min(520, math.max(0.0, maxHeight - 72)),
                child: _ChatPanel(
                  controller: widget.controller,
                  draftController: _draftController,
                  onClose: () => setState(() => _panelOpen = false),
                ),
              ),
            ),
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              heroTag: 'apex-chatbot-fab',
              tooltip: widget.wide ? 'Mở trợ lý Apex RC' : 'Mở chat với AI',
              onPressed: widget.wide
                  ? () => setState(() => _panelOpen = !_panelOpen)
                  : _open,
              backgroundColor: const Color(0xFF3267E3),
              foregroundColor: Colors.white,
              child: Icon(
                widget.wide && _panelOpen
                    ? Icons.close_rounded
                    : Icons.chat_bubble_outline_rounded,
              ),
            ),
          ),
        ],
      );
    },
  );
}

class ChatPage extends StatelessWidget {
  const ChatPage({
    super.key,
    required this.controller,
    required this.draftController,
  });

  final ChatController controller;
  final TextEditingController draftController;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF7F8FA),
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Trợ lý Apex RC', style: TextStyle(fontSize: 16)),
          Text(
            'Hỏi đáp bằng AI',
            style: TextStyle(fontSize: 11, color: Color(0xFF667085)),
          ),
        ],
      ),
      leading: IconButton(
        tooltip: 'Quay lại',
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
    ),
    body: ChatConversationView(
      controller: controller,
      draftController: draftController,
    ),
  );
}

class _ChatPanel extends StatelessWidget {
  const _ChatPanel({
    required this.controller,
    required this.draftController,
    required this.onClose,
  });

  final ChatController controller;
  final TextEditingController draftController;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 12,
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 17,
                backgroundColor: Color(0xFFEEF3FF),
                child: Icon(Icons.smart_toy_rounded, color: Color(0xFF3267E3)),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trợ lý Apex RC',
                      style: TextStyle(
                        color: Color(0xFF172033),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Hỏi đáp bằng AI',
                      style: TextStyle(fontSize: 11, color: Color(0xFF667085)),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Đóng chat',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE8EBF0)),
        Expanded(
          child: ChatConversationView(
            controller: controller,
            draftController: draftController,
          ),
        ),
      ],
    ),
  );
}

class ChatConversationView extends StatefulWidget {
  const ChatConversationView({
    super.key,
    required this.controller,
    required this.draftController,
  });

  final ChatController controller;
  final TextEditingController draftController;

  @override
  State<ChatConversationView> createState() => _ChatConversationViewState();
}

class _ChatConversationViewState extends State<ChatConversationView> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scrollToLatest);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLatest());
  }

  @override
  void didUpdateWidget(covariant ChatConversationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scrollToLatest);
      widget.controller.addListener(_scrollToLatest);
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      unawaited(
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  Future<void> _send() async {
    final text = widget.draftController.text;
    if (text.trim().isEmpty ||
        widget.controller.loading ||
        widget.controller.error != null) {
      return;
    }
    widget.draftController.clear();
    await widget.controller.send(text);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scrollToLatest);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final messages = widget.controller.messages;
      return Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(14),
              itemCount: messages.isEmpty
                  ? 1
                  : messages.length +
                        (widget.controller.loading ? 1 : 0) +
                        (widget.controller.error != null ? 1 : 0),
              itemBuilder: (context, index) {
                if (messages.isEmpty) return const _WelcomeMessage();
                if (index < messages.length) {
                  return _MessageBubble(message: messages[index]);
                }
                if (widget.controller.loading) return const _ThinkingBubble();
                return _RetryMessage(
                  message: widget.controller.error!,
                  onRetry: widget.controller.retry,
                );
              },
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE8EBF0)),
          _ChatComposer(
            controller: widget.draftController,
            enabled: !widget.controller.loading,
            canSend: widget.controller.error == null,
            onSend: _send,
          ),
        ],
      );
    },
  );
}

class _WelcomeMessage extends StatelessWidget {
  const _WelcomeMessage();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, left: 8, right: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CircleAvatar(
          radius: 22,
          backgroundColor: Color(0xFFEEF3FF),
          child: Icon(Icons.smart_toy_rounded, color: Color(0xFF3267E3)),
        ),
        const SizedBox(height: 14),
        const Text(
          'Chào bạn! Mình có thể giúp gì về Apex RC?',
          style: TextStyle(
            color: Color(0xFF172033),
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Bạn có thể hỏi về kết nối, tinh chỉnh, đường đua, va chạm hoặc kết quả.',
          style: TextStyle(color: Color(0xFF667085), height: 1.5),
        ),
      ],
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final user = message.role == ChatRole.user;
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 340),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: user ? const Color(0xFF3267E3) : Colors.white,
        borderRadius: BorderRadius.circular(16).copyWith(
          bottomRight: user ? const Radius.circular(5) : null,
          bottomLeft: user ? null : const Radius.circular(5),
        ),
        border: user ? null : Border.all(color: const Color(0xFFE8EBF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            message.content,
            style: TextStyle(
              color: user ? Colors.white : const Color(0xFF344054),
              height: 1.45,
              fontSize: 13,
            ),
          ),
          if (message.truncated) ...[
            const SizedBox(height: 7),
            const Text(
              'Phản hồi đã chạm giới hạn độ dài.',
              style: TextStyle(fontSize: 10, color: Color(0xFF8A5B00)),
            ),
          ],
        ],
      ),
    );
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: bubble,
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) => const Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: EdgeInsets.only(bottom: 12, left: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 9),
          Text(
            'Đang trả lời…',
            style: TextStyle(fontSize: 12, color: Color(0xFF667085)),
          ),
        ],
      ),
    ),
  );
}

class _RetryMessage extends StatelessWidget {
  const _RetryMessage({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF2D28B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: const TextStyle(fontSize: 12, height: 1.4)),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Thử lại'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ChatComposer extends StatelessWidget {
  const _ChatComposer({
    required this.controller,
    required this.enabled,
    required this.canSend,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool canSend;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: enabled && canSend
                  ? (_) => unawaited(onSend())
                  : null,
              decoration: InputDecoration(
                hintText: 'Nhập câu hỏi…',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE4E7EC)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => IconButton.filled(
              tooltip: 'Gửi tin nhắn',
              onPressed: enabled && canSend && value.text.trim().isNotEmpty
                  ? () => unawaited(onSend())
                  : null,
              icon: const Icon(Icons.send_rounded, size: 19),
            ),
          ),
        ],
      ),
    ),
  );
}
