import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

/// `/admin/deliveries` — live driver assignments.
///
/// Read-only by design: the backend creates assignments from its delivery
/// worker and exposes no partner registry or assignment endpoint, so this
/// screen reports what actually exists instead of offering controls the API
/// cannot honour.
class AdminDeliveriesPage extends ConsumerStatefulWidget {
  const AdminDeliveriesPage({super.key});

  @override
  ConsumerState<AdminDeliveriesPage> createState() => _AdminDeliveriesPageState();
}

class _AdminDeliveriesPageState extends ConsumerState<AdminDeliveriesPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  AdminSearchQuery _query = const AdminSearchQuery();

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _query = _query.filtered(search: value, clearSearch: value.isEmpty));
    });
  }

  void _reload() => ref.invalidate(adminDeliveriesProvider(_query));

  @override
  Widget build(BuildContext context) {
    final deliveries = ref.watch(adminDeliveriesProvider(_query));

    return AdminPage(
      title: 'Deliveries',
      description: 'Driver assignments created by the delivery worker.',
      actions: [AdminRefreshButton(onPressed: () => refreshAdminData(ref))],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, size: 17, color: AdminColors.inkSoft),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Read-only view. Assignments are produced by the platform\'s delivery worker; '
                    'this build has no delivery-partner registry and no endpoint to create, '
                    'reassign or cancel a driver, so no such controls are shown here.',
                    style: AdminType.bodySoft,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AdminSection(
            title: 'Active assignments',
            padding: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      AdminSearchField(
                        controller: _search,
                        onChanged: _onSearch,
                        hintText: 'Search driver, order id or restaurant',
                        width: 320,
                      ),
                      if (_query.search != null)
                        TextButton(
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = const AdminSearchQuery());
                          },
                          child: const Text('Clear filters'),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  deliveries.when(
                    loading: () => const AdminLoading(label: 'Loading deliveries…'),
                    error: (error, _) => AdminErrorState(
                      message: error is ApiException ? error.message : '$error',
                      onRetry: _reload,
                    ),
                    data: (page) => _body(page),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(Paginated<AdminDelivery> page) {
    if (page.items.isEmpty) {
      return AdminEmpty(
        icon: Icons.delivery_dining_outlined,
        title: _query.search != null ? 'No assignments match that search' : 'No deliveries on the road',
        message: _query.search != null
            ? 'Try a different driver, order id or restaurant.'
            : 'Assignments appear here once the delivery worker dispatches an order.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminTable<AdminDelivery>(
          columns: [
            AdminColumn(
              label: 'Driver',
              flex: 2,
              cell: (context, row) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.driverName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AdminType.cell),
                  Text(row.vehicle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AdminType.caption),
                ],
              ),
            ),
            AdminColumn(
              label: 'Order',
              flex: 2,
              cell: (context, row) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shortId(row.orderId), style: AdminType.mono),
                  Text(row.restaurantName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AdminType.caption),
                ],
              ),
            ),
            AdminColumn(
              label: 'Status',
              width: 172,
              cell: (context, row) => AdminStatusBadge(status: row.orderStatus, dense: true),
            ),
            AdminColumn(
              label: 'ETA',
              width: 72,
              align: TextAlign.center,
              cell: (context, row) => Text(
                '${row.etaMinutes} min',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AdminColors.ink),
              ),
            ),
            AdminColumn(
              label: 'Total',
              width: 100,
              align: TextAlign.right,
              cell: (context, row) => Text(
                formatMinor(row.totalMinor, currency: row.currency),
                textAlign: TextAlign.right,
                style: AdminType.cell,
              ),
            ),
            AdminColumn(
              label: 'Placed',
              width: 124,
              cell: (context, row) => Tooltip(
                message: formatDateTime(row.createdAt),
                child: Text(formatRelative(row.createdAt), style: AdminType.caption),
              ),
            ),
          ],
          rows: page.items,
          cardTitle: (row) => row.driverName,
          cardSubtitle: (row) => '${row.restaurantName} · ${shortId(row.orderId)}',
        ),
        const SizedBox(height: AppSpacing.md),
        PaginationBar(
          page: page.page,
          pageSize: page.pageSize,
          total: page.total,
          onPageChanged: (next) => setState(() => _query = _query.filtered(page: next)),
          onPageSizeChanged: (size) => setState(() => _query = _query.filtered(pageSize: size)),
        ),
      ],
    );
  }
}
