import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../shared/charts.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../../state/admin_range_controller.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'orders_table.dart';

/// `/admin` — the operational landing page.
///
/// Every number here comes from the period currently selected in the header,
/// and every panel links through to the list that produced it.
class AdminOverviewPage extends ConsumerWidget {
  const AdminOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(adminSummaryProvider);

    return AdminPage(
      title: 'Operations overview',
      description: summary.maybeWhen(
        data: (s) => s.dateFrom == null
            ? 'All recorded activity.'
            : 'Performance for ${s.dateFrom} to ${s.dateTo}, compared with the previous period.',
        orElse: () => 'Orders, revenue and catalogue health.',
      ),
      actions: [
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
          summary.when(
            loading: () => const AdminLoading(label: 'Loading the reporting period…'),
            error: (error, _) => AdminErrorState(
              message: error is ApiException ? error.message : '$error',
              onRetry: () => ref.invalidate(adminSummaryProvider),
            ),
            data: (s) => _SummaryBody(summary: s),
          ),
          const SizedBox(height: AppSpacing.lg),
          const OrdersTable(
            title: 'Recent orders',
            subtitle: 'Newest first · scoped to the reporting period in the header',
            pageSize: 10,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// KPIs, charts, attention and rankings
// ---------------------------------------------------------------------------

class _SummaryBody extends ConsumerWidget {
  const _SummaryBody({required this.summary});

  final AdminSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = summary;
    final period = ref.watch(adminRangeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- KPIs -----------------------------------------------------------
        AdminGrid(
          minItemWidth: 236,
          children: [
            MetricCard(
              label: 'Total orders',
              value: s.totalOrders.toString(),
              delta: s.comparison?.orders,
              caption: s.successfulOrders > 0 || s.failedOrders > 0
                  ? '${s.successfulOrders} realised · ${s.failedOrders} failed'
                  : 'No completed orders yet',
              onTap: () => context.go('/admin/orders'),
            ),
            MetricCard(
              label: 'Revenue (INR)',
              value: formatMinor(s.totalRevenueMinor, currency: s.currency),
              delta: s.comparison?.revenue,
              caption: s.successfulOrders > 0
                  ? 'from ${s.successfulOrders} paid orders'
                  : 'Revenue counts completed orders only',
              onTap: () => context.go('/admin/analytics'),
            ),
            MetricCard(
              label: 'Active customers',
              value: s.activeCustomers.toString(),
              delta: s.comparison?.customers,
              caption: 'ordered in this period · ${s.totalCustomers} registered',
              onTap: () => context.go('/admin/customers'),
            ),
            MetricCard(
              label: 'Avg order value',
              value: formatMinor(s.avgOrderValueMinor, currency: s.currency),
              delta: s.comparison?.aov,
              caption: s.successfulOrders > 0
                  ? 'across ${s.successfulOrders} realised orders'
                  : 'needs completed orders to calculate',
              onTap: () => context.go('/admin/analytics'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        // --- Charts ---------------------------------------------------------
        AdminGrid(
          minItemWidth: 340,
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.lg,
          children: [
            AdminSection(
              title: 'Revenue',
              subtitle: s.revenueByDay.isEmpty
                  ? 'No buckets returned'
                  : '${s.revenueByDay.length} ${s.granularity == 'day' ? 'days' : s.granularity == 'week' ? 'weeks' : 'months'} · ${period.label.toLowerCase()}',
              trailing: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: const [
                  Pill(label: 'INR', dense: true, color: AppColors.forest),
                  GranularityControl(compact: true),
                ],
              ),
              child: _RevenueChart(summary: s),
            ),
            AdminSection(
              title: 'Orders by status',
              subtitle: 'Real states only — select one to open its list',
              child: _StatusChart(summary: s),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        // --- Attention + rankings -------------------------------------------
        AdminGrid(
          minItemWidth: 340,
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.lg,
          children: [
            AdminSection(
              title: 'Needs attention',
              subtitle: 'Conditions that need a person to act',
              child: _NeedsAttention(summary: s),
            ),
            AdminSection(
              title: 'Best performing dishes',
              subtitle: 'Ranked by units sold in this period',
              trailing: const Text('UNITS  ·  REVENUE', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AdminColors.inkMuted)),
              child: _TopDishes(summary: s),
            ),
          ],
        ),
      ],
    );
  }
}

class _RevenueChart extends StatelessWidget {
  const _RevenueChart({required this.summary});

  final AdminSummary summary;

  @override
  Widget build(BuildContext context) {
    final rows = summary.revenueByDay;
    if (rows.isEmpty) {
      return const AdminEmpty(
        icon: Icons.show_chart_rounded,
        title: 'No revenue data for this period',
        message: 'Pick a different reporting period, or place an order to see it charted.',
      );
    }
    final hasSales = rows.any((r) => r.revenueMinor > 0);
    if (!hasSales) {
      return const AdminEmpty(
        icon: Icons.payments_outlined,
        title: 'No completed sales yet',
        message: 'Revenue counts orders that reached PAID, CONFIRMED or out-for-delivery. Orders still awaiting payment appear in the status chart.',
      );
    }
    return RevenueAreaChart(
      points: [
        for (final r in rows) ChartPoint(r.date, r.revenueMinor.toDouble()),
      ],
      height: 250,
      currency: summary.currency,
    );
  }
}

class _StatusChart extends ConsumerWidget {
  const _StatusChart({required this.summary});

  final AdminSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bars = <({String label, double value, Color color})>[
      for (final status in adminStatuses)
        (
          label: adminStatusLabel(status),
          value: summary.countOf(status).toDouble(),
          color: statusColor(status),
        ),
    ];
    final total = summary.totalOrders;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (total == 0)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text('No orders in this period yet.', style: AdminType.bodySoft),
          ),
        HorizontalBarChart(
          bars: bars,
          valueFormatter: (v) => v.toStringAsFixed(0),
          onBarTap: (index) => context.go('/admin/orders?status=${adminStatuses[index]}'),
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'Select a status to filter the orders list.',
          style: AdminType.caption,
        ),
      ],
    );
  }
}

class _NeedsAttention extends StatelessWidget {
  const _NeedsAttention({required this.summary});

  final AdminSummary summary;

  static (String, String?) _target(String key) => switch (key) {
        'awaiting_payment' => ('/admin/orders', 'PENDING'),
        'awaiting_confirmation' => ('/admin/orders', 'PAID'),
        'awaiting_driver' => ('/admin/orders', 'CONFIRMED'),
        'out_for_delivery' => ('/admin/orders', 'DRIVER_ASSIGNED'),
        'payment_failed' => ('/admin/orders', 'PAYMENT_FAILED'),
        'cancelled' => ('/admin/orders', 'FAILED'),
        'unavailable_menu_items' => ('/admin/menu', null),
        'unavailable_restaurants' => ('/admin/restaurants', null),
        'quarantine' => ('/admin/settings', null),
        'retry_backlog' => ('/admin/settings', null),
        _ => ('/admin/orders', null),
      };

  static IconData _iconFor(String key) => switch (key) {
        'awaiting_payment' => Icons.schedule_rounded,
        'awaiting_confirmation' => Icons.pending_actions_outlined,
        'awaiting_driver' => Icons.person_pin_circle_outlined,
        'out_for_delivery' => Icons.delivery_dining_outlined,
        'payment_failed' => Icons.credit_card_off_outlined,
        'cancelled' => Icons.cancel_outlined,
        'unavailable_menu_items' => Icons.menu_book_outlined,
        'unavailable_restaurants' => Icons.storefront_outlined,
        'quarantine' => Icons.warning_amber_rounded,
        'retry_backlog' => Icons.autorenew_rounded,
        _ => Icons.info_outline,
      };

  static bool _isError(String key) =>
      key == 'payment_failed' || key == 'cancelled' || key == 'quarantine';

  @override
  Widget build(BuildContext context) {
    if (summary.attention.isEmpty) {
      return const AdminEmpty(
        icon: Icons.check_circle_outline_rounded,
        title: 'Nothing needs your attention',
        message: 'No stuck orders, payment failures, catalogue gaps or messaging issues in this period.',
      );
    }

    return Column(
      children: [
        for (final item in _sorted(summary.attention)) ...[
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                final target = _target(item.key);
                context.go(target.$2 == null ? target.$1 : '${target.$1}?status=${target.$2}');
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: (_isError(item.key) ? AppColors.error : AdminColors.brand)
                            .withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _iconFor(item.key),
                        size: 16,
                        color: _isError(item.key) ? AppColors.error : AdminColors.brand,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(item.label, style: AdminType.body, maxLines: 2),
                    ),
                    Text(
                      item.count.toString(),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AdminColors.ink),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right_rounded, size: 17, color: AdminColors.inkMuted),
                  ],
                ),
              ),
            ),
          ),
          if (item != summary.attention.last) const Divider(height: 12, color: AdminColors.lineSoft),
        ],
      ],
    );
  }

  List<AttentionItem> _sorted(List<AttentionItem> items) {
    final ordered = List<AttentionItem>.from(items);
    const priority = [
      'quarantine',
      'payment_failed',
      'cancelled',
      'awaiting_payment',
      'awaiting_confirmation',
      'awaiting_driver',
      'out_for_delivery',
      'unavailable_menu_items',
      'unavailable_restaurants',
      'retry_backlog',
    ];
    ordered.sort((a, b) => priority.indexOf(a.key).compareTo(priority.indexOf(b.key)));
    return ordered;
  }
}

class _TopDishes extends StatelessWidget {
  const _TopDishes({required this.summary});

  final AdminSummary summary;

  @override
  Widget build(BuildContext context) {
    if (summary.topDishes.isEmpty) {
      return const AdminEmpty(
        icon: Icons.trending_down_rounded,
        title: 'No dish sales in this period',
        message: 'Units sold appear once an order reaches a completed state.',
      );
    }

    return Column(
      children: [
        for (var i = 0; i < summary.topDishes.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AdminColors.inkMuted),
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: AppImage(
                    url: summary.topDishes[i].imageUrl,
                    width: 38,
                    height: 38,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.topDishes[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AdminColors.ink),
                      ),
                      if (summary.topDishes[i].restaurantName.isNotEmpty)
                        Text(
                          summary.topDishes[i].restaurantName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AdminType.caption,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                SizedBox(
                  width: 56,
                  child: Text(
                    '${summary.topDishes[i].quantity}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AdminColors.ink),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                SizedBox(
                  width: 84,
                  child: Text(
                    formatCompactCurrency(summary.topDishes[i].revenueMinor),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AdminColors.inkSoft),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Recent orders
