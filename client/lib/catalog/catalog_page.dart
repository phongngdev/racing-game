import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../auth/auth_controller.dart';
import '../auth/session_user.dart';
import '../pages/page_components.dart';
import 'catalog_models.dart';
import 'catalog_repository.dart';

class CatalogPage extends StatelessWidget {
  const CatalogPage({
    super.key,
    required this.repository,
    required this.auth,
    this.canManage = false,
    this.onReturnToRacing,
  });

  final CatalogRepository repository;
  final AuthController auth;
  final bool canManage;
  final VoidCallback? onReturnToRacing;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(canManage ? 'Quản trị sản phẩm' : 'Sản phẩm & danh mục'),
      actions: [
        if (onReturnToRacing != null)
          TextButton.icon(
            onPressed: onReturnToRacing,
            icon: const Icon(Icons.sports_esports_outlined),
            label: const Text('Mở Apex RC'),
          ),
        PopupMenuButton<String>(
          tooltip: 'Tài khoản ${auth.user?.username ?? ''}',
          onSelected: (value) {
            if (value == 'logout') auth.logout();
            if (value == 'racing') onReturnToRacing?.call();
          },
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              enabled: false,
              child: Text(
                '${auth.user?.username ?? ''} · ${_roleLabel(auth.user?.role)}',
              ),
            ),
            if (onReturnToRacing != null)
              const PopupMenuItem(value: 'racing', child: Text('Mở Apex RC')),
            const PopupMenuItem(value: 'logout', child: Text('Đăng xuất')),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CircleAvatar(
              radius: 16,
              child: Text(_initials(auth.user?.username ?? '')),
            ),
          ),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: CatalogBrowser(repository: repository, canManage: canManage),
  );
}

class CatalogBrowser extends StatefulWidget {
  const CatalogBrowser({
    super.key,
    required this.repository,
    required this.canManage,
  });

  final CatalogRepository repository;
  final bool canManage;

  @override
  State<CatalogBrowser> createState() => _CatalogBrowserState();
}

class _CatalogBrowserState extends State<CatalogBrowser> {
  List<Product> _products = const [];
  List<Category> _categories = const [];
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool initial = true}) async {
    if (initial && mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.repository.products(),
        widget.repository.categories(),
      ]);
      if (!mounted) return;
      setState(() {
        _products = results[0] as List<Product>;
        _categories = results[1] as List<Category>;
        _loadError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = _errorMessage(error));
    } finally {
      if (initial && mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _saveProduct(_ProductDraft draft, {Product? existing}) async {
    try {
      if (existing == null) {
        await widget.repository.createProduct(
          name: draft.name,
          price: draft.price,
          description: draft.description,
          categoryId: draft.categoryId,
        );
      } else {
        await widget.repository.replaceProduct(
          id: existing.id,
          name: draft.name,
          price: draft.price,
          description: draft.description,
          categoryId: draft.categoryId,
        );
      }
      await _load(initial: false);
      return null;
    } catch (error) {
      return _errorMessage(error);
    }
  }

  Future<String?> _saveCategory(
    _CategoryDraft draft, {
    Category? existing,
  }) async {
    try {
      if (existing == null) {
        await widget.repository.createCategory(
          name: draft.name,
          description: draft.description,
        );
      } else {
        await widget.repository.replaceCategory(
          id: existing.id,
          name: draft.name,
          description: draft.description,
        );
      }
      await _load(initial: false);
      return null;
    } catch (error) {
      return _errorMessage(error);
    }
  }

  Future<void> _deleteProduct(Product product) async {
    final confirmed = await _confirmDelete(
      context,
      title: 'Xóa sản phẩm này?',
      message: product.name,
    );
    if (confirmed != true) return;
    await _perform(() => widget.repository.deleteProduct(product.id));
  }

  Future<void> _deleteCategory(Category category) async {
    final confirmed = await _confirmDelete(
      context,
      title: 'Xóa danh mục này?',
      message:
          '${category.name}\nSản phẩm vẫn được giữ và bỏ liên kết danh mục.',
    );
    if (confirmed != true) return;
    await _perform(() => widget.repository.deleteCategory(category.id));
  }

  Future<void> _perform(Future<void> Function() action) async {
    setState(() {
      _saving = true;
      _loadError = null;
    });
    try {
      await action();
      await _load(initial: false);
      if (mounted) _showMessage('Đã cập nhật dữ liệu.');
    } catch (error) {
      if (mounted) _showMessage(_errorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createProduct() async {
    final saved = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => _ProductEditor(
        categories: _categories,
        onSave: (draft) => _saveProduct(draft),
      ),
    );
    if (saved == true && mounted) _showMessage('Đã tạo sản phẩm.');
  }

  Future<void> _editProduct(Product product) async {
    final saved = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => _ProductEditor(
        categories: _categories,
        product: product,
        onSave: (draft) => _saveProduct(draft, existing: product),
      ),
    );
    if (saved == true && mounted) _showMessage('Đã lưu sản phẩm.');
  }

  Future<void> _createCategory() async {
    final saved = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) =>
          _CategoryEditor(onSave: (draft) => _saveCategory(draft)),
    );
    if (saved == true && mounted) _showMessage('Đã tạo danh mục.');
  }

  Future<void> _editCategory(Category category) async {
    final saved = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => _CategoryEditor(
        category: category,
        onSave: (draft) => _saveCategory(draft, existing: category),
      ),
    );
    if (saved == true && mounted) _showMessage('Đã lưu danh mục.');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      icon: Icon(Icons.inventory_2_outlined),
                      label: Text('Sản phẩm'),
                    ),
                    ButtonSegment(
                      value: 1,
                      icon: Icon(Icons.category_outlined),
                      label: Text('Danh mục'),
                    ),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (selection) =>
                      setState(() => _tab = selection.first),
                ),
              ),
              IconButton(
                tooltip: 'Tải lại dữ liệu',
                onPressed: _saving ? null : () => _load(),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
        if (_loadError != null)
          MaterialBanner(
            content: Text(_loadError!),
            leading: const Icon(Icons.wifi_off_outlined),
            actions: [
              TextButton(
                onPressed: () => _load(),
                child: const Text('Thử lại'),
              ),
              TextButton(
                onPressed: () => setState(() => _loadError = null),
                child: const Text('Đóng'),
              ),
            ],
          ),
        if (_saving) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [
              _ProductList(
                products: _products,
                categories: _categories,
                canManage: widget.canManage,
                onCreate: _createProduct,
                onEdit: _editProduct,
                onDelete: _deleteProduct,
              ),
              _CategoryList(
                categories: _categories,
                canManage: widget.canManage,
                onCreate: _createCategory,
                onEdit: _editCategory,
                onDelete: _deleteCategory,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProductList extends StatelessWidget {
  const _ProductList({
    required this.products,
    required this.categories,
    required this.canManage,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Product> products;
  final List<Category> categories;
  final bool canManage;
  final VoidCallback onCreate;
  final ValueChanged<Product> onEdit;
  final ValueChanged<Product> onDelete;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
    children: [
      SectionTitle(
        'Sản phẩm',
        trailing: canManage
            ? FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Thêm'),
              )
            : null,
      ),
      const SizedBox(height: 12),
      if (products.isEmpty)
        const _EmptyCatalog(message: 'Chưa có sản phẩm nào.')
      else
        for (final product in products)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          style: const TextStyle(
                            color: ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        product.price.toStringAsFixed(2),
                        style: const TextStyle(
                          color: demoBlue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  if (product.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(product.description),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: StatusTag(
                          _categoryName(product.categoryId, categories),
                        ),
                      ),
                      if (canManage) ...[
                        IconButton(
                          tooltip: 'Sửa ${product.name}',
                          onPressed: () => onEdit(product),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Xóa ${product.name}',
                          onPressed: () => onDelete(product),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ] else
                        TextButton.icon(
                          onPressed: () =>
                              _showProductDetails(context, product),
                          icon: const Icon(Icons.info_outline, size: 18),
                          label: const Text('Chi tiết'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    ],
  );
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({
    required this.categories,
    required this.canManage,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Category> categories;
  final bool canManage;
  final VoidCallback onCreate;
  final ValueChanged<Category> onEdit;
  final ValueChanged<Category> onDelete;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
    children: [
      SectionTitle(
        'Danh mục',
        trailing: canManage
            ? FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Thêm'),
              )
            : null,
      ),
      const SizedBox(height: 12),
      if (categories.isEmpty)
        const _EmptyCatalog(message: 'Chưa có danh mục nào.')
      else
        for (final category in categories)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFEEF3FF),
                foregroundColor: demoBlue,
                child: Icon(Icons.category_outlined),
              ),
              title: Text(
                category.name,
                style: const TextStyle(color: ink, fontWeight: FontWeight.w700),
              ),
              subtitle: category.description.isEmpty
                  ? null
                  : Text(category.description),
              trailing: canManage
                  ? Wrap(
                      children: [
                        IconButton(
                          tooltip: 'Sửa ${category.name}',
                          onPressed: () => onEdit(category),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Xóa ${category.name}',
                          onPressed: () => onDelete(category),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    )
                  : TextButton(
                      onPressed: () => _showCategoryDetails(context, category),
                      child: const Text('Chi tiết'),
                    ),
            ),
          ),
    ],
  );
}

class _ProductEditor extends StatefulWidget {
  const _ProductEditor({
    required this.categories,
    required this.onSave,
    this.product,
  });

  final List<Category> categories;
  final Product? product;
  final Future<String?> Function(_ProductDraft draft) onSave;

  @override
  State<_ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<_ProductEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late String? _categoryId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.product?.name ?? '');
    _description = TextEditingController(
      text: widget.product?.description ?? '',
    );
    _price = TextEditingController(
      text: widget.product?.price.toString() ?? '',
    );
    final initialCategoryId = widget.product?.categoryId;
    _categoryId = widget.categories.any((c) => c.id == initialCategoryId)
        ? initialCategoryId
        : null;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onSave(
      _ProductDraft(
        name: _name.text.trim(),
        description: _description.text.trim(),
        price: double.parse(_price.text.trim()),
        categoryId: _categoryId,
      ),
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.product == null ? 'Thêm sản phẩm' : 'Sửa sản phẩm'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) _FormError(_error!),
              TextFormField(
                controller: _name,
                autofocus: true,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Tên sản phẩm'),
                validator: (value) => (value?.trim().isNotEmpty ?? false)
                    ? null
                    : 'Nhập tên sản phẩm.',
              ),
              TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Giá'),
                validator: (value) {
                  final price = double.tryParse(value?.trim() ?? '');
                  if (price == null || !price.isFinite || price < 0) {
                    return 'Nhập số hợp lệ lớn hơn hoặc bằng 0.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _description,
                maxLength: 2000,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Mô tả'),
              ),
              DropdownButtonFormField<String?>(
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Danh mục'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Không có danh mục'),
                  ),
                  for (final category in widget.categories)
                    DropdownMenuItem<String?>(
                      value: category.id,
                      child: Text(category.name),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _categoryId = value),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: _busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Lưu'),
      ),
    ],
  );
}

class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({required this.onSave, this.category});

  final Category? category;
  final Future<String?> Function(_CategoryDraft draft) onSave;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.category?.name ?? '');
    _description = TextEditingController(
      text: widget.category?.description ?? '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onSave(
      _CategoryDraft(
        name: _name.text.trim(),
        description: _description.text.trim(),
      ),
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.category == null ? 'Thêm danh mục' : 'Sửa danh mục'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) _FormError(_error!),
            TextFormField(
              controller: _name,
              autofocus: true,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Tên danh mục'),
              validator: (value) => (value?.trim().isNotEmpty ?? false)
                  ? null
                  : 'Nhập tên danh mục.',
            ),
            TextFormField(
              controller: _description,
              maxLength: 2000,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Mô tả'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: _busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Lưu'),
      ),
    ],
  );
}

class _ProductDraft {
  const _ProductDraft({
    required this.name,
    required this.description,
    required this.price,
    required this.categoryId,
  });

  final String name;
  final String description;
  final double price;
  final String? categoryId;
}

class _CategoryDraft {
  const _CategoryDraft({required this.name, required this.description});

  final String name;
  final String description;
}

class _FormError extends StatelessWidget {
  const _FormError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4ED),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(
      message,
      style: const TextStyle(color: Color(0xFFB54708), fontSize: 13),
    ),
  );
}

class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.inventory_2_outlined, color: muted, size: 28),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

String _categoryName(String? id, List<Category> categories) {
  if (id == null) return 'Chưa có danh mục';
  for (final category in categories) {
    if (category.id == id) return category.name;
  }
  return 'Chưa có danh mục';
}

Future<bool?> _confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) => showDialog<bool>(
  context: context,
  useRootNavigator: false,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: Text(message),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Hủy'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Xóa'),
      ),
    ],
  ),
);

Future<void> _showProductDetails(BuildContext context, Product product) =>
    showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: Text(product.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Giá: ${product.price.toStringAsFixed(2)}'),
            const SizedBox(height: 8),
            Text(
              product.description.isEmpty
                  ? 'Chưa có mô tả.'
                  : product.description,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );

Future<void> _showCategoryDetails(BuildContext context, Category category) =>
    showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: Text(category.name),
        content: Text(
          category.description.isEmpty
              ? 'Chưa có mô tả.'
              : category.description,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );

String _errorMessage(Object error) => error is ApiException
    ? error.userMessage
    : 'Thao tác chưa hoàn tất. Hãy thử lại.';

String _roleLabel(AppRole? role) => role == AppRole.admin ? 'Admin' : 'User';

String _initials(String username) =>
    username.isEmpty ? '?' : username.substring(0, 1).toUpperCase();
