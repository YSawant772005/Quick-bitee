import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

/// `/admin/orders/:id` — the admin order detail view.
///
/// One payload carries customer, payment, line items and the fulfilment
/// timeline, so the screen makes a single round trip.
class AdminOrderDetailPage extends ConsumerWidget {
  const AdminOrderDetailPage({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(adminOrderDetailProvider(orderId));

    return AdminPage(
      title: 'Order details',
      description: detail.maybeWhen(
        data: (order) => '${shortId(order.id)} · ${order.restaurantName}',
        orElse: () => 'Fulfilment, payment and timeline.',
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.go('/admin/orders'),
          icon: const Icon(Icons.arrow_back_rounded, size: 16),
          label: const Text('All orders'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AdminColors.ink,
            side: const BorderSide(color: AdminColors.line),
            minimumSize: const Size(0, 40),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(adminOrderDetailProvider(orderId)),
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Refresh'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AdminColors.ink,
            side: const BorderSide(color: AdminColors.line),
            minimumSize: const Size(0, 40),
          ),
        ),
      ],
      child: detail.when(
        loading: () => const AdminLoading(label: 'Loading order…'),
        error: (error, _) => AdminErrorState(
          message: error is ApiException ? error.message : '$error',
          onRetry: () => ref.invalidate(adminOrderDetailProvider(orderId)),
        ),
        data: (order) => _Detail(order: order),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.order});

  final AdminOrderDetail order;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= AppBreakpoints.desktop;

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusCard(order: order),
        const SizedBox(height: AppSpacing.lg),
        _ItemsCard(order: order),
      ],
    );

    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CustomerCard(order: order),
        const SizedBox(height: AppSpacing.lg),
        _TimelineCard(order: order),
        const SizedBox(height: AppSpacing.lg),
        const _TransitionNote(),
      ],
    );

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: left),
          const SizedBox(width: AppSpacing.lg),
          Expanded(flex: 2, child: right),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        left,
        const SizedBox(height: AppSpacing.lg),
        right,
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.order});

  final AdminOrderDetail order;

  @override
  Widget build(BuildContext context) {
    return AdminSection(
      title: 'Status',
      subtitle: 'Current position of this order in the fulfilment flow',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AdminStatusBadge(status: order.status),
              PaymentBadge(status: order.paymentStatus, attempts: order.paymentAttempts),
              if (order.failureReason != null && order.failureReason!.isNotEmpty)
                Pill(
                  label: order.failureReason!,
                  icon: Icons.error_outline_rounded,
                  color: AppColors.error,
                  dense: true,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _facts(context),
        ],
      ),
    );
  }

  Widget _facts(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xl,
      runSpacing: AppSpacing.md,
      children: [
        _Fact(label: 'Order id', value: order.id, mono: true),
        _Fact(label: 'Placed', value: formatDateTime(order.createdAt)),
        _Fact(label: 'Last update', value: formatDateTime(order.updatedAt)),
        _Fact(label: 'Version', value: '${order.version}'),
        _Fact(label: 'Currency', value: order.currency),
        if (order.driver != null)
          _Fact(
            label: 'Driver',
            value: '${order.driver!.driverName} · ${order.driver!.vehicle} · ${order.driver!.etaMinutes} min ETA',
          ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AdminType.label),
        const SizedBox(height: 3),
        SelectableText(
          value,
          style: mono
              ? AdminType.mono
              : const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AdminColors.ink),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.order});

  final AdminOrderDetail order;

  @override
  Widget build(BuildContext context) {
    final subtotal = order.itemsSubtotalMinor;
    final matchesTotal = subtotal == order.totalMinor;

    return AdminSection(
      title: 'Items',
      subtitle: '${order.items.length} line${order.items.length == 1 ? '' : 's'} · prices as ordered',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final line in order.items) _LineRow(line: line, currency: order.currency),
          const Divider(height: 20, color: AdminColors.line),
          _amountRow('Items subtotal', formatMinor(subtotal, currency: order.currency)),
          const SizedBox(height: 6),
          if (!matchesTotal) ...[
            // The API has no tax/delivery fields: if the stored total differs
            // from the line subtotal we say so rather than inventing a fee.
            Text(
              'Order total differs from the line subtotal by '
              '${formatMinor(order.totalMinor - subtotal, currency: order.currency)} '
              '— the API does not itemise adjustments.',
              style: AdminType.caption,
            ),
            const SizedBox(height: 6),
          ],
          _amountRow('Total', formatMinor(order.totalMinor, currency: order.currency), strong: true),
        ],
      ),
    );
  }

  Widget _amountRow(String label, String value, {bool strong = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: strong ? 14 : 13,
              fontWeight: FontWeight.w800,
              color: AdminColors.ink,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: strong ? 17 : 13.5,
            fontWeight: FontWeight.w800,
            color: strong ? AdminColors.brand : AdminColors.ink,
          ),
        ),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.currency});

  final OrderLine line;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AppImage(
              url: line.imageUrl,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              radius: 8,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AdminColors.ink)),
                const SizedBox(height: 2),
                Text(
                  '${formatMinor(line.unitPriceMinor, currency: currency)} × ${line.quantity}',
                  style: AdminType.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            formatMinor(line.lineTotalMinor, currency: currency),
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AdminColors.ink),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.order});

  final AdminOrderDetail order;

  @override
  Widget build(BuildContext context) {
    return AdminSection(
      title: 'Customer & delivery',
      subtitle: 'Visible to administrators only',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(Icons.person_outline_rounded, 'Customer',
              order.customerEmail.isEmpty ? 'Not available' : order.customerEmail),
          const SizedBox(height: AppSpacing.md),
          _row(Icons.alternate_email_rounded, 'Account id', order.customerId),
          const SizedBox(height: AppSpacing.md),
          _row(Icons.location_on_outlined, 'Address',
              order.deliveryAddress.isEmpty ? 'Not available' : order.deliveryAddress),
          const SizedBox(height: AppSpacing.md),
          _row(Icons.storefront_outlined, 'Restaurant', order.restaurantName),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AdminColors.inkSoft),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 96,
          child: Text(label, style: AdminType.label),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontSize: 13.5, color: AdminColors.ink),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.order});

  final AdminOrderDetail order;

  @override
  Widget build(BuildContext context) {
    if (order.timeline.isEmpty) {
      return const AdminSection(
        title: 'Fulfilment timeline',
        child: AdminEmpty(
          icon: Icons.timeline_rounded,
          title: 'No timeline entries yet',
          message: 'Entries are written as the order moves through the state machine.',
        ),
      );
    }

    return AdminSection(
      title: 'Fulfilment timeline',
      subtitle: 'Ordered by state-machine version',
      child: Column(
        children: [
          for (var i = 0; i < order.timeline.length; i++)
            _TimelineRow(entry: order.timeline[i], isLast: i == order.timeline.length - 1),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.entry, required this.isLast});

  final HistoryEntry entry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(entry.status);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: AdminColors.line),
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
                      Expanded(
                        child: Text(
                          adminStatusLabel(entry.status),
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AdminColors.ink),
                        ),
                      ),
                      Text(formatRelative(entry.createdAt), style: AdminType.caption),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(formatDateTime(entry.createdAt), style: AdminType.caption),
                  if (entry.note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(entry.note, style: AdminType.bodySoft),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Honest note instead of fabricated transition controls.
///
/// The backend advances orders only through its background workers; there is
/// no manual transition endpoint in this build, so no override buttons are
/// rendered.
class _TransitionNote extends StatelessWidget {
  const _TransitionNote();

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 17, color: AdminColors.inkSoft),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Why there are no status buttons', style: AdminType.sectionTitle),
                const SizedBox(height: 4),
                const Text(
                  'Order status is advanced by the platform\'s payment, restaurant and delivery '
                  'workers using the backend\'s state machine. This build does not expose a manual '
                  'transition endpoint, so no override controls are offered here — showing them '
                  'would imply a capability the API does not have.',
                  style: AdminType.bodySoft,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
