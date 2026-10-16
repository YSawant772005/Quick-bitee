import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'orders_table.dart';

/// `/admin/orders` — fulfilment management, distinct from the customer's
/// order history: period-wide counts, filtering and server-side paging over
/// every restaurant.
class AdminOrdersPage extends ConsumerWidget {
  const AdminOrdersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Honour deep links such as /admin/orders?status=PAYMENT_FAILED.
    final initialStatus = GoRouterState.of(context).uri.queryParameters['status'];
    final validInitial = adminStatuses.contains(initialStatus) ? initialStatus : null;

    final summary = ref.watch(adminSummaryProvider);

    return AdminPage(
      title: 'Orders',
      description: 'Track and manage fulfilment across every restaurant.',
      actions: [
        const DateRangeControl(compact: true),
        OutlinedButton.icon(
          onPressed: () => refreshAdminData(ref),
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Refresh'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AdminColors.ink,
            side: const BorderSide(color: AdminColors.line),
            minimumSize: const Size(0, 40),
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          summary.maybeWhen(
            data: (s) => _Counts(summary: s),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: AppSpacing.lg),
          OrdersTable(
            key: ValueKey(validInitial),
            title: 'All orders',
            subtitle: 'Scoped to the reporting period above',
            pageSize: 20,
            initialStatus: validInitial,
            above: (context, query, update) => _ActiveFilters(query: query, update: update),
          ),
        ],
      ),
    );
  }
}

/// Period-scoped status counts. Each chip is a filter link, so the numbers
/// above the table and the table itself always agree.
class _Counts extends StatelessWidget {
  const _Counts({required this.summary});

  final AdminSummary summary;

  @override
  Widget build(BuildContext context) {
    final populated = adminStatuses.where((s) => summary.countOf(s) > 0).toList();

    return AdminCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _CountTile(
            label: 'Total',
            value: summary.totalOrders,
            color: AdminColors.brand,
            highlighted: false,
          ),
          const SizedBox(width: AppSpacing.xs),
          for (final status in adminStatuses)
            _CountTile(
              label: adminStatusLabel(status),
              value: summary.countOf(status),
              color: statusColor(status),
              highlighted: false,
              muted: summary.countOf(status) == 0,
            ),
          if (populated.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: Text(
                'No orders in this period — totals update as customers order.',
                style: AdminType.caption,
              ),
            ),
        ],
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.label,
    required this.value,
    required this.color,
    required this.highlighted,
    this.muted = false,
  });

  final String label;
  final int value;
  final Color color;
  final bool highlighted;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final effective = muted ? AdminColors.inkMuted : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: highlighted ? effective.withValues(alpha: 0.12) : AdminColors.metricFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: highlighted ? effective : AdminColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: effective, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: muted ? AdminColors.inkMuted : AdminColors.inkSoft),
            ),
          ),
          const SizedBox(width: 8),
          Text('$value', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: effective)),
        ],
      ),
    );
  }
}

/// Shows which filters are currently narrowing the table and offers a reset.
class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({required this.query, required this.update});

  final AdminOrdersQuery query;
  final void Function(AdminOrdersQuery) update;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (query.status != null)
        _FilterChip(
          label: 'Status: ${adminStatusLabel(query.status!)}',
          onClear: () => update(query.filtered(clearStatus: true)),
        ),
      if (query.search != null && query.search!.isNotEmpty)
        _FilterChip(
          label: 'Search: ${query.search}',
          onClear: () => update(query.filtered(clearSearch: true)),
        ),
    ];

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Filtering by', style: AdminType.label),
        ...chips,
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.onClear});

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: AdminColors.brand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AdminColors.ink)),
          const SizedBox(width: 4),
          InkWell(
            onTap: onClear,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.close_rounded, size: 14, color: AdminColors.inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}
