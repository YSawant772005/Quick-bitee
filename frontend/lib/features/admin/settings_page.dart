import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../shared/theme.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

/// The order-state transitions the backend actually accepts, surfaced so
/// operators do not expect controls that do not exist.
const _orderTransitions = <String, List<String>>{
  'PENDING': ['PAID', 'PAYMENT_FAILED'],
  'PAID': ['CONFIRMED', 'FAILED'],
  'CONFIRMED': ['DRIVER_ASSIGNED', 'FAILED'],
};

/// `/admin/settings` — read-only system facts.
///
/// This build has no persisted configuration store, so the page reports real
/// platform state and documented limitations instead of presenting controls
/// that would do nothing. No environment variables, credentials or tokens are
/// ever read into the UI.
class AdminSettingsPage extends ConsumerWidget {
  const AdminSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(adminSummaryProvider);
    final restaurants = ref.watch(adminRestaurantsProvider(const AdminCatalogQuery(pageSize: 1)));

    return AdminPage(
      title: 'Settings',
      description: 'Platform state, data definitions and known limitations.',
      actions: [AdminRefreshButton(onPressed: () => refreshAdminData(ref))],
      child: summary.when(
        loading: () => const AdminLoading(label: 'Loading system state…'),
        error: (error, _) => AdminErrorState(
          message: error is ApiException ? error.message : '$error',
          onRetry: () => ref.invalidate(adminSummaryProvider),
        ),
        data: (s) => _Body(summary: s, restaurantTotal: restaurants.valueOrNull?.total ?? 0),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.summary, required this.restaurantTotal});

  final AdminSummary summary;
  final int restaurantTotal;

  @override
  Widget build(BuildContext context) {
    return AdminGrid(
      minItemWidth: 360,
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.lg,
      children: [
        AdminSection(
          title: 'System health',
          subtitle: 'Messaging pipeline and live operations',
          child: _rows([
            _kv('Pending outbox events', '${summary.pendingOutbox}', ok: summary.pendingOutbox == 0),
            _kv('Scheduled retries', '${summary.retryBacklog}', ok: summary.retryBacklog == 0),
            _kv('Quarantined events', '${summary.quarantineCount}', ok: summary.quarantineCount == 0),
            _kv('Deliveries on the road', '${summary.activeDeliveries}'),
          ]),
        ),
        AdminSection(
          title: 'Catalogue & accounts',
          subtitle: 'Current counts across the platform',
          child: _rows([
            _kv('Restaurants', '$restaurantTotal'),
            _kv('Restaurants closed', '${summary.unavailableRestaurants}',
                ok: summary.unavailableRestaurants == 0),
            _kv('Menu items unavailable', '${summary.unavailableMenuItems}',
                ok: summary.unavailableMenuItems == 0),
            _kv('Registered customers', '${summary.totalCustomers}'),
          ]),
        ),
        AdminSection(
          title: 'Platform configuration',
          subtitle: 'Fixed for this deployment',
          child: _rows([
            _kv('Reporting currency', summary.currency),
            _kv('Account roles', 'customer, admin'),
            _kv('Payment provider', 'Simulated (stored per order)'),
            _kv('Reporting buckets', 'day, week, month'),
            _kv('Revenue definition', 'PAID + CONFIRMED + DRIVER_ASSIGNED'),
            _kv('Active customers', 'Distinct customers with ≥1 order in period'),
          ]),
        ),
        AdminSection(
          title: 'Order state machine',
          subtitle: 'The only transitions the backend accepts',
          child: Column(
            children: [
              for (final entry in _orderTransitions.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      AdminStatusBadge(status: entry.key, dense: true),
                      const SizedBox(width: AppSpacing.sm),
                      const Icon(Icons.arrow_forward_rounded, size: 15, color: AdminColors.inkMuted),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            for (final target in entry.value)
                              AdminStatusBadge(status: target, dense: true),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 20, color: AdminColors.lineSoft),
              const Text(
                'Terminal states (DRIVER_ASSIGNED, PAYMENT_FAILED, FAILED) cannot move again. '
                'Transitions are performed by the background workers — there is no manual '
                'override endpoint in this build.',
                style: AdminType.bodySoft,
              ),
            ],
          ),
        ),
        AdminSection(
          title: 'Known gaps',
          subtitle: 'Modules that are not implemented — listed rather than faked',
          child: Column(
            children: [
              _gap(Icons.local_offer_outlined, 'Offers & coupons',
                  'No coupon/offer model or endpoint exists in the backend, so this module is not shown in the sidebar.'),
              _gap(Icons.star_outline_rounded, 'Reviews & ratings',
                  'No review model or endpoint exists, so no reviews module or rating figures are displayed.'),
              _gap(Icons.add_circle_outline_rounded, 'Creating restaurants & dishes',
                  'The API exposes read and update (PATCH) only; there is no create endpoint, so no "Add" button is offered.'),
              _gap(Icons.swap_horiz_rounded, 'Manual order transitions',
                  'Order status advances only through the payment, restaurant and delivery workers.'),
              _gap(Icons.person_add_alt_outlined, 'Delivery partner management',
                  'Driver assignments are created by the worker; there is no partner registry or assignment endpoint.'),
              _gap(Icons.tune_rounded, 'Editable application settings',
                  'There is no settings store, so this page reports state rather than offering inert controls.'),
            ],
          ),
        ),
        AdminSection(
          title: 'Security',
          subtitle: 'What this console is allowed to show',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '• Every admin endpoint requires a token whose role is admin; customers receive 403.',
                style: AdminType.bodySoft,
              ),
              const SizedBox(height: 6),
              const Text(
                '• Customer email and delivery address are only returned on admin-protected routes.',
                style: AdminType.bodySoft,
              ),
              const SizedBox(height: 6),
              const Text(
                '• No passwords, tokens, environment variables or connection strings are read into the UI.',
                style: AdminType.bodySoft,
              ),
              const SizedBox(height: 6),
              const Text(
                '• All admin routes are additionally blocked client-side for non-admin sessions.',
                style: AdminType.bodySoft,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _rows(List<Widget> children) => Column(children: children);

  Widget _kv(String label, String value, {bool? ok}) {
    final color = ok == null
        ? AdminColors.ink
        : ok
            ? AppColors.success
            : AppColors.warning;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: AdminType.bodySoft)),
          const SizedBox(width: AppSpacing.md),
          Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }

  Widget _gap(IconData icon, String title, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: AdminColors.inkSoft),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AdminColors.ink)),
                const SizedBox(height: 2),
                Text(message, style: AdminType.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
