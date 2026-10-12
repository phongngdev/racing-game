import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:racing_client/api/api_client.dart';
import 'package:racing_client/catalog/catalog_repository.dart';

void main() {
  test(
    'catalog repository uses list, POST, PUT and DELETE API contracts',
    () async {
      final requests = <http.Request>[];
      final api = ApiClient(
        baseUri: Uri.parse('http://localhost:3000'),
        readAccessToken: () => 'admin-token',
        client: MockClient((request) async {
          requests.add(request);
          final product = {
            'id': 'product-1',
            'name': 'RC Buggy',
            'description': '',
            'price': 12.5,
            'categoryId': null,
          };
          final category = {
            'id': 'category-1',
            'name': 'Buggy',
            'description': '',
          };
          return switch ('${request.method} ${request.url.path}') {
            'GET /products' => http.Response(jsonEncode([product]), 200),
            'GET /categories' => http.Response(jsonEncode([category]), 200),
            'POST /products' || 'PUT /products/product-1' => http.Response(
              jsonEncode(product),
              200,
            ),
            'DELETE /products/product-1' => http.Response('', 204),
            'POST /categories' || 'PUT /categories/category-1' => http.Response(
              jsonEncode(category),
              200,
            ),
            'DELETE /categories/category-1' => http.Response('', 204),
            _ => http.Response('{}', 404),
          };
        }),
      );
      addTearDown(api.close);
      final repository = HttpCatalogRepository(api);

      expect((await repository.products()).single.categoryId, isNull);
      expect((await repository.categories()).single.name, 'Buggy');
      await repository.createProduct(
        name: 'RC Buggy',
        price: 12.5,
        description: '',
        categoryId: null,
      );
      await repository.replaceProduct(
        id: 'product-1',
        name: 'RC Buggy',
        price: 12.5,
        description: '',
        categoryId: 'category-1',
      );
      await repository.deleteProduct('product-1');
      await repository.createCategory(name: 'Buggy', description: '');
      await repository.replaceCategory(
        id: 'category-1',
        name: 'Buggy',
        description: 'Updated',
      );
      await repository.deleteCategory('category-1');

      expect(
        requests.map((request) => '${request.method} ${request.url.path}'),
        [
          'GET /products',
          'GET /categories',
          'POST /products',
          'PUT /products/product-1',
          'DELETE /products/product-1',
          'POST /categories',
          'PUT /categories/category-1',
          'DELETE /categories/category-1',
        ],
      );
      expect(
        requests.every(
          (request) => request.headers['Authorization'] == 'Bearer admin-token',
        ),
        isTrue,
      );
      expect(jsonDecode(requests[2].body)['categoryId'], isNull);
      expect(jsonDecode(requests[3].body)['categoryId'], 'category-1');
      expect(jsonDecode(requests[5].body)['name'], 'Buggy');
      expect(jsonDecode(requests[6].body)['description'], 'Updated');
    },
  );
}
