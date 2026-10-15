import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../shared/charts.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

/// `/admin/analytics` — deeper reporting for the selected period.
///
/// Every panel aggregates real rows for the reporting period chosen in the
/// header; nothing on this screen is sampled, estimated or placeholder data.
class AdminAnalyticsPage extends ConsumerWidget {
  const AdminAnalyticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analytics = ref.watch(adminAnalyticsProvider);
    final summary = ref.watch(adminSummaryProvider);

    return AdminPage(
      title: 'Analytics',
      description: 'Sales, demand patterns and catalogue contribution.',
      actions: [AdminRefreshButton(onPressed: () => refreshAdminData(ref))],
      child: analytics.when(
        loading: () => const AdminLoading(label: 'Crunching the numbers…', rows: 6),
        error: (error, _) => AdminErrorState(
          message: error is ApiException ? error.message : '$error',
          onRetry: () => ref.invalidate(adminAnalyticsProvider),
        ),
        data: (a) => _Body(analytics: a, summary: summary),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.analytics, required this.summary});

  final AdminAnalytics analytics;
  final AsyncValue<AdminSummary> summary;

  @override
  Widget build(BuildContext context) {
    final a = analytics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminGrid(
          minItemWidth: 210,
          children: [
            MetricCard(label: 'Orders', value: a.totalOrders.toString(), caption: 'all statuses in period'),
            MetricCard(
              label: 'Revenue',
              value: formatMinor(a.totalRevenueMinor, currency: a.currency),
              caption: 'realised sales only',
            ),
            MetricCard(
              label: 'Avg order value',
              value: formatMinor(a.avgOrderValueMinor, currency: a.currency),
              caption: a.successfulOrders > 0 ? 'over ${a.successfulOrders} sales' : 'no sales yet',
            ),
            MetricCard(
              label: 'Active customers',
              value: a.activeCustomers.toString(),
              caption: 'ordered in period',
            ),
            MetricCard(
              label: 'Avg items / order',
              value: a.avgItemsPerOrder.toStringAsFixed(1),
              caption: a.totalOrders > 0 ? 'across ${a.totalOrders} orders' : 'no orders yet',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        AdminSection(
          title: 'Revenue over time',
          subtitle: '${a.granularity} buckets · ${a.dateFrom ?? 'all time'} to ${a.dateTo ?? 'today'}',
          trailing: const GranularityControl(compact: true),
          child: _RevenueSeries(analytics: a),
        ),
        const SizedBox(height: AppSpacing.lg),

        AdminGrid(
          minItemWidth: 360,
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.lg,
          children: [
            AdminSection(
              title: 'Revenue by restaurant',
              subtitle: 'Contribution to realised revenue',
              child: _ByRestaurant(analytics: a),
            ),
            AdminSection(
              title: 'Orders by weekday',
              subtitle: 'Demand spread across the week',
              child: _WeekdayChart(analytics: a),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        AdminGrid(
          minItemWidth: 360,
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.lg,
          children: [
            AdminSection(
              title: 'Orders by hour of day',
              subtitle: 'When customers actually order',
              child: _HourChart(analytics: a),
            ),
            AdminSection(
              title: 'Status funnel',
              subtitle: 'Where orders are sitting right now',
              child: _Funnel(analytics: a),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        summary.maybeWhen(
          data: (s) => AdminSection(
            title: 'Top dishes',
            subtitle: 'Units and revenue for realised sales in this period',
            child: _TopDishesTable(summary: s),
          ),
          orElse: () => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _RevenueSeries extends StatelessWidget {
  const _RevenueSeries({required this.analytics});

  final AdminAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final rows = analytics.revenueByDay;
    if (rows.isEmpty) {
      return const AdminEmpty(
        icon: Icons.show_chart_rounded,
        title: 'No data for this period',
        message: 'Widen the reporting period to see a revenue series.',
      );
    }
    if (!rows.any((r) => r.revenueMinor > 0)) {
      return const AdminEmpty(
        icon: Icons.payments_outlined,
        title: 'No realised revenue yet',
        message: 'Revenue only counts orders that reached PAID, CONFIRMED or out-for-delivery.',
      );
    }
    return RevenueAreaChart(
      points: [for (final r in rows) ChartPoint(r.date, r.revenueMinor.toDouble())],
      height: 300,
      currency: analytics.currency,
    );
  }
}

class _ByRestaurant extends StatelessWidget {
  const _ByRestaurant({required this.analytics});

  final AdminAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final rows = analytics.revenueByRestaurant;
    if (rows.isEmpty) {
      return const AdminEmpty(
        icon: Icons.storefront_outlined,
        title: 'No restaurant sales yet',
        message: 'Revenue by venue appears once orders complete.',
      );
    }
    final total = analytics.totalRevenueMinor;

    return Column(
      children: [
        for (final row in rows) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: AppImage(url: row.imageUrl, width: 36, height: 36, fit: BoxFit.cover, radius: 7),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AdminType.cell),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: total == 0 ? 0 : row.revenueMinor / total,
                          minHeight: 5,
                          backgroundColor: AdminColors.rowFill,
                          valueColor: const AlwaysStoppedAnimation<Color>(AdminColors.brand),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                SizedBox(
                  width: 74,
                  child: Text(
                    total == 0 ? '—' : '${((row.revenueMinor / total) * 100).toStringAsFixed(1)}%',
                    textAlign: TextAlign.right,
                    style: AdminType.label,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 88,
                  child: Text(
                    formatCompactCurrency(row.revenueMinor),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AdminColors.ink),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _WeekdayChart extends StatelessWidget {
  const _WeekdayChart({required this.analytics});

  final AdminAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final buckets = analytics.ordersByWeekday;
    if (buckets.isEmpty) {
      return const AdminEmpty(
        icon: Icons.calendar_view_week_rounded,
        title: 'No orders in this period',
        message: 'Weekday demand appears once orders exist.',
      );
    }
    return HorizontalBarChart(
      bars: [
        for (final b in buckets)
          (label: b.label, value: b.count.toDouble(), color: AdminColors.brand),
      ],
      valueFormatter: (v) => v.toStringAsFixed(0),
    );
  }
}

class _HourChart extends StatelessWidget {
  const _HourChart({required this.analytics});

  final AdminAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final buckets = analytics.ordersByHour;
    if (buckets.isEmpty) {
      return const AdminEmpty(
        icon: Icons.schedule_rounded,
        title: 'No orders in this period',
        message: 'Hourly demand appears once orders exist.',
      );
    }
    return HorizontalBarChart(
      bars: [
        for (final b in buckets)
          (label: b.label, value: b.count.toDouble(), color: AppColors.info),
      ],
      valueFormatter: (v) => v.toStringAsFixed(0),
    );
  }
}

class _Funnel extends StatelessWidget {
  const _Funnel({required this.analytics});

  final AdminAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final buckets = analytics.ordersByStatus;
    if (buckets.isEmpty) {
      return const AdminEmpty(
        icon: Icons.filter_alt_outlined,
        title: 'No orders in this period',
        message: 'The funnel fills in as orders enter the state machine.',
      );
    }
    return HorizontalBarChart(
      bars: [
        for (final status in adminStatuses)
          if (buckets.containsKey(status))
            (
              label: adminStatusLabel(status),
              value: (buckets[status] ?? 0).toDouble(),
              color: statusColor(status),
            ),
      ],
      valueFormatter: (v) => v.toStringAsFixed(0),
    );
  }
}

class _TopDishesTable extends StatelessWidget {
  const _TopDishesTable({required this.summary});

  final AdminSummary summary;

  @override
  Widget build(BuildContext context) {
    if (summary.topDishes.isEmpty) {
      return const AdminEmpty(
        icon: Icons.trending_down_rounded,
        title: 'No dish sales in this period',
        message: 'Ranked dish performance appears once orders complete.',
      );
    }

    return AdminTable<TopDish>(
      columns: [
        AdminColumn(
          label: 'Dish',
          flex: 3,
          cell: (context, row) => Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: AppImage(url: row.imageUrl, width: 36, height: 36, fit: BoxFit.cover, radius: 7),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AdminType.cell),
                    if (row.restaurantName.isNotEmpty)
                      Text(row.restaurantName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AdminType.caption),
                  ],
                ),
              ),
            ],
          ),
        ),
        AdminColumn(
          label: 'Units',
          width: 90,
          align: TextAlign.right,
          cell: (context, row) => Text('${row.quantity}', textAlign: TextAlign.right, style: AdminType.cell),
        ),
        AdminColumn(
          label: 'Revenue',
          width: 116,
          align: TextAlign.right,
          cell: (context, row) => Text(
            formatMinor(row.revenueMinor, currency: summary.currency),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AdminColors.ink),
          ),
        ),
      ],
      rows: summary.topDishes,
      cardTitle: (row) => row.name,
      cardSubtitle: (row) => row.restaurantName,
    );
  }
}
