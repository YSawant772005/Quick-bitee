import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';
import '../../shared/layout.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../../state/auth_controller.dart';

IconData _eventIcon(String eventType) => switch (eventType) {
      'order.created' => Icons.receipt_long_outlined,
      'order.paid' => Icons.payments_outlined,
      'order.payment.failed' => Icons.error_outline,
      'order.confirmed' => Icons.soup_kitchen_outlined,
      'order.driver.assigned' => Icons.delivery_dining_outlined,
      'order.failed' => Icons.cancel_outlined,
      _ => Icons.notifications_none,
    };

Color _eventColor(String eventType) => switch (eventType) {
      'order.paid' || 'order.confirmed' => AppColors.success,
      'order.driver.assigned' => AppColors.forest,
      'order.payment.failed' || 'order.failed' => AppColors.error,
      _ => AppColors.warning,
    };

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  static const _pageSize = 20;

  List<AppNotification> _items = const [];
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
      final data = await ref.read(apiClientProvider).notifications(page: page, pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        _items = data.items;
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
    return CustomerShell(
      navIndex: null,
      showBack: true,
      title: 'Notifications',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(
                  message: _error is ApiException ? (_error! as ApiException).message : 'Could not load notifications.',
                  onRetry: () => _load(page: _page),
                )
              : _items.isEmpty
                  ? const EmptyState(
                      icon: Icons.notifications_none,
                      title: 'No notifications',
                      subtitle: 'Order updates are persisted here as they happen.',
                    )
                  : RefreshIndicator(
                      onRefresh: () => _load(page: 1),
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                        children: [
                          ContentWidth(
                            maxWidth: 820,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: AppSpacing.lg),
                                for (final n in _items) ...[
                                  _NotificationCard(notification: n),
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

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final color = _eventColor(notification.eventType);
    final timeFmt = DateFormat('d MMM, HH:mm');
    return AppCard(
      onTap: () => context.push('/orders/${notification.orderId}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(_eventIcon(notification.eventType), color: color, size: 22),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(notification.title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(notification.message, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.schedule_rounded, size: 13, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Text(timeFmt.format(notification.createdAt.toLocal()),
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ],
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
