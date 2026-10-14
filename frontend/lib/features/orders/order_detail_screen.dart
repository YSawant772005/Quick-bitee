import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../shared/widgets.dart';
import '../../state/auth_controller.dart';

final Set<String> _terminalStatuses = {
  'DRIVER_ASSIGNED',
  'PAYMENT_FAILED',
  'FAILED',
};

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
        _history = results[1] as List<HistoryEntry>;
        _notifications = results[2] as List<AppNotification>;
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

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push('/notifications'),
          ),
        ],
      ),
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
                    padding: const EdgeInsets.all(16),
                    children: [
                      _StatusHeader(order: order),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Items', style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 8),
                              for (final item in order.items)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Text('${item.quantity}×', style: const TextStyle(fontWeight: FontWeight.w600)),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(item.name)),
                                      Text(formatMinor(item.lineTotalMinor)),
                                    ],
                                  ),
                                ),
                              const Divider(height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Total', style: TextStyle(fontWeight: FontWeight.w700)),
                                  Text(formatMinor(order.totalMinor),
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('Delivery to: ${order.deliveryAddress}',
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ),
                      if (order.driver != null) ...[
                        const SizedBox(height: 16),
                        _DriverCard(driver: order.driver!),
                      ],
                      if (order.failureReason != null) ...[
                        const SizedBox(height: 16),
                        Card(
                          color: const Color(0xFFFFF1F2),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.error_outline, color: Color(0xFF9F1239)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Failure: ${order.failureReason}',
                                    style: const TextStyle(color: Color(0xFF9F1239)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text('Timeline', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      for (final entry in _history)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            entry.status == 'PENDING'
                                ? Icons.radio_button_unchecked
                                : entry.status == order.status
                                    ? Icons.check_circle
                                    : Icons.circle,
                            color: entry.status == 'PENDING'
                                ? Colors.grey
                                : const Color(0xFFC2410C),
                          ),
                          title: Text(entry.status),
                          subtitle: Text(entry.note),
                          trailing: Text(
                            TimeOfDay.fromDateTime(entry.createdAt.toLocal()).format(context),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      const SizedBox(height: 16),
                      Text('Updates', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (_notifications.where((n) => n.orderId == order.id).isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text('No notifications yet.'),
                        )
                      else
                        for (final n in _notifications.where((n) => n.orderId == order.id))
                          Card(
                            child: ListTile(
                              title: Text(n.title),
                              subtitle: Text(n.message),
                              dense: true,
                            ),
                          ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.order});

  final OrderDetail order;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text('Order #${order.id.substring(0, 8)}',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                StatusChip(status: order.status),
              ],
            ),
            const SizedBox(height: 8),
            if (order.status == 'DRIVER_ASSIGNED')
              const Text('Your driver is on the way. This screen will stop refreshing.')
            else if (_terminalStatuses.contains(order.status))
              const Text('This order has reached a final status.')
            else
              Text('Processing — refreshing every 2 seconds…',
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _DriverCard extends StatelessWidget {
  const _DriverCard({required this.driver});

  final Driver driver;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.delivery_dining)),
        title: Text(driver.driverName),
        subtitle: Text('${driver.vehicle} · ETA ${driver.etaMinutes} min'),
      ),
    );
  }
}
