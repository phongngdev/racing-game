import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

import '../api/api_exception.dart';
import 'auth_repository.dart';
import 'session_user.dart';
import 'token_store.dart';

enum AuthStatus {
  restoring,
  signedOut,
  signedIn,
  unavailable,
  configurationError,
}

class AuthController extends ChangeNotifier {
  AuthController({
    required AuthRepository repository,
    required TokenStore tokenStore,
    this.configurationError,
  }) {
    _repository = repository;
    _tokenStore = tokenStore;
  }

  late final AuthRepository _repository;
  late final TokenStore _tokenStore;

  AuthStatus _status = AuthStatus.restoring;
  SessionUser? _user;
  String? _accessToken;
  String? _pendingToken;
  String? _message;
  String? _successMessage;
  String? _usernameForLogin;
  bool _busy = false;
  int _sessionVersion = 0;

  final String? configurationError;

  AuthStatus get status => _status;
  SessionUser? get user => _user;
  String? get accessToken => _accessToken;
  String? get message => _message;
  String? get successMessage => _successMessage;
  String? get usernameForLogin => _usernameForLogin;
  bool get isBusy => _busy;
  int get sessionVersion => _sessionVersion;

  Future<void> initialize() async {
    if (configurationError != null) {
      _status = AuthStatus.configurationError;
      _message = configurationError;
      notifyListeners();
      return;
    }

    _status = AuthStatus.restoring;
    _message = null;
    _successMessage = null;
    notifyListeners();

    String? token;
    try {
      token = _pendingToken ?? await _tokenStore.read();
    } catch (_) {
      _status = AuthStatus.unavailable;
      _message = 'Không đọc được phiên đã lưu. Hãy thử lại.';
      notifyListeners();
      return;
    }

    if (token == null || token.isEmpty) {
      _accessToken = null;
      _pendingToken = null;
      _user = null;
      _status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }

    if (_isInvalidOrExpired(token)) {
      await _discardToken(token);
      _message = 'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.';
      _status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }

    _accessToken = token;
    _pendingToken = token;
    try {
      final user = await _repository.me();
      await _tokenStore.write(token);
      _pendingToken = null;
      _setSignedIn(user, token);
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await _discardToken(token);
        _message = error.userMessage;
        _status = AuthStatus.signedOut;
      } else {
        _status = AuthStatus.unavailable;
        _message = error.userMessage;
      }
      notifyListeners();
    } catch (_) {
      _status = AuthStatus.unavailable;
      _message = 'Không thể khôi phục phiên lúc này. Hãy thử lại.';
      notifyListeners();
    }
  }

  Future<void> login(String username, String password) async {
    if (_busy) return;
    _busy = true;
    _message = null;
    _successMessage = null;
    notifyListeners();
    try {
      final token = await _repository.login(username.trim(), password);
      if (_isInvalidOrExpired(token)) {
        throw const ApiException(
          kind: ApiFailureKind.invalidResponse,
          message: 'The API returned an invalid or expired token.',
        );
      }
      _accessToken = token;
      _pendingToken = token;
      final user = await _repository.me();
      await _tokenStore.write(token);
      _pendingToken = null;
      _usernameForLogin = null;
      _setSignedIn(user, token);
    } on ApiException catch (error) {
      if (error.isUnauthorized && _accessToken != null) {
        await _discardToken(_accessToken!);
      } else {
        _accessToken = null;
      }
      _message = error.userMessage;
      _status = error.isUnauthorized
          ? AuthStatus.signedOut
          : AuthStatus.unavailable;
    } on FormatException {
      _accessToken = null;
      _pendingToken = null;
      _status = AuthStatus.signedOut;
      _message = 'Máy chủ gửi dữ liệu đăng nhập không hợp lệ.';
    } catch (_) {
      _status = _pendingToken == null
          ? AuthStatus.signedOut
          : AuthStatus.unavailable;
      _message = 'Không thể hoàn tất đăng nhập. Hãy kiểm tra mạng và thử lại.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> register(String username, String email, String password) async {
    if (_busy) return;
    _busy = true;
    _message = null;
    _successMessage = null;
    notifyListeners();
    try {
      await _repository.register(username.trim(), email.trim(), password);
      _usernameForLogin = username.trim();
      _successMessage = 'Tạo tài khoản thành công. Hãy đăng nhập.';
      _status = AuthStatus.signedOut;
    } on ApiException catch (error) {
      _message = error.userMessage;
    } catch (_) {
      _message = 'Không thể tạo tài khoản lúc này. Hãy thử lại.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _accessToken = null;
    _pendingToken = null;
    _user = null;
    _sessionVersion++;
    _message = null;
    _successMessage = null;
    _status = AuthStatus.signedOut;
    notifyListeners();
    try {
      await _tokenStore.clear();
    } catch (_) {
      _message = 'Đã thoát trên ứng dụng nhưng chưa xóa được token đã lưu.';
      notifyListeners();
    }
  }

  Future<void> expireIfCurrent(String token) async {
    if (_accessToken != token) return;
    await _discardToken(token);
    _sessionVersion++;
    _message = 'Phiên đăng nhập không còn hợp lệ. Hãy đăng nhập lại.';
    _status = AuthStatus.signedOut;
    notifyListeners();
  }

  bool _isInvalidOrExpired(String token) {
    try {
      final payload = JwtDecoder.decode(token);
      if (payload['exp'] is! num) return true;
      return JwtDecoder.isExpired(token);
    } catch (_) {
      return true;
    }
  }

  Future<void> _discardToken(String token) async {
    if (_accessToken == token) _accessToken = null;
    if (_pendingToken == token) _pendingToken = null;
    _user = null;
    try {
      await _tokenStore.clear();
    } catch (_) {
      _message = 'Không thể xóa phiên đã lưu. Hãy thử đăng xuất lại.';
    }
  }

  void _setSignedIn(SessionUser user, String token) {
    _user = user;
    _accessToken = token;
    _sessionVersion++;
    _status = AuthStatus.signedIn;
    _message = null;
    _successMessage = null;
    notifyListeners();
  }
}
