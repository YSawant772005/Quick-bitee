import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../shared/widgets.dart';
import '../../state/auth_controller.dart';

class OrderHistoryScreen extends ConsumerStatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  ConsumerState<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends ConsumerState<OrderHistoryScreen> {
  static const _pageSize = 10;

  List<OrderListItem> _orders = const [];
  int _page = 1;
  int _totalPages = 1;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load(page: 1);
  }

  Future<void> _load({required int page}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(apiClientProvider).orders(page: page, pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        _orders = data.items;
        _page = data.page;
        _totalPages = data.totalPages;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Order history')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(
                  message: _error is ApiException ? (_error! as ApiException).message : 'Could not load orders.',
                  onRetry: () => _load(page: _page),
                )
              : _orders.isEmpty
                  ? const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No orders yet',
                      subtitle: 'Your placed orders will appear here.',
                    )
                  : RefreshIndicator(
                      onRefresh: () => _load(page: 1),
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          for (final order in _orders)
                            Card(
                              child: ListTile(
                                leading: const CircleAvatar(child: Icon(Icons.receipt)),
                                title: Text(order.restaurantName.isEmpty
                                    ? 'Order #${order.id.substring(0, 8)}'
                                    : order.restaurantName),
                                subtitle: Text(
                                  '${order.itemSummary} · ${formatMinor(order.totalMinor)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    StatusChip(status: order.status),
                                    const SizedBox(height: 4),
                                    Text(
                                      MaterialLocalizations.of(context)
                                          .formatShortDate(order.createdAt.toLocal()),
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                                onTap: () => context.push('/orders/${order.id}'),
                              ),
                            ),
                          if (_totalPages > 1)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.chevron_left),
                                    onPressed: _page > 1 ? () => _load(page: _page - 1) : null,
                                  ),
                                  Text('Page $_page of $_totalPages'),
                                  IconButton(
                                    icon: const Icon(Icons.chevron_right),
                                    onPressed: _page < _totalPages ? () => _load(page: _page + 1) : null,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
    );
  }
}
