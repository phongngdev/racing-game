import '../api/api_client.dart';
import 'catalog_models.dart';

abstract interface class CatalogRepository {
  Future<List<Product>> products();
  Future<List<Category>> categories();
  Future<Product> createProduct({
    required String name,
    required double price,
    required String description,
    required String? categoryId,
  });
  Future<Product> replaceProduct({
    required String id,
    required String name,
    required double price,
    required String description,
    required String? categoryId,
  });
  Future<void> deleteProduct(String id);
  Future<Category> createCategory({
    required String name,
    required String description,
  });
  Future<Category> replaceCategory({
    required String id,
    required String name,
    required String description,
  });
  Future<void> deleteCategory(String id);
}

class HttpCatalogRepository implements CatalogRepository {
  const HttpCatalogRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<Product>> products() async =>
      decodeObjectList(await _api.get('/products'))
          .map(Product.fromJson)
          .toList(growable: false);

  @override
  Future<List<Category>> categories() async =>
      decodeObjectList(await _api.get('/categories'))
          .map(Category.fromJson)
          .toList(growable: false);

  @override
  Future<Product> createProduct({
    required String name,
    required double price,
    required String description,
    required String? categoryId,
  }) async => Product.fromJson(
    (await _api.post('/products', {
          'name': name,
          'price': price,
          'description': description,
          'categoryId': categoryId,
        }))!
        as Map<String, dynamic>,
  );

  @override
  Future<Product> replaceProduct({
    required String id,
    required String name,
    required double price,
    required String description,
    required String? categoryId,
  }) async => Product.fromJson(
    (await _api.put('/products/$id', {
          'name': name,
          'price': price,
          'description': description,
          'categoryId': categoryId,
        }))!
        as Map<String, dynamic>,
  );

  @override
  Future<void> deleteProduct(String id) async {
    await _api.delete('/products/$id');
  }

  @override
  Future<Category> createCategory({
    required String name,
    required String description,
  }) async => Category.fromJson(
    (await _api.post('/categories', {
          'name': name,
          'description': description,
        }))!
        as Map<String, dynamic>,
  );

  @override
  Future<Category> replaceCategory({
    required String id,
    required String name,
    required String description,
  }) async => Category.fromJson(
    (await _api.put('/categories/$id', {
          'name': name,
          'description': description,
        }))!
        as Map<String, dynamic>,
  );

  @override
  Future<void> deleteCategory(String id) async {
    await _api.delete('/categories/$id');
  }
}
