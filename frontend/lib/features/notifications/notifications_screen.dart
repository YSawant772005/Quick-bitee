import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';
import '../../shared/widgets.dart';
import '../../state/auth_controller.dart';

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
      final data =
          await ref.read(apiClientProvider).notifications(page: page, pageSize: _pageSize);
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
    final timeFmt = DateFormat('dd MMM, HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
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
                        padding: const EdgeInsets.all(16),
                        children: [
                          for (final n in _items)
                            Card(
                              child: ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.notifications_active_outlined),
                                ),
                                title: Text(n.title),
                                subtitle: Text('${n.message}\n${timeFmt.format(n.createdAt.toLocal())}'),
                                isThreeLine: true,
                                onTap: () => context.push('/orders/${n.orderId}'),
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
