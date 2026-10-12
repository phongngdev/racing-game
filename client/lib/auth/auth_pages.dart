import 'package:flutter/material.dart';

import '../pages/page_components.dart';
import 'auth_controller.dart';
import 'google_sign_in_button.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.auth});

  final AuthController auth;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _linkPassword = TextEditingController();
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _username.text = widget.auth.usernameForLogin ?? '';
    if (widget.auth.enableGoogleSignIn) {
      widget.auth.prepareGoogleSignIn();
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _linkPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await widget.auth.login(_username.text, _password.text);
  }

  Future<void> _openRegister() async {
    final username = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => RegisterPage(auth: widget.auth)),
    );
    if (mounted && username != null) _username.text = username;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AnimatedBuilder(
                animation: widget.auth,
                builder: (context, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _AuthBrand(),
                    const SizedBox(height: 28),
                    Text(
                      'Đăng nhập',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    const Text('Đăng nhập để kết nối với Apex RC.'),
                    const SizedBox(height: 22),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (widget.auth.successMessage
                                  case final message?)
                                _InlineNotice(message: message, success: true),
                              if (widget.auth.message case final message?)
                                _InlineNotice(message: message),
                              if (widget.auth.googleLinkRequired) ...[
                                TextFormField(
                                  controller: _linkPassword,
                                  obscureText: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Mật khẩu tài khoản hiện tại',
                                    prefixIcon: Icon(Icons.lock_outline),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.tonal(
                                  onPressed: widget.auth.isBusy
                                      ? null
                                      : () => widget.auth.linkGoogleAccount(
                                          _linkPassword.text,
                                        ),
                                  child: const Text('Liên kết Google'),
                                ),
                                const SizedBox(height: 12),
                              ],
                              TextFormField(
                                controller: _username,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.username],
                                decoration: const InputDecoration(
                                  labelText: 'Tên đăng nhập',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                                validator: (value) {
                                  final username = value?.trim() ?? '';
                                  if (!RegExp(r'^[a-zA-Z0-9_]{3,30}$')
                                      .hasMatch(username)) {
                                    return 'Dùng 3–30 chữ cái, số hoặc dấu gạch dưới.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _password,
                                obscureText: !_showPassword,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [AutofillHints.password],
                                onFieldSubmitted: (_) => _submit(),
                                decoration: InputDecoration(
                                  labelText: 'Mật khẩu',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    tooltip: _showPassword
                                        ? 'Ẩn mật khẩu'
                                        : 'Hiện mật khẩu',
                                    onPressed: () => setState(
                                      () => _showPassword = !_showPassword,
                                    ),
                                    icon: Icon(
                                      _showPassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                  ),
                                ),
                                validator: (value) =>
                                    (value?.length ?? 0) < 8 ||
                                        (value?.length ?? 0) > 128
                                    ? 'Mật khẩu cần từ 8 đến 128 ký tự.'
                                    : null,
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                height: 46,
                                child: FilledButton(
                                  onPressed: widget.auth.isBusy
                                      ? null
                                      : _submit,
                                  child: widget.auth.isBusy
                                      ? const SizedBox.square(
                                          dimension: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Đăng nhập'),
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (widget.auth.enableGoogleSignIn &&
                                  !widget.auth.googleLinkRequired) ...[
                                const Row(
                                  children: [
                                    Expanded(child: Divider()),
                                    Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Text('hoặc'),
                                    ),
                                    Expanded(child: Divider()),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (widget.auth.googleReady)
                                  buildGoogleSignInButton(
                                    onPressed: widget.auth.isBusy
                                        ? () {}
                                        : widget.auth.signInWithGoogle,
                                  )
                                else if (widget.auth.message == null)
                                  const Center(
                                    child: SizedBox.square(
                                      dimension: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 8),
                              ],
                              TextButton(
                                onPressed: widget.auth.isBusy
                                    ? null
                                    : () => Navigator.of(context).push<void>(
                                        MaterialPageRoute<void>(
                                          builder: (_) => ForgotPasswordPage(
                                            auth: widget.auth,
                                          ),
                                        ),
                                      ),
                                child: const Text('Quên mật khẩu?'),
                              ),
                              const SizedBox(height: 4),
                              TextButton(
                                onPressed: widget.auth.isBusy
                                    ? null
                                    : _openRegister,
                                child: const Text('Tạo tài khoản User'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key, required this.auth});

  final AuthController auth;

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _email = TextEditingController();
  final _otp = TextEditingController();
  final _password = TextEditingController();
  bool _codeRequested = false;

  @override
  void dispose() {
    _email.dispose();
    _otp.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final requested = await widget.auth.requestPasswordReset(_email.text);
    if (mounted && requested) setState(() => _codeRequested = true);
  }

  Future<void> _resetPassword() async {
    final reset = await widget.auth.resetPassword(
      _email.text,
      _otp.text,
      _password.text,
    );
    if (mounted && reset) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Đặt lại mật khẩu')),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: AnimatedBuilder(
                  animation: widget.auth,
                  builder: (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Khôi phục tài khoản',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Nhập email để nhận mã xác nhận có hiệu lực trong 5 phút.',
                      ),
                      const SizedBox(height: 16),
                      if (widget.auth.successMessage case final message?)
                        _InlineNotice(message: message, success: true),
                      if (widget.auth.message case final message?)
                        _InlineNotice(message: message),
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        enabled: !_codeRequested,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),
                      if (_codeRequested) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _otp,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          decoration: const InputDecoration(
                            labelText: 'Mã xác nhận',
                            prefixIcon: Icon(Icons.pin_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Mật khẩu mới',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: widget.auth.isBusy
                            ? null
                            : _codeRequested
                            ? _resetPassword
                            : _requestCode,
                        child: widget.auth.isBusy
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(_codeRequested ? 'Đổi mật khẩu' : 'Gửi mã'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key, required this.auth});

  final AuthController auth;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await widget.auth.register(_username.text, _email.text, _password.text);
    if (!mounted || widget.auth.successMessage == null) return;
    Navigator.of(context).pop(_username.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tạo tài khoản')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: AnimatedBuilder(
                    animation: widget.auth,
                    builder: (context, _) => Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Tạo tài khoản User',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          if (widget.auth.message case final message?)
                            _InlineNotice(message: message),
                          TextFormField(
                            controller: _username,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Tên đăng nhập',
                            ),
                            validator: (value) =>
                                RegExp(r'^[a-zA-Z0-9_]{3,30}$')
                                    .hasMatch(value?.trim() ?? '')
                                ? null
                                : 'Dùng 3–30 chữ cái, số hoặc dấu gạch dưới.',
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                            ),
                            validator: (value) =>
                                RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                    .hasMatch(value?.trim() ?? '')
                                ? null
                                : 'Nhập email hợp lệ.',
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: 'Mật khẩu',
                            ),
                            validator: (value) =>
                                (value?.length ?? 0) >= 8 &&
                                    (value?.length ?? 0) <= 128
                                ? null
                                : 'Mật khẩu cần từ 8 đến 128 ký tự.',
                          ),
                          const SizedBox(height: 18),
                          FilledButton(
                            onPressed: widget.auth.isBusy ? null : _submit,
                            child: widget.auth.isBusy
                                ? const CircularProgressIndicator()
                                : const Text('Tạo tài khoản'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthBrand extends StatelessWidget {
  const _AuthBrand();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Icon(Icons.sports_motorsports_rounded, color: demoBlue, size: 34),
      SizedBox(width: 10),
      Text(
        'APEX RC',
        style: TextStyle(
          color: ink,
          fontSize: 16,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    ],
  );
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.message, this.success = false});

  final String message;
  final bool success;

  @override
  Widget build(BuildContext context) {
    final color = success ? const Color(0xFF20825A) : const Color(0xFFB54708);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(message, style: TextStyle(color: color, fontSize: 13)),
    );
  }
}

class SessionMessagePage extends StatelessWidget {
  const SessionMessagePage({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_off_outlined,
                      size: 36,
                      color: muted,
                    ),
                    const SizedBox(height: 14),
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    if (actionLabel != null && onAction != null)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: onAction,
                          child: Text(actionLabel!),
                        ),
                      ),
                    if (secondaryLabel != null && onSecondary != null)
                      TextButton(
                        onPressed: onSecondary,
                        child: Text(secondaryLabel!),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
