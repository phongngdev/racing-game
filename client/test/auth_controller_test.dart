import 'package:flutter_test/flutter_test.dart';
import 'package:racing_client/api/api_exception.dart';
import 'package:racing_client/auth/auth_controller.dart';
import 'package:racing_client/auth/session_user.dart';

import 'support/fakes.dart';

void main() {
  test(
    'restores a valid token and takes the authoritative role from /auth/me',
    () async {
      final token = testToken();
      final repository = FakeAuthRepository(
        user: testUser(role: AppRole.admin),
        token: token,
      );
      final store = MemoryTokenStore(token);
      final auth = AuthController(repository: repository, tokenStore: store);
      addTearDown(auth.dispose);

      await auth.initialize();

      expect(auth.status, AuthStatus.signedIn);
      expect(auth.user?.role, AppRole.admin);
      expect(auth.accessToken, token);
      expect(repository.meCalls, 1);
    },
  );

  test('clears expired tokens without calling the API', () async {
    final token = testToken(validFor: const Duration(seconds: -1));
    final repository = FakeAuthRepository(user: testUser());
    final store = MemoryTokenStore(token);
    final auth = AuthController(repository: repository, tokenStore: store);
    addTearDown(auth.dispose);

    await auth.initialize();

    expect(auth.status, AuthStatus.signedOut);
    expect(store.token, isNull);
    expect(repository.meCalls, 0);
  });

  test('keeps a valid token for retry when the API is unavailable', () async {
    final token = testToken();
    final repository = FakeAuthRepository(
      user: testUser(),
      token: token,
      meError: const ApiException(
        kind: ApiFailureKind.network,
        message: 'offline',
      ),
    );
    final store = MemoryTokenStore(token);
    final auth = AuthController(repository: repository, tokenStore: store);
    addTearDown(auth.dispose);

    await auth.initialize();
    expect(auth.status, AuthStatus.unavailable);
    expect(store.token, token);

    repository.meError = null;
    await auth.initialize();
    expect(auth.status, AuthStatus.signedIn);
    expect(auth.user?.role, AppRole.user);
  });

  test(
    'clears a token rejected by /auth/me and logout drops session state',
    () async {
      final token = testToken();
      final repository = FakeAuthRepository(
        user: testUser(),
        token: token,
        meError: const ApiException(
          kind: ApiFailureKind.http,
          statusCode: 401,
          message: 'unauthorized',
        ),
      );
      final store = MemoryTokenStore(token);
      final auth = AuthController(repository: repository, tokenStore: store);
      addTearDown(auth.dispose);

      await auth.initialize();
      expect(auth.status, AuthStatus.signedOut);
      expect(store.token, isNull);

      repository.meError = null;
      store.token = token;
      await auth.initialize();
      final sessionVersion = auth.sessionVersion;
      await auth.logout();
      expect(auth.status, AuthStatus.signedOut);
      expect(auth.user, isNull);
      expect(auth.accessToken, isNull);
      expect(store.token, isNull);
      expect(auth.sessionVersion, sessionVersion + 1);
    },
  );

  test('public registration only registers, login verifies role and persists token', () async {
    final repository = FakeAuthRepository(user: testUser(role: AppRole.user));
    final store = MemoryTokenStore();
    final auth = AuthController(repository: repository, tokenStore: store);
    addTearDown(auth.dispose);
    await auth.initialize();

    await auth.register('new_racer', 'new@example.com', 'racing-pass-123');
    expect(repository.registerCalls, 1);
    expect(auth.status, AuthStatus.signedOut);
    expect(auth.usernameForLogin, 'new_racer');
    expect(store.token, isNull);

    await auth.login('new_racer', 'racing-pass-123');
    expect(auth.status, AuthStatus.signedIn);
    expect(auth.user?.role, AppRole.user);
    expect(store.token, isNotNull);
  });

  test('configuration error prevents storage and API access', () async {
    final repository = FakeAuthRepository(user: testUser());
    final store = MemoryTokenStore(testToken());
    final auth = AuthController(
      repository: repository,
      tokenStore: store,
      configurationError: 'missing API_BASE_URL',
    );
    addTearDown(auth.dispose);

    await auth.initialize();
    expect(auth.status, AuthStatus.configurationError);
    expect(repository.meCalls, 0);
    expect(auth.message, contains('API_BASE_URL'));
  });
}
