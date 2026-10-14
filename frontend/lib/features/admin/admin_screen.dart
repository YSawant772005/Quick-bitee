import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../shared/widgets.dart';
import '../../state/auth_controller.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  static const _statuses = [
    '',
    'PENDING',
    'PAID',
    'CONFIRMED',
    'DRIVER_ASSIGNED',
    'PAYMENT_FAILED',
    'FAILED',
  ];

  String _statusFilter = '';
  int _page = 1;
  static const _pageSize = 20;

  AdminSummary? _summary;
  Paginated<OrderListItem>? _orders;
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
      final api = ref.read(apiClientProvider);
      final summary = await api.adminSummary();
      final orders = await api.adminOrders(
        page: page,
        pageSize: _pageSize,
        status: _statusFilter.isEmpty ? null : _statusFilter,
      );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _orders = orders;
        _page = orders.page;
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
    final summary = _summary;
    final orders = _orders;
    return Scaffold(
      appBar: AppBar(title: const Text('Admin overview')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(
                  message: _error is ApiException ? (_error! as ApiException).message : 'Could not load dashboard.',
                  onRetry: () => _load(page: _page),
                )
              : RefreshIndicator(
                  onRefresh: () => _load(page: 1),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (summary != null) ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _MetricCard(label: 'Total orders', value: '${summary.totalOrders}'),
                            for (final entry in summary.byStatus.entries)
                              _MetricCard(
                                label: entry.key.replaceAll('_', ' '),
                                value: '${entry.value}',
                                color: statusColor(entry.key),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _MetricCard(label: 'Pending outbox', value: '${summary.pendingOutbox}'),
                            _MetricCard(label: 'Retry backlog', value: '${summary.retryBacklog}'),
                            _MetricCard(
                              label: 'Quarantined',
                              value: '${summary.quarantineCount}',
                              color: summary.quarantineCount > 0
                                  ? const Color(0xFFB91C1C)
                                  : const Color(0xFF15803D),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      Row(
                        children: [
                          Text('Orders', style: Theme.of(context).textTheme.titleMedium),
                          const Spacer(),
                          DropdownButton<String>(
                            value: _statusFilter,
                            items: [
                              for (final s in _statuses)
                                DropdownMenuItem(
                                  value: s,
                                  child: Text(s.isEmpty ? 'All statuses' : s.replaceAll('_', ' ')),
                                ),
                            ],
                            onChanged: (v) {
                              setState(() => _statusFilter = v ?? '');
                              _load(page: 1);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (orders == null || orders.items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: EmptyState(
                            icon: Icons.inbox_outlined,
                            title: 'No orders match',
                          ),
                        )
                      else ...[
                        for (final order in orders.items)
                          Card(
                            child: ListTile(
                              dense: true,
                              title: Text(
                                '#${order.id.substring(0, 8)} — ${order.restaurantName.isEmpty ? 'QuickBite' : order.restaurantName}',
                              ),
                              subtitle: Text(order.itemSummary, maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  StatusChip(status: order.status),
                                  const SizedBox(height: 4),
                                  Text(formatMinor(order.totalMinor),
                                      style: Theme.of(context).textTheme.bodySmall),
                                ],
                              ),
                              onTap: () => context.push('/orders/${order.id}'),
                            ),
                          ),
                        if (orders.totalPages > 1)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.chevron_left),
                                  onPressed: _page > 1 ? () => _load(page: _page - 1) : null,
                                ),
                                Text('Page $_page of ${orders.totalPages}'),
                                IconButton(
                                  icon: const Icon(Icons.chevron_right),
                                  onPressed: _page < orders.totalPages ? () => _load(page: _page + 1) : null,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? const Color(0xFF7C2D12);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: effectiveColor, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
