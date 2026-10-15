import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../../state/auth_controller.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

/// Options for the restaurant filter, loaded independently of the Restaurants
/// page so this screen never shows a stale or partial list.
final _restaurantOptionsProvider = FutureProvider.autoDispose<List<AdminRestaurant>>((ref) async {
  ref.watch(adminRefreshTokenProvider);
  final page = await ref.watch(apiClientProvider).adminRestaurants(page: 1, pageSize: 100);
  return page.items;
});

/// `/admin/menu` — dish-level management.
///
/// Backed by `GET/PATCH /admin/menu-items`. There is no create endpoint, so no
/// "Add dish" control is offered (see Settings → Known gaps).
class AdminMenuPage extends ConsumerStatefulWidget {
  const AdminMenuPage({super.key});

  @override
  ConsumerState<AdminMenuPage> createState() => _AdminMenuPageState();
}

class _AdminMenuPageState extends ConsumerState<AdminMenuPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  AdminCatalogQuery _query = const AdminCatalogQuery();

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _update(AdminCatalogQuery next) => setState(() => _query = next);

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _update(_query.filtered(search: value, clearSearch: value.isEmpty));
    });
  }

  void _reload() => ref.invalidate(adminMenuItemsProvider(_query));

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(adminMenuItemsProvider(_query));
    final restaurants = ref.watch(_restaurantOptionsProvider);

    final restaurantName = {
      for (final r in restaurants.valueOrNull ?? const <AdminRestaurant>[]) r.id: r.name,
    };

    return AdminPage(
      title: 'Menu management',
      description: 'Prices, availability and sales performance for every dish.',
      actions: [AdminRefreshButton(onPressed: () => refreshAdminData(ref))],
      child: AdminSection(
        title: 'Dishes',
        subtitle: 'Includes dishes currently hidden from customers',
        padding: EdgeInsets.zero,
        trailing: const SizedBox.shrink(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AdminSearchField(
                    controller: _search,
                    onChanged: _onSearch,
                    hintText: 'Search dish name',
                    width: 250,
                  ),
                  SizedBox(
                    width: 210,
                    child: DropdownButtonFormField<String?>(
                      key: ValueKey<String?>(_query.restaurantId),
                      initialValue: _query.restaurantId,
                      isExpanded: true,
                      isDense: true,
                      style: AdminType.body,
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('All restaurants')),
                        for (final r in restaurants.valueOrNull ?? const <AdminRestaurant>[])
                          DropdownMenuItem<String?>(value: r.id, child: Text(r.name)),
                      ],
                      onChanged: (value) => _update(
                        _query.filtered(restaurantId: value, clearRestaurant: value == null),
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
                        filled: true,
                        fillColor: AdminColors.card,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AdminColors.line),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AdminColors.brand, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                  AdminDropdown<bool?>(
                    value: _query.available,
                    width: 170,
                    items: const [
                      DropdownMenuItem<bool?>(value: null, child: Text('All availability')),
                      DropdownMenuItem<bool?>(value: true, child: Text('Available')),
                      DropdownMenuItem<bool?>(value: false, child: Text('Unavailable')),
                    ],
                    onChanged: (value) =>
                        _update(_query.filtered(available: value, clearAvailable: value == null)),
                  ),
                  if (_query.search != null || _query.available != null || _query.restaurantId != null)
                    TextButton(
                      onPressed: () {
                        _search.clear();
                        _update(const AdminCatalogQuery());
                      },
                      child: const Text('Clear filters'),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              items.when(
                loading: () => const AdminLoading(label: 'Loading menu items…'),
                error: (error, _) => AdminErrorState(
                  message: error is ApiException ? error.message : '$error',
                  onRetry: _reload,
                ),
                data: (page) => _body(page, restaurantName),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(Paginated<AdminMenuItem> page, Map<String, String> restaurantName) {
    if (page.items.isEmpty) {
      return AdminEmpty(
        icon: Icons.menu_book_outlined,
        title: _query.search != null || _query.available != null || _query.restaurantId != null
            ? 'No dishes match these filters'
            : 'No dishes yet',
        message: _query.search != null || _query.available != null || _query.restaurantId != null
            ? 'Try clearing the search, restaurant or availability filter.'
            : 'Menu items appear here once they are seeded in the backend.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminTable<AdminMenuItem>(
          columns: [
            AdminColumn(
              label: 'Dish',
              flex: 3,
              cell: (context, row) => Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: AppImage(url: row.imageUrl, width: 40, height: 40, fit: BoxFit.cover, radius: 7),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AdminType.cell),
                        Text(
                          restaurantName[row.restaurantId] ?? 'Unknown restaurant',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AdminType.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            AdminColumn(
              label: 'Price',
              width: 100,
              align: TextAlign.right,
              cell: (context, row) => Text(
                formatMinor(row.priceMinor, currency: row.currency),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AdminColors.ink),
              ),
            ),
            AdminColumn(
              label: 'Units sold',
              width: 92,
              align: TextAlign.right,
              cell: (context, row) => Text('${row.unitsSold}', textAlign: TextAlign.right, style: AdminType.cell),
            ),
            AdminColumn(
              label: 'Revenue',
              width: 106,
              align: TextAlign.right,
              cell: (context, row) => Text(
                formatCompactCurrency(row.revenueMinor),
                textAlign: TextAlign.right,
                style: AdminType.cell,
              ),
            ),
            AdminColumn(
              label: 'Availability',
              width: 140,
              cell: (context, row) => Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    row.available ? 'Available' : 'Unavailable',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: row.available ? AppColors.success : AdminColors.inkMuted,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Switch(
                    value: row.available,
                    onChanged: (next) => _toggleAvailability(row, next),
                  ),
                ],
              ),
            ),
            AdminColumn(
              label: 'Actions',
              width: 84,
              cell: (context, row) => TextButton(
                onPressed: () => _openEditor(row),
                style: TextButton.styleFrom(
                  foregroundColor: AdminColors.brand,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
                child: const Text('Edit'),
              ),
            ),
          ],
          rows: page.items,
          onRowTap: _openEditor,
          cardTitle: (row) => row.name,
          cardSubtitle: (row) => restaurantName[row.restaurantId] ?? '',
        ),
        const SizedBox(height: AppSpacing.md),
        PaginationBar(
          page: page.page,
          pageSize: page.pageSize,
          total: page.total,
          onPageChanged: (next) => _update(_query.copyWith(page: next)),
          onPageSizeChanged: (size) => _update(_query.copyWith(pageSize: size, page: 1)),
        ),
      ],
    );
  }

  Future<void> _toggleAvailability(AdminMenuItem item, bool next) async {
    if (!next) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Hide ${item.name}?'),
          content: Text(
            'Hiding this dish removes it from the customer menu immediately. '
            'Its price and past orders are kept.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Hide dish'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      await ref.read(apiClientProvider).adminUpdateMenuItem(item.id, available: next);
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(next ? '${item.name} is available' : '${item.name} is hidden')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openEditor(AdminMenuItem item) async {
    final updated = await showDialog<AdminMenuItem>(
      context: context,
      builder: (_) => _MenuItemEditor(item: item),
    );
    if (updated == null) return;
    _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${updated.name} updated')),
    );
  }
}

/// Mirrors `PATCH /admin/menu-items/{id}`: price is entered in rupees and
/// stored in minor units, within the backend's 0 – 10,000,000 limit.
class _MenuItemEditor extends ConsumerStatefulWidget {
  const _MenuItemEditor({required this.item});

  final AdminMenuItem item;

  @override
  ConsumerState<_MenuItemEditor> createState() => _MenuItemEditorState();
}

class _MenuItemEditorState extends ConsumerState<_MenuItemEditor> {
  static const _maxPriceMinor = 10000000;

  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _description;
  late final TextEditingController _image;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.item.name);
    _price = TextEditingController(text: (widget.item.priceMinor / 100).toStringAsFixed(2));
    _description = TextEditingController(text: widget.item.description);
    _image = TextEditingController(text: widget.item.imageUrl);
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _description.dispose();
    _image.dispose();
    super.dispose();
  }

  int? _parsePrice() {
    final raw = _price.text.trim().replaceAll(',', '');
    final value = double.tryParse(raw);
    if (value == null) return null;
    final minor = (value * 100).round();
    if (minor < 0 || minor > _maxPriceMinor) return null;
    return minor;
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final price = _parsePrice();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    if (price == null) {
      setState(() => _error = 'Enter a price between ₹0 and ₹${(_maxPriceMinor / 100).toStringAsFixed(0)}.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await ref.read(apiClientProvider).adminUpdateMenuItem(
            widget.item.id,
            name: name,
            priceMinor: price,
            description: _description.text.trim(),
            imageUrl: _image.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.item.name}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name (required)'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Price (₹, required)',
                  helperText: 'Saved in minor units (paise) on the server.',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _image,
                decoration: const InputDecoration(labelText: 'Image URL'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _description,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save changes'),
        ),
      ],
    );
  }
}
