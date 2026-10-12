class Product {
  const Product({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.categoryId,
  });

  final String id;
  final String name;
  final String description;
  final double price;
  final String? categoryId;

  factory Product.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final description = json['description'];
    final price = json['price'];
    final categoryId = json['categoryId'];
    if (id is! String ||
        name is! String ||
        description is! String ||
        price is! num ||
        (categoryId != null && categoryId is! String)) {
      throw const FormatException('The API returned an invalid product.');
    }
    return Product(
      id: id,
      name: name,
      description: description,
      price: price.toDouble(),
      categoryId: categoryId as String?,
    );
  }
}

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.description,
  });

  final String id;
  final String name;
  final String description;

  factory Category.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final description = json['description'];
    if (id is! String || name is! String || description is! String) {
      throw const FormatException('The API returned an invalid category.');
    }
    return Category(id: id, name: name, description: description);
  }
}

List<Map<String, dynamic>> decodeObjectList(Object? response) {
  if (response is! List) {
    throw const FormatException('The API returned an invalid list.');
  }
  return response
      .map((item) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('The API returned an invalid list item.');
        }
        return item;
      })
      .toList(growable: false);
}
