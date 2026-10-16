import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

/// `/admin/customers` — account-level order aggregates.
///
/// Derived entirely from `users` + `orders`; the API returns only what an
/// administrator is authorised to see (email, dates, counts and spend). No
/// credentials, tokens or other accounts' data are exposed.
class AdminCustomersPage extends ConsumerStatefulWidget {
  const AdminCustomersPage({super.key});

  @override
  ConsumerState<AdminCustomersPage> createState() => _AdminCustomersPageState();
}

class _AdminCustomersPageState extends ConsumerState<AdminCustomersPage> {
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

  void _reload() => ref.invalidate(adminCustomersProvider(_query));

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(adminCustomersProvider(_query));

    return AdminPage(
      title: 'Customers',
      description: 'Registered accounts and their ordering behaviour.',
      actions: [AdminRefreshButton(onPressed: () => refreshAdminData(ref))],
      child: AdminSection(
        title: 'Accounts',
        subtitle: 'Customer role only · administrators are not listed',
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
                    hintText: 'Search by email',
                    width: 300,
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
              customers.when(
                loading: () => const AdminLoading(label: 'Loading customers…'),
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
    );
  }

  Widget _body(Paginated<AdminCustomer> page) {
    if (page.items.isEmpty) {
      return AdminEmpty(
        icon: Icons.groups_outlined,
        title: _query.search != null ? 'No customers match that search' : 'No customer accounts yet',
        message: _query.search != null
            ? 'Try a different email fragment.'
            : 'Accounts appear here once customers register.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminTable<AdminCustomer>(
          columns: [
            AdminColumn(
              label: 'Customer',
              flex: 3,
              cell: (context, row) => Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AdminColors.brand.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        row.email.isEmpty ? '?' : row.email.characters.first.toUpperCase(),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AdminColors.brand),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: AdminType.cell),
                        Text('Joined ${formatDate(row.registeredAt)}', style: AdminType.caption),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            AdminColumn(
              label: 'Orders',
              width: 78,
              align: TextAlign.right,
              cell: (context, row) => Text('${row.totalOrders}', textAlign: TextAlign.right, style: AdminType.cell),
            ),
            AdminColumn(
              label: 'Realised',
              width: 84,
              align: TextAlign.right,
              cell: (context, row) => Text('${row.successfulOrders}', textAlign: TextAlign.right, style: AdminType.cell),
            ),
            AdminColumn(
              label: 'Active',
              width: 76,
              align: TextAlign.right,
              cell: (context, row) => Text(
                '${row.activeOrders}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: row.activeOrders > 0 ? AppColors.warning : AdminColors.inkSoft,
                ),
              ),
            ),
            AdminColumn(
              label: 'Last order',
              width: 130,
              cell: (context, row) => Text(
                row.lastOrderAt == null ? '—' : formatRelative(row.lastOrderAt!),
                style: AdminType.caption,
              ),
            ),
            AdminColumn(
              label: 'Spend',
              width: 116,
              align: TextAlign.right,
              cell: (context, row) => Text(
                formatMinor(row.totalSpentMinor, currency: row.currency),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AdminColors.ink),
              ),
            ),
          ],
          rows: page.items,
          cardTitle: (row) => row.email,
          cardSubtitle: (row) => '${row.totalOrders} orders · ${formatMinor(row.totalSpentMinor)}',
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
