import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../../state/admin_range_controller.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

/// The server-backed orders table: search, status filter, sort, period filter,
/// pagination and page-size controls, with loading/empty/error states and a
/// stacked-card layout below the desktop breakpoint.
///
/// Shared by the Overview and the Orders management page so both behave
/// identically.
class OrdersTable extends ConsumerStatefulWidget {
  const OrdersTable({
    super.key,
    this.title = 'Orders',
    this.subtitle,
    this.pageSize = 20,
    this.initialStatus,
    this.above,
  });

  final String title;
  final String? subtitle;
  final int pageSize;

  /// Status to preselect (used to honour `?status=` deep links).
  final String? initialStatus;

  /// Rendered above the controls — used for status-count chips bound to the
  /// same query object.
  final Widget Function(BuildContext context, AdminOrdersQuery query, void Function(AdminOrdersQuery) update)? above;

  @override
  ConsumerState<OrdersTable> createState() => _OrdersTableState();
}

class _OrdersTableState extends ConsumerState<OrdersTable> {
  final _search = TextEditingController();
  Timer? _debounce;
  late AdminOrdersQuery _query;

  @override
  void initState() {
    super.initState();
    _query = AdminOrdersQuery(
      pageSize: widget.pageSize,
      status: widget.initialStatus,
    );
    _search.text = _query.search ?? '';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _update(AdminOrdersQuery next) => setState(() => _query = next);

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _update(_query.filtered(search: value, clearSearch: value.isEmpty));
    });
  }

  bool get _filtered => _query.search != null || _query.status != null;

  void _clear() {
    _search.clear();
    _update(AdminOrdersQuery(pageSize: widget.pageSize));
  }

  @override
  Widget build(BuildContext context) {
    // A new reporting period restarts pagination so the visible page always
    // belongs to the period shown in the header.
    ref.listen(adminRangeProvider, (_, __) {
      if (_query.page != 1) _update(_query.copyWith(page: 1));
    });

    final orders = ref.watch(adminOrdersProvider(_query));

    return AdminSection(
      title: widget.title,
      subtitle: widget.subtitle,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.above != null) ...[
              widget.above!(context, _query, _update),
              const SizedBox(height: AppSpacing.lg),
            ],
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AdminSearchField(
                  controller: _search,
                  onChanged: _onSearchChanged,
                  hintText: 'Search order id or customer',
                  width: 280,
                ),
                AdminDropdown<String?>(
                  value: _query.status,
                  width: 190,
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('All statuses')),
                    for (final s in adminStatuses)
                      DropdownMenuItem<String?>(value: s, child: Text(adminStatusLabel(s))),
                  ],
                  onChanged: (value) => _update(_query.filtered(status: value, clearStatus: value == null)),
                ),
                AdminDropdown<String>(
                  value: _query.sort,
                  width: 172,
                  items: const [
                    DropdownMenuItem(value: 'created_desc', child: Text('Newest first')),
                    DropdownMenuItem(value: 'created_asc', child: Text('Oldest first')),
                    DropdownMenuItem(value: 'total_desc', child: Text('Total: high to low')),
                    DropdownMenuItem(value: 'total_asc', child: Text('Total: low to high')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    _update(_query.copyWith(sort: value, page: 1));
                  },
                ),
                if (_filtered)
                  TextButton(
                    onPressed: _clear,
                    child: const Text('Clear filters'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            orders.when(
              loading: () => const AdminLoading(label: 'Loading orders…', rows: 5),
              error: (error, _) => AdminErrorState(
                message: error is ApiException ? error.message : '$error',
                onRetry: () => ref.invalidate(adminOrdersProvider(_query)),
              ),
              data: (page) => _body(context, page),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, Paginated<AdminOrderListItem> page) {
    if (page.items.isEmpty) {
      return AdminEmpty(
        icon: Icons.receipt_long_outlined,
        title: _filtered ? 'No orders match these filters' : 'No orders in this period',
        message: _filtered
            ? 'Try clearing the search or status filter, or widen the reporting period.'
            : 'Orders appear here as soon as customers place them.',
        action: _filtered
            ? OutlinedButton(onPressed: _clear, child: const Text('Clear filters'))
            : null,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminTable<AdminOrderListItem>(
          columns: [
            AdminColumn(
              label: 'Order',
              width: 190,
              cell: (context, row) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shortId(row.id), style: AdminType.mono),
                  Text(row.itemSummary, maxLines: 1, overflow: TextOverflow.ellipsis, style: AdminType.caption),
                ],
              ),
            ),
            AdminColumn(
              label: 'Customer',
              flex: 2,
              cell: (context, row) => Text(
                row.customerEmail.isEmpty ? '—' : row.customerEmail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AdminType.cell,
              ),
            ),
            AdminColumn(
              label: 'Restaurant',
              flex: 2,
              cell: (context, row) => Text(
                row.restaurantName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AdminType.cell,
              ),
            ),
            AdminColumn(
              label: 'Items',
              width: 64,
              align: TextAlign.center,
              cell: (context, row) => Text('${row.itemCount}', textAlign: TextAlign.center, style: AdminType.cell),
            ),
            AdminColumn(
              label: 'Total',
              width: 108,
              align: TextAlign.right,
              cell: (context, row) => Text(
                formatMinor(row.totalMinor, currency: row.currency),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AdminColors.ink),
              ),
            ),
            AdminColumn(
              label: 'Payment',
              width: 118,
              cell: (context, row) => PaymentBadge(status: row.paymentStatus, attempts: row.paymentAttempts, dense: true),
            ),
            AdminColumn(
              label: 'Status',
              width: 172,
              cell: (context, row) => AdminStatusBadge(status: row.status, dense: true),
            ),
            AdminColumn(
              label: 'Placed',
              width: 124,
              cell: (context, row) => Tooltip(
                message: formatDateTime(row.createdAt),
                child: Text(formatRelative(row.createdAt), style: AdminType.caption),
              ),
            ),
            AdminColumn(
              label: 'Actions',
              width: 76,
              cell: (context, row) => TextButton(
                onPressed: () => context.push('/admin/orders/${row.id}'),
                style: TextButton.styleFrom(
                  foregroundColor: AdminColors.brand,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
                child: const Text('View'),
              ),
            ),
          ],
          rows: page.items,
          onRowTap: (row) => context.push('/admin/orders/${row.id}'),
          cardTitle: (row) => '${shortId(row.id)}  ·  ${formatMinor(row.totalMinor, currency: row.currency)}',
          cardSubtitle: (row) =>
              '${row.customerEmail.isEmpty ? "No customer" : row.customerEmail} · ${row.restaurantName}',
        ),
        const SizedBox(height: AppSpacing.md),
        PaginationBar(
          page: page.page,
          pageSize: page.pageSize,
          total: page.total,
          onPageChanged: (next) => _update(_query.copyWith(page: next)),
          onPageSizeChanged: (size) => _update(_query.copyWith(pageSize: size, page: 1)),
        ),
      ],
    );
  }
}
