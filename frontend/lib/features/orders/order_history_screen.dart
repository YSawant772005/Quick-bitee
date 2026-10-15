import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';
import '../../shared/layout.dart';
import '../../shared/theme.dart';
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
  int _total = 0;
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
        _total = data.total;
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
    return CustomerShell(
      navIndex: 3,
      title: 'Your orders',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(
                  message: _error is ApiException ? (_error! as ApiException).message : 'Could not load orders.',
                  onRetry: () => _load(page: _page),
                )
              : _orders.isEmpty
                  ? EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No orders yet',
                      subtitle: 'Your placed orders will appear here with their dishes and status.',
                      action: FilledButton.icon(
                        onPressed: () => context.go('/explore'),
                        icon: const Icon(Icons.restaurant_menu, size: 19),
                        label: const Text('Start an order'),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _load(page: 1),
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                        children: [
                          ContentWidth(
                            maxWidth: 900,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: AppSpacing.lg),
                                Text('Your orders', style: Theme.of(context).textTheme.headlineSmall),
                                const SizedBox(height: 4),
                                Text('$_total order${_total == 1 ? '' : 's'} placed',
                                    style: Theme.of(context).textTheme.bodyMedium),
                                const SizedBox(height: AppSpacing.xl),
                                for (final order in _orders) ...[
                                  _OrderRow(order: order, onTap: () => context.push('/orders/${order.id}')),
                                  const SizedBox(height: AppSpacing.md),
                                ],
                                if (_totalPages > 1)
                                  _Pager(
                                    page: _page,
                                    totalPages: _totalPages,
                                    onPrev: _page > 1 ? () => _load(page: _page - 1) : null,
                                    onNext: _page < _totalPages ? () => _load(page: _page + 1) : null,
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

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order, required this.onTap});

  final OrderListItem order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('d MMM yyyy, HH:mm').format(order.createdAt.toLocal());
    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppImage(url: order.thumbnailUrl, height: 72, width: 72, radius: AppRadius.md),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          order.restaurantName.isEmpty ? 'QuickBitee' : order.restaurantName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      StatusChip(status: order.status),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(order.itemSummary.isEmpty ? 'Order items' : order.itemSummary,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(date, style: Theme.of(context).textTheme.bodySmall),
                      const Spacer(),
                      PriceText(minor: order.totalMinor, currency: order.currency, size: 15),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({required this.page, required this.totalPages, this.onPrev, this.onNext});

  final int page;
  final int totalPages;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left_rounded, size: 18),
            label: const Text('Previous'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text('Page $page of $totalPages',
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          ),
          OutlinedButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded, size: 18),
            label: const Text('Next'),
          ),
        ],
      ),
    );
  }
}
