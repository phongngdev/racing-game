import 'dart:convert';

import 'package:racing_client/auth/auth_repository.dart';
import 'package:racing_client/auth/session_user.dart';
import 'package:racing_client/auth/token_store.dart';
import 'package:racing_client/catalog/catalog_models.dart';
import 'package:racing_client/catalog/catalog_repository.dart';

SessionUser testUser({AppRole role = AppRole.user}) => SessionUser(
  id: '0123456789abcdef01234567',
  username: role == AppRole.admin ? 'admin_racer' : 'racer_01',
  email: 'racer@example.com',
  role: role,
);

String testToken({Duration validFor = const Duration(hours: 1)}) {
  final header = base64Url.encode(utf8.encode('{"alg":"none"}'));
  final expiry = DateTime.now().add(validFor).millisecondsSinceEpoch ~/ 1000;
  final payload = base64Url.encode(
    utf8.encode(jsonEncode({'sub': '0123456789abcdef01234567', 'exp': expiry})),
  );
  return '$header.$payload.signature';
}

class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this.token]);

  String? token;
  int clearCount = 0;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async => token = value;

  @override
  Future<void> clear() async {
    clearCount++;
    token = null;
  }
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    required this.user,
    String? token,
    this.meError,
    this.loginError,
    this.registerError,
  }) : token = token ?? testToken();

  final SessionUser user;
  final String token;
  Object? meError;
  Object? loginError;
  Object? registerError;
  int meCalls = 0;
  int registerCalls = 0;

  @override
  Future<String> login(String username, String password) async {
    if (loginError case final error?) throw error;
    return token;
  }

  @override
  Future<void> register(String username, String email, String password) async {
    registerCalls++;
    if (registerError case final error?) throw error;
  }

  @override
  Future<SessionUser> me() async {
    meCalls++;
    if (meError case final error?) throw error;
    return user;
  }
}

class FakeCatalogRepository implements CatalogRepository {
  List<Product> productData = [
    const Product(
      id: 'product-1',
      name: 'RC Buggy',
      description: 'Ready to race',
      price: 125.5,
      categoryId: null,
    ),
  ];
  List<Category> categoryData = [
    const Category(id: 'category-1', name: 'Buggy', description: 'Off-road'),
  ];
  int createProductCalls = 0;
  int replaceProductCalls = 0;
  int deleteProductCalls = 0;
  int createCategoryCalls = 0;
  int replaceCategoryCalls = 0;
  int deleteCategoryCalls = 0;

  @override
  Future<List<Product>> products() async => productData;

  @override
  Future<List<Category>> categories() async => categoryData;

  @override
  Future<Product> createProduct({
    required String name,
    required double price,
    required String description,
    required String? categoryId,
  }) async {
    createProductCalls++;
    final product = Product(
      id: 'product-new',
      name: name,
      description: description,
      price: price,
      categoryId: categoryId,
    );
    productData = [...productData, product];
    return product;
  }

  @override
  Future<Product> replaceProduct({
    required String id,
    required String name,
    required double price,
    required String description,
    required String? categoryId,
  }) async {
    replaceProductCalls++;
    final product = Product(
      id: id,
      name: name,
      description: description,
      price: price,
      categoryId: categoryId,
    );
    productData = productData
        .map((item) => item.id == id ? product : item)
        .toList();
    return product;
  }

  @override
  Future<void> deleteProduct(String id) async {
    deleteProductCalls++;
    productData = productData.where((item) => item.id != id).toList();
  }

  @override
  Future<Category> createCategory({
    required String name,
    required String description,
  }) async {
    createCategoryCalls++;
    final category = Category(
      id: 'category-new',
      name: name,
      description: description,
    );
    categoryData = [...categoryData, category];
    return category;
  }

  @override
  Future<Category> replaceCategory({
    required String id,
    required String name,
    required String description,
  }) async {
    replaceCategoryCalls++;
    final category = Category(id: id, name: name, description: description);
    categoryData = categoryData
        .map((item) => item.id == id ? category : item)
        .toList();
    return category;
  }

  @override
  Future<void> deleteCategory(String id) async {
    deleteCategoryCalls++;
    categoryData = categoryData.where((item) => item.id != id).toList();
  }
}
