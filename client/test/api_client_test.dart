import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:racing_client/api/api_client.dart';
import 'package:racing_client/api/api_exception.dart';

void main() {
  test('sends JSON and a Bearer token to the configured API root', () async {
    http.Request? captured;
    final api = ApiClient(
      baseUri: Uri.parse('http://192.168.1.20:3000'),
      readAccessToken: () => 'jwt-token',
      client: MockClient((request) async {
        captured = request;
        return http.Response.bytes(
          utf8.encode('{"id":"p1","name":"RC"}'),
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(api.close);

    final value = await api.post('/products', {'name': 'RC', 'price': 12.5});

    expect(captured?.url, Uri.parse('http://192.168.1.20:3000/products'));
    expect(captured?.method, 'POST');
    expect(captured?.headers['Authorization'], 'Bearer jwt-token');
    expect(captured?.headers['Content-Type'], contains('application/json'));
    expect(jsonDecode(captured!.body), {'name': 'RC', 'price': 12.5});
    expect(value, {'id': 'p1', 'name': 'RC'});
  });

  test('uses PUT and returns null for an empty DELETE response', () async {
    final methods = <String>[];
    final api = ApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      readAccessToken: () => null,
      client: MockClient((request) async {
        methods.add(request.method);
        return http.Response('', request.method == 'PUT' ? 200 : 204);
      }),
    );
    addTearDown(api.close);

    expect(await api.put('/categories/c1', {'name': 'Buggy'}), isNull);
    expect(await api.delete('/categories/c1'), isNull);
    expect(methods, ['PUT', 'DELETE']);
  });

  test(
    'calls the unauthorized handler for 401 but preserves 403 semantics',
    () async {
      var invalidatedToken = '';
      final api = ApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        readAccessToken: () => 'current-token',
        onUnauthorized: (token) async => invalidatedToken = token,
        client: MockClient((request) async {
          return http.Response('{"message":"Forbidden"}', 403);
        }),
      );
      addTearDown(api.close);

      await expectLater(
        api.get('/products'),
        throwsA(
          isA<ApiException>()
              .having((error) => error.isForbidden, 'isForbidden', isTrue)
              .having(
                (error) => error.userMessage,
                'userMessage',
                contains('quyền'),
              ),
        ),
      );
      expect(invalidatedToken, isEmpty);

      final unauthorizedApi = ApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        readAccessToken: () => 'current-token',
        onUnauthorized: (token) async => invalidatedToken = token,
        client: MockClient((request) async => http.Response('{}', 401)),
      );
      addTearDown(unauthorizedApi.close);
      await expectLater(
        unauthorizedApi.get('/auth/me'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.isUnauthorized,
            'isUnauthorized',
            isTrue,
          ),
        ),
      );
      expect(invalidatedToken, 'current-token');
    },
  );

  test('maps bad JSON and network failures to typed API errors', () async {
    final malformedApi = ApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      readAccessToken: () => null,
      client: MockClient((request) async => http.Response('not-json', 200)),
    );
    addTearDown(malformedApi.close);
    await expectLater(
      malformedApi.get('/products'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.invalidResponse,
        ),
      ),
    );

    final networkApi = ApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      readAccessToken: () => null,
      client: MockClient(
        (request) async => throw http.ClientException('offline'),
      ),
    );
    addTearDown(networkApi.close);
    await expectLater(
      networkApi.get('/products'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.network,
        ),
      ),
    );
  });

  test('enforces the configured timeout', () async {
    final response = Completer<http.Response>();
    final api = ApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      readAccessToken: () => null,
      client: MockClient((request) => response.future),
      timeout: const Duration(milliseconds: 10),
    );
    addTearDown(api.close);

    await expectLater(
      api.get('/health'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.timeout,
        ),
      ),
    );
  });
}
