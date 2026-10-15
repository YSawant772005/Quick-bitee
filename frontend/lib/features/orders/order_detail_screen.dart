import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';
import '../../shared/layout.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../../state/auth_controller.dart';
import '../../state/cart_controller.dart';

const _terminalStatuses = {'DRIVER_ASSIGNED', 'PAYMENT_FAILED', 'FAILED'};

/// Canonical happy-path stages, in order.
const _stages = [
  ('PENDING', 'Order placed', 'We received your order'),
  ('PAID', 'Payment received', 'Payment captured securely'),
  ('CONFIRMED', 'Preparing', 'The kitchen is cooking your food'),
  ('DRIVER_ASSIGNED', 'Out for delivery', 'Your driver is on the way'),
];

class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  OrderDetail? _order;
  List<HistoryEntry> _history = const [];
  List<AppNotification> _notifications = const [];
  Object? _error;
  Timer? _pollTimer;
  int _failures = 0;
  bool _reordering = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final api = ref.read(apiClientProvider);
    try {
      final results = await Future.wait([
        api.order(widget.orderId),
        api.orderHistory(widget.orderId),
        api.notifications(),
      ]);
      if (!mounted) return;
      setState(() {
        _order = results[0] as OrderDetail;
        _history = (results[1] as Paginated<HistoryEntry>).items;
        _notifications = (results[2] as Paginated<AppNotification>).items;
        _error = null;
        _failures = 0;
      });
      if (_terminalStatuses.contains(_order!.status)) {
        _pollTimer?.cancel();
      }
    } catch (e) {
      _failures++;
      if (_failures >= 5 && mounted) {
        setState(() => _error = e);
        _pollTimer?.cancel();
      }
    }
  }

  Future<void> _reorder() async {
    final order = _order;
    if (order == null || _reordering) return;
    setState(() => _reordering = true);
    try {
      final menu = await ref.read(apiClientProvider).menu(order.restaurantId, pageSize: 100);
      final byId = {for (final m in menu.items) m.id: m};
      final cart = ref.read(cartProvider.notifier);
      cart.clear();
      var added = 0;
      var skipped = 0;
      for (final line in order.items) {
        final item = byId[line.menuItemId];
        if (item != null && item.available) {
          cart.add(item, quantity: line.quantity);
          added++;
        } else {
          skipped++;
        }
      }
      if (!mounted) return;
      if (added == 0) {
        showAppSnack(context, 'These dishes are not available right now.', icon: Icons.info_outline_rounded);
      } else {
        showAppSnack(
          context,
          skipped == 0 ? 'Items added to your cart' : 'Added $added item(s); $skipped unavailable',
        );
        context.go('/cart');
      }
    } catch (_) {
      if (mounted) showAppSnack(context, 'Could not load the menu to reorder.', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return CustomerShell(
      navIndex: null,
      showBack: true,
      title: 'Order tracking',
      actions: [
        IconButton(
          tooltip: 'Notifications',
          onPressed: () => context.push('/notifications'),
          icon: const Icon(Icons.notifications_none_rounded),
        ),
      ],
      body: _error != null && order == null
          ? ErrorState(
              message: 'Could not load the order. ${_error is ApiException ? (_error! as ApiException).message : _error}',
              onRetry: () {
                _failures = 0;
                _refresh();
                _startPolling();
              },
            )
          : order == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                    children: [
                      ContentWidth(
                        maxWidth: 820,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: AppSpacing.lg),
                            _TrackingHeader(
                              order: order,
                              live: !_terminalStatuses.contains(order.status),
                              reordering: _reordering,
                              onReorder: _reorder,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            _ProgressCard(order: order, history: _history),
                            if (order.failureReason != null) ...[
                              const SizedBox(height: AppSpacing.lg),
                              _FailureBanner(reason: order.failureReason!),
                            ],
                            const SizedBox(height: AppSpacing.lg),
                            _ItemsCard(order: order),
                            if (order.driver != null) ...[
                              const SizedBox(height: AppSpacing.lg),
                              _DriverCard(driver: order.driver!),
                            ],
                            const SizedBox(height: AppSpacing.lg),
                            _AddressCard(address: order.deliveryAddress),
                            if (_history.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.lg),
                              _ActivityCard(history: _history),
                            ],
                            const SizedBox(height: AppSpacing.lg),
                            _UpdatesCard(orderId: order.id, notifications: _notifications),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _TrackingHeader extends StatelessWidget {
  const _TrackingHeader({
    required this.order,
    required this.live,
    required this.reordering,
    required this.onReorder,
  });

  final OrderDetail order;
  final bool live;
  final bool reordering;
  final VoidCallback onReorder;

  @override
  Widget build(BuildContext context) {
    final failed = order.status == 'PAYMENT_FAILED' || order.status == 'FAILED';
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: failed
              ? [const Color(0xFF7F2A2A), const Color(0xFF5A1D1D)]
              : [AppColors.forestSoft, AppColors.forestDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(statusIcon(order.status), color: AppColors.lime, size: 26),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      friendlyStatus(order.status),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Order #${order.id.substring(0, 8)}',
                      style: const TextStyle(color: AppColors.onForestMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (live)
                Row(
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.lime),
                    ),
                    const SizedBox(width: 6),
                    const Text('Live', style: TextStyle(color: AppColors.lime, fontWeight: FontWeight.w700, fontSize: 12)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                Icon(
                  failed ? Icons.error_outline_rounded : Icons.info_outline_rounded,
                  size: 18,
                  color: AppColors.lime,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _message(order.status),
                    style: const TextStyle(color: AppColors.onForest, fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          if (!failed) ...[
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: reordering ? null : onReorder,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                  minimumSize: const Size(0, 48),
                ),
                icon: reordering
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.replay_rounded, size: 19),
                label: Text(reordering ? 'Adding to cart…' : 'Order again'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _message(String status) => switch (status) {
        'PENDING' => 'We have your order. Payment is being processed.',
        'PAID' => 'Payment captured. The restaurant will confirm shortly.',
        'CONFIRMED' => 'The kitchen is preparing your food right now.',
        'DRIVER_ASSIGNED' => 'Your driver is on the way to your address.',
        'PAYMENT_FAILED' => 'Payment could not be processed. No charge was made.',
        'FAILED' => 'This order could not be completed.',
        _ => 'Order status updated.',
      };
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.order, required this.history});

  final OrderDetail order;
  final List<HistoryEntry> history;

  @override
  Widget build(BuildContext context) {
    final reached = {for (final h in history) h.status};
    reached.add('PENDING');
    reached.add(order.status);
    final failed = order.status == 'PAYMENT_FAILED' || order.status == 'FAILED';
    final currentIndex = _stages.indexWhere((s) => s.$1 == order.status);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Progress', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.lg),
          for (var i = 0; i < _stages.length; i++)
            _StageRow(
              label: _stages[i].$2,
              subtitle: _stages[i].$3,
              done: reached.contains(_stages[i].$1),
              active: !failed && currentIndex == i && order.status == _stages[i].$1,
              isLast: i == _stages.length - 1,
            ),
          if (failed) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  friendlyStatus(order.status),
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.error),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.label,
    required this.subtitle,
    required this.done,
    required this.active,
    required this.isLast,
  });

  final String label;
  final String subtitle;
  final bool done;
  final bool active;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = done ? AppColors.forest : AppColors.border;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: done ? AppColors.forest : AppColors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: done ? AppColors.forest : AppColors.border, width: 2),
                ),
                child: done
                    ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                    : null,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: color,
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          color: done ? AppColors.textPrimary : AppColors.textMuted,
                        ),
                      ),
                      if (active) ...[
                        const SizedBox(width: 8),
                        const Pill(label: 'Now', color: AppColors.forest, dense: true),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.order});

  final OrderDetail order;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Items', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.lg),
          for (var i = 0; i < order.items.length; i++) ...[
            Row(
              children: [
                AppImage(url: order.items[i].imageUrl, height: 52, width: 52, radius: AppRadius.sm),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${order.items[i].quantity} × ${order.items[i].name}',
                          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(formatMinor(order.items[i].unitPriceMinor),
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                PriceText(minor: order.items[i].lineTotalMinor, size: 14.5),
              ],
            ),
            if (i != order.items.length - 1) const SizedBox(height: AppSpacing.lg),
          ],
          const Divider(height: AppSpacing.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: Theme.of(context).textTheme.titleMedium),
              PriceText(minor: order.totalMinor, currency: order.currency, size: 18),
            ],
          ),
        ],
      ),
    );
  }
}

class _DriverCard extends StatelessWidget {
  const _DriverCard({required this.driver});

  final Driver driver;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(color: AppColors.limeSoft, shape: BoxShape.circle),
            child: const Icon(Icons.delivery_dining_rounded, color: AppColors.forest, size: 28),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(driver.driverName, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(driver.vehicle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Pill(
            label: 'ETA ${driver.etaMinutes} min',
            icon: Icons.schedule_rounded,
            color: AppColors.forest,
            background: AppColors.limeSoft,
          ),
        ],
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.address});

  final String address;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_on_outlined, color: AppColors.forest),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Delivery address', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(address, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FailureBanner extends StatelessWidget {
  const _FailureBanner({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.errorSoft,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('What went wrong', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.error)),
                const SizedBox(height: 2),
                Text(reason, style: const TextStyle(color: AppColors.error, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.history});

  final List<HistoryEntry> history;

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('d MMM, HH:mm');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Activity', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < history.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Icon(statusIcon(history[i].status), size: 18, color: statusColor(history[i].status)),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(history[i].note,
                          style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(
                        '${friendlyStatus(history[i].status)} · ${timeFmt.format(history[i].createdAt.toLocal())}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (i != history.length - 1) const SizedBox(height: AppSpacing.lg),
          ],
        ],
      ),
    );
  }
}

class _UpdatesCard extends StatelessWidget {
  const _UpdatesCard({required this.orderId, required this.notifications});

  final String orderId;
  final List<AppNotification> notifications;

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('d MMM, HH:mm');
    final mine = notifications.where((n) => n.orderId == orderId).toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Updates', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.md),
          if (mine.isEmpty)
            const Text('No notifications yet.', style: TextStyle(color: AppColors.textSecondary))
          else
            for (var i = 0; i < mine.length; i++) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.notifications_active_outlined, size: 18, color: AppColors.forest),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(mine[i].title,
                            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        const SizedBox(height: 2),
                        Text(mine[i].message, style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 2),
                        Text(timeFmt.format(mine[i].createdAt.toLocal()),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
              if (i != mine.length - 1) const SizedBox(height: AppSpacing.lg),
            ],
        ],
      ),
    );
  }
}
