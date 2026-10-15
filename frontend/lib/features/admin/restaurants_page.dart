import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../../state/auth_controller.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

/// `/admin/restaurants` — catalogue management.
///
/// Backed by `GET/PATCH /admin/restaurants`. The backend exposes no create or
/// delete endpoint for restaurants, so no "Add restaurant" control is shown —
/// see Settings → Known gaps.
class AdminRestaurantsPage extends ConsumerStatefulWidget {
  const AdminRestaurantsPage({super.key});

  @override
  ConsumerState<AdminRestaurantsPage> createState() => _AdminRestaurantsPageState();
}

class _AdminRestaurantsPageState extends ConsumerState<AdminRestaurantsPage> {
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

  void _reload() => ref.invalidate(adminRestaurantsProvider(_query));

  @override
  Widget build(BuildContext context) {
    final restaurants = ref.watch(adminRestaurantsProvider(_query));

    return AdminPage(
      title: 'Restaurants',
      description: 'Open or close venues and keep their details accurate.',
      actions: [AdminRefreshButton(onPressed: () => refreshAdminData(ref))],
      child: AdminSection(
        title: 'All restaurants',
        subtitle: 'Includes venues currently closed to customers',
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
                    hintText: 'Search name or cuisine',
                    width: 280,
                  ),
                  AdminDropdown<bool?>(
                    value: _query.available,
                    width: 180,
                    items: const [
                      DropdownMenuItem<bool?>(value: null, child: Text('All availability')),
                      DropdownMenuItem<bool?>(value: true, child: Text('Open')),
                      DropdownMenuItem<bool?>(value: false, child: Text('Closed')),
                    ],
                    onChanged: (value) =>
                        _update(_query.filtered(available: value, clearAvailable: value == null)),
                  ),
                  if (_query.search != null || _query.available != null)
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
              restaurants.when(
                loading: () => const AdminLoading(label: 'Loading restaurants…'),
                error: (error, _) => AdminErrorState(
                  message: error is ApiException ? error.message : '$error',
                  onRetry: _reload,
                ),
                data: (page) => _body(page),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(Paginated<AdminRestaurant> page) {
    if (page.items.isEmpty) {
      return AdminEmpty(
        icon: Icons.storefront_outlined,
        title: _query.search != null || _query.available != null
            ? 'No restaurants match these filters'
            : 'No restaurants yet',
        message: _query.search != null || _query.available != null
            ? 'Try clearing the search or availability filter.'
            : 'Restaurants appear here once they are seeded in the backend.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminTable<AdminRestaurant>(
          columns: [
            AdminColumn(
              label: 'Restaurant',
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
                          row.cuisine.isEmpty ? 'No cuisine set' : row.cuisine,
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
              label: 'Menu',
              width: 130,
              cell: (context, row) => Text(
                '${row.availableItemCount} of ${row.menuItemCount} available',
                style: AdminType.cell,
              ),
            ),
            AdminColumn(
              label: 'Orders',
              width: 84,
              align: TextAlign.right,
              cell: (context, row) => Text('${row.orderCount}', textAlign: TextAlign.right, style: AdminType.cell),
            ),
            AdminColumn(
              label: 'Revenue',
              width: 110,
              align: TextAlign.right,
              cell: (context, row) => Text(
                formatCompactCurrency(row.revenueMinor),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AdminColors.ink),
              ),
            ),
            AdminColumn(
              label: 'Availability',
              width: 132,
              cell: (context, row) => Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    row.available ? 'Open' : 'Closed',
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
          cardSubtitle: (row) => row.cuisine.isEmpty ? 'No cuisine set' : row.cuisine,
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

  Future<void> _toggleAvailability(AdminRestaurant restaurant, bool next) async {
    if (!next) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Close ${restaurant.name}?'),
          content: Text(
            'Closing removes ${restaurant.name} from the customer catalogue immediately. '
            'Its menu and history are kept.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Close restaurant'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      await ref.read(apiClientProvider).adminUpdateRestaurant(restaurant.id, available: next);
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(next ? '${restaurant.name} is open' : '${restaurant.name} is now closed')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openEditor(AdminRestaurant restaurant) async {
    final updated = await showDialog<AdminRestaurant>(
      context: context,
      builder: (_) => _RestaurantEditor(restaurant: restaurant),
    );
    if (updated == null) return;
    _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${updated.name} updated')),
    );
  }
}

/// Edit form following the backend's `PATCH /admin/restaurants/{id}` contract:
/// only fields the API accepts are offered, with the same validation limits.
class _RestaurantEditor extends ConsumerStatefulWidget {
  const _RestaurantEditor({required this.restaurant});

  final AdminRestaurant restaurant;

  @override
  ConsumerState<_RestaurantEditor> createState() => _RestaurantEditorState();
}

class _RestaurantEditorState extends ConsumerState<_RestaurantEditor> {
  late final TextEditingController _name;
  late final TextEditingController _cuisine;
  late final TextEditingController _description;
  late final TextEditingController _image;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.restaurant.name);
    _cuisine = TextEditingController(text: widget.restaurant.cuisine);
    _description = TextEditingController(text: widget.restaurant.description);
    _image = TextEditingController(text: widget.restaurant.imageUrl);
  }

  @override
  void dispose() {
    _name.dispose();
    _cuisine.dispose();
    _description.dispose();
    _image.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await ref.read(apiClientProvider).adminUpdateRestaurant(
            widget.restaurant.id,
            name: name,
            cuisine: _cuisine.text.trim(),
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
      title: Text('Edit ${widget.restaurant.name}'),
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
                controller: _cuisine,
                decoration: const InputDecoration(labelText: 'Cuisine'),
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
