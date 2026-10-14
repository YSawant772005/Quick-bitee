import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../shared/widgets.dart';
import '../../state/auth_controller.dart';
import '../../state/cart_controller.dart';

class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key, required this.restaurantId});

  final String restaurantId;

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  Restaurant? _restaurant;
  Paginated<MenuItem>? _menu;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final restaurants = await api.restaurants(pageSize: 100);
      _restaurant = restaurants.items.where((r) => r.id == widget.restaurantId).firstOrNull;
      _menu = await api.menu(widget.restaurantId);
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Network error';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addToCart(MenuItem item) async {
    final cart = ref.read(cartProvider.notifier);
    try {
      cart.add(item);
    } on CartRestaurantMismatch {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Start a new cart?'),
          content: Text('Your cart has items from another restaurant. Replace them with ${item.name}?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Replace')),
          ],
        ),
      );
      if (replace == true) cart.replaceRestaurant(item);
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${item.name} added to cart')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_restaurant?.name ?? 'Menu'),
        actions: [
          IconButton(
            tooltip: 'Cart',
            icon: Badge(
              isLabelVisible: cart.totalQuantity > 0,
              label: Text('${cart.totalQuantity}'),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
            onPressed: () => context.push('/cart'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_restaurant != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: AppImage(url: _restaurant!.imageUrl, height: 160),
                        ),
                        const SizedBox(height: 12),
                        Text(_restaurant!.description, style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 16),
                      ],
                      if (_menu!.items.isEmpty)
                        const EmptyState(icon: Icons.restaurant_menu, title: 'No menu items')
                      else
                        ..._menu!.items.map(
                              (item) => Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(item.name,
                                                style: Theme.of(context).textTheme.titleSmall),
                                            const SizedBox(height: 4),
                                            Text(item.description,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context).textTheme.bodySmall),
                                            const SizedBox(height: 8),
                                            Text(
                                              formatMinor(item.priceMinor, currency: item.currency),
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFFC2410C)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
                                            child: AppImage(url: item.imageUrl, height: 84, width: 84),
                                          ),
                                          const SizedBox(height: 8),
                                          if (!item.available)
                                            const Text('Unavailable',
                                                style: TextStyle(color: Color(0xFFB91C1C), fontSize: 12))
                                          else
                                            FilledButton.tonalIcon(
                                              onPressed: () => _addToCart(item),
                                              icon: const Icon(Icons.add, size: 18),
                                              label: const Text('Add'),
                                              style: FilledButton.styleFrom(
                                                  minimumSize: const Size(84, 36)),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
    );
  }
}
