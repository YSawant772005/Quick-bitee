import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../shared/widgets.dart';
import '../../state/auth_controller.dart';
import '../../state/cart_controller.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _search = '';
  Paginated<Restaurant>? _data;
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
      final data = await ref.read(apiClientProvider).restaurants(pageSize: 50, search: _search);
      if (mounted) setState(() => _data = data);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Network error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final user = (ref.watch(authControllerProvider) as SignedIn).user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('QuickBite', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFC2410C))),
        actions: [
          if (user.role == 'admin')
            IconButton(
              tooltip: 'Admin dashboard',
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onPressed: () => context.go('/admin'),
            ),
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push('/notifications'),
          ),
          IconButton(
            tooltip: 'Order history',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => context.push('/orders'),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      floatingActionButton: cart.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/cart'),
              icon: Badge(
                label: Text('${cart.totalQuantity}'),
                child: const Icon(Icons.shopping_cart_outlined),
              ),
              label: Text(formatMinor(cart.subtotalMinor)),
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Semantics(
              label: 'Search restaurants',
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search restaurants…',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => _search = v,
                onSubmitted: (_) => _load(),
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              ...List.generate(
                4,
                (_) => const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(height: 140),
                          SizedBox(height: 12),
                          SkeletonBox(height: 18, width: 200),
                          SizedBox(height: 8),
                          SkeletonBox(height: 14, width: 280),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else if (_error != null)
              ErrorState(message: _error!, onRetry: _load)
            else if (_data!.items.isEmpty)
              const EmptyState(
                icon: Icons.storefront_outlined,
                title: 'No restaurants found',
                subtitle: 'Try a different search, or pull to refresh.',
              )
            else
              ..._data!.items.map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => context.push('/restaurant/${r.id}'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppImage(url: r.imageUrl, height: 150),
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(r.name,
                                              style: Theme.of(context).textTheme.titleMedium),
                                        ),
                                        if (!r.available) const StatusChip(status: 'CLOSED'),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(r.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFEDD5),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(r.cuisine,
                                          style: const TextStyle(
                                              color: Color(0xFF9A3412),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
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
