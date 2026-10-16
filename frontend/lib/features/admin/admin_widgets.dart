import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../../state/admin_range_controller.dart';
import 'admin_providers.dart';

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `12 Oct 2026, 14:05` — compact timestamp used across admin tables.
String formatDateTime(DateTime value) {
  final local = value.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${_months[local.month - 1]} ${local.year}, $hh:$mm';
}

/// `12 Oct 2026` — date only.
String formatDate(DateTime value) {
  final local = value.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// `4m ago` / `3h ago` / `5d ago` — relative age for operational lists.
String formatRelative(DateTime value) {
  final diff = DateTime.now().difference(value);
  if (diff.isNegative) return 'just now';
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return formatDate(value);
}

/// Short, non-technical order id: `8f3a…c21b`.
String shortId(String id) => id.length <= 10 ? id : '${id.substring(0, 8)}…';

/// The order states the backend's state machine actually produces.
const adminStatuses = ['PENDING', 'PAID', 'CONFIRMED', 'DRIVER_ASSIGNED', 'PAYMENT_FAILED', 'FAILED'];

/// Operational wording for the console — more precise than the storefront's
/// customer-facing labels.
String adminStatusLabel(String status) => switch (status) {
      'PENDING' => 'Awaiting payment',
      'PAID' => 'Paid · needs confirm',
      'CONFIRMED' => 'Preparing',
      'DRIVER_ASSIGNED' => 'Out for delivery',
      'PAYMENT_FAILED' => 'Payment failed',
      'FAILED' => 'Cancelled',
      _ => status.replaceAll('_', ' '),
    };

/// Status badge for admin tables. Never invents a state: anything outside the
/// real enum renders as-is.
class AdminStatusBadge extends StatelessWidget {
  const AdminStatusBadge({super.key, required this.status, this.dense = false});

  final String status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 7 : 9, vertical: dense ? 3 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon(status), size: dense ? 12 : 13, color: color),
          const SizedBox(width: 4),
          // Flexible so a long status can ellipsize inside a narrow table cell
          // or stacked card instead of overflowing its row.
          Flexible(
            child: Text(
              adminStatusLabel(status),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: dense ? 11 : 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Payment outcome badge. `null` means no payment attempt has happened yet —
/// rendered as "Not attempted", never as a failure.
class PaymentBadge extends StatelessWidget {
  const PaymentBadge({super.key, required this.status, this.attempts = 0, this.dense = false});

  final String? status;
  final int attempts;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'SUCCESS' => ('Paid', AppColors.success),
      'FAILED' => ('Failed', AppColors.error),
      _ => ('Not attempted', AdminColors.inkMuted),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 7 : 9, vertical: dense ? 3 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        attempts > 1 && status == 'FAILED' ? '$label · $attempts tries' : label,
        style: TextStyle(fontSize: dense ? 11 : 12, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page scaffolding
// ---------------------------------------------------------------------------

/// Page container for every admin screen: canvas background, constrained
/// content width, page title, optional description and right-aligned actions.
class AdminPage extends StatelessWidget {
  const AdminPage({
    super.key,
    required this.title,
    required this.child,
    this.description,
    this.actions = const [],
    this.showTitle = true,
  });

  final String title;
  final String? description;
  final List<Widget> actions;
  final Widget child;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final gutter = width >= AppBreakpoints.desktop
        ? 28.0
        : width >= AppBreakpoints.tablet
            ? 20.0
            : 16.0;

    return Container(
      color: AdminColors.canvas,
      // Admin pages are dense; the whole page scrolls under the fixed shell
      // header rather than trapping content in an unscrollable Column.
      child: SingleChildScrollView(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AdminLayout.contentMaxWidth),
            child: Padding(
              padding: EdgeInsets.fromLTRB(gutter, 24, gutter, 40),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (!showTitle) return child;

                  final titleBlock = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AdminType.pageTitle),
                      if (description != null) ...[
                        const SizedBox(height: 4),
                        Text(description!, style: AdminType.bodySoft),
                      ],
                    ],
                  );
                  final headerActions = Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: actions,
                  );
                  final titleAndBody = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [titleBlock, const SizedBox(height: AppSpacing.xl), child],
                  );

                  if (actions.isEmpty) return titleAndBody;

                  // The action row (date range, granularity, refresh) is wider
                  // than a phone screen. Below this width it stacks under the
                  // title and scrolls sideways, so it can never overflow.
                  if (constraints.maxWidth < 860) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        titleBlock,
                        const SizedBox(height: AppSpacing.lg),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: headerActions,
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        child,
                      ],
                    );
                  }

                  // Wide: title and actions share one line while the page body
                  // keeps the full width underneath, so dense tables are never
                  // starved of horizontal space.
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: titleBlock),
                          const SizedBox(width: AppSpacing.lg),
                          Flexible(
                            child: Align(
                              alignment: Alignment.topRight,
                              child: headerActions,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      child,
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// White card with a hairline border — the base surface of the admin console.
class AdminCard extends StatelessWidget {
  const AdminCard({super.key, required this.child, this.padding = const EdgeInsets.all(AppSpacing.lg), this.onTap});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AdminColors.card,
        borderRadius: BorderRadius.circular(AdminLayout.radius),
        border: Border.all(color: AdminColors.line),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AdminLayout.radius),
        child: card,
      ),
    );
  }
}

/// Card with a compact header row (title, optional subtitle, trailing action).
class AdminSection extends StatelessWidget {
  const AdminSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }

  /// Responsive section header.
  ///
  /// On wide cards the title sits on the left and the trailing control (a
  /// granularity switch, filter, or legend) is pushed to the right. On narrow
  /// cards the two would fight for the same line, so the trailing control is
  /// stacked under the title and — worst case — scrolls sideways instead of
  /// overflowing.
  Widget _header() {
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AdminType.sectionTitle),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!, style: AdminType.caption),
        ],
      ],
    );
    if (trailing == null) return titleBlock;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              const SizedBox(height: AppSpacing.md),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: trailing,
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: AppSpacing.md),
            trailing!,
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Metrics
// ---------------------------------------------------------------------------

/// Period-over-period change. Renders nothing when the previous period had no
/// data — we never display a percentage that wasn't calculated.
class DeltaBadge extends StatelessWidget {
  const DeltaBadge({super.key, required this.delta, this.dense = false});

  final MetricDelta? delta;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (delta == null || delta!.changePct == null) {
      return Text(
        'no prior data',
        style: TextStyle(fontSize: dense ? 11 : 11.5, color: AdminColors.inkMuted, fontWeight: FontWeight.w600),
      );
    }
    final pct = delta!.changePct!;
    final up = pct > 0;
    final flat = pct == 0;
    final color = flat
        ? AdminColors.inkSoft
        : up
            ? AppColors.success
            : AppColors.error;
    final icon = flat
        ? Icons.remove_rounded
        : up
            ? Icons.north_rounded
            : Icons.south_rounded;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: dense ? 2 : 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: dense ? 12 : 13, color: color),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              '${pct > 0 ? '+' : ''}${pct.toStringAsFixed(1)}%',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: dense ? 11 : 11.5,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One KPI tile: label, headline value, previous-period comparison.
///
/// [onTap] wires the card through to the related list, so a metric is always a
/// route rather than a dead end.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    this.delta,
    this.caption,
    this.onTap,
    this.trend,
  });

  final String label;
  final String value;
  final MetricDelta? delta;
  final String? caption;
  final VoidCallback? onTap;
  final Widget? trend;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label.toUpperCase(), style: AdminType.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (onTap != null)
              Icon(Icons.arrow_forward_rounded, size: 15, color: AdminColors.inkMuted),
          ],
        ),
        const SizedBox(height: 10),
        Text(value, style: AdminType.metricValue, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 8),
        if (delta != null) DeltaBadge(delta: delta, dense: true),
        if (caption != null) ...[
          const SizedBox(height: 6),
          Text(caption!, style: AdminType.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
        if (trend != null) ...[const SizedBox(height: 8), trend!],
      ],
    );
    return AdminCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      onTap: onTap,
      child: content,
    );
  }
}

/// Lays children out in a responsive wrapped grid: as many columns of at least
/// [minItemWidth] fit, evenly spaced. Admin equivalent of the storefront grid,
/// kept here so the admin module has no dependency on customer layout chrome.
class AdminGrid extends StatelessWidget {
  const AdminGrid({
    super.key,
    required this.children,
    this.minItemWidth = 240,
    this.spacing = AppSpacing.md,
    this.runSpacing = AppSpacing.md,
    this.minColumns = 1,
  });

  final List<Widget> children;
  final double minItemWidth;
  final double spacing;
  final double runSpacing;

  /// Floor on the number of columns, regardless of [minItemWidth].
  ///
  /// KPI grids set this to 2 so phones always get the compact two-up layout
  /// even though the tiles' natural width would otherwise collapse them to a
  /// single full-width column.
  final int minColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        var columns = ((available + spacing) / (minItemWidth + spacing)).floor();
        if (columns < 1) columns = 1;
        if (columns < minColumns) columns = minColumns;
        if (columns > children.length && children.isNotEmpty) columns = children.length;
        final itemWidth = (available - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (final child in children) SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Controls
// ---------------------------------------------------------------------------

/// Compact search box used by every admin list.
class AdminSearchField extends StatelessWidget {
  const AdminSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hintText = 'Search…',
    this.width = 300,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: AdminType.body,
        decoration: InputDecoration(
          isDense: true,
          hintText: hintText,
          hintStyle: const TextStyle(fontSize: 13, color: AdminColors.inkMuted),
          prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AdminColors.inkMuted),
          prefixIconConstraints: const BoxConstraints(minWidth: 40, maxHeight: 40),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close_rounded, size: 17),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          contentPadding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
          filled: true,
          fillColor: AdminColors.card,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AdminColors.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AdminColors.brand, width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// Compact dropdown filter.
class AdminDropdown<T> extends StatelessWidget {
  const AdminDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.width = 190,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? label;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<T>(
        // Re-keying on value keeps the closed field in sync with the filter
        // state without relying on the deprecated `value` parameter.
        key: ValueKey<T?>(value),
        initialValue: value,
        isExpanded: true,
        items: items,
        onChanged: onChanged,
        isDense: true,
        style: AdminType.body,
        icon: const Icon(Icons.expand_more_rounded, size: 18, color: AdminColors.inkSoft),
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          labelStyle: const TextStyle(fontSize: 11.5, color: AdminColors.inkMuted, fontWeight: FontWeight.w700),
          contentPadding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
          filled: true,
          fillColor: AdminColors.card,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AdminColors.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AdminColors.brand, width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// The reporting period control shown in the admin header.
///
/// Today / Last 7 / Last 30 / Custom, plus explicit date pickers when Custom
/// is selected. Everything downstream reads the shared [adminRangeProvider].
class DateRangeControl extends ConsumerWidget {
  const DateRangeControl({super.key, this.compact = false});

  final bool compact;

  Future<void> _pick(BuildContext context, WidgetRef ref, {required bool isFrom}) async {
    final current = ref.read(adminRangeProvider);
    final resolved = current.resolve();
    final initial = DateTime.parse(isFrom ? resolved.from : resolved.to);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null || !context.mounted) return;
    final ranges = ref.read(adminRangeProvider.notifier);
    if (current.preset != AdminRangePreset.custom) {
      ranges.setCustom(isFrom ? picked : DateTime.parse(resolved.from),
          isFrom ? DateTime.parse(resolved.to) : picked);
    } else if (isFrom) {
      ranges.setCustom(picked, current.customTo ?? picked);
    } else {
      ranges.setCustom(current.customFrom ?? picked, picked);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(adminRangeProvider);
    final controller = ref.read(adminRangeProvider.notifier);
    final resolved = range.resolve();

    final segmented = SegmentedButton<AdminRangePreset>(
      segments: const [
        ButtonSegment(value: AdminRangePreset.today, label: Text('Today')),
        ButtonSegment(value: AdminRangePreset.last7, label: Text('Last 7')),
        ButtonSegment(value: AdminRangePreset.last30, label: Text('Last 30')),
        ButtonSegment(value: AdminRangePreset.custom, label: Text('Custom')),
      ],
      selected: {range.preset},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => controller.select(selection.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: compact ? 11.5 : 12.5, fontWeight: FontWeight.w700),
        ),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.white : AdminColors.inkSoft),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? AdminColors.brand : AdminColors.card),
        side: WidgetStatePropertyAll(BorderSide(color: AdminColors.line)),
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: 8)),
      ),
    );

    if (range.preset != AdminRangePreset.custom) {
      return segmented;
    }

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        segmented,
        _DateButton(label: 'From', value: resolved.from, onTap: () => _pick(context, ref, isFrom: true)),
        _DateButton(label: 'To', value: resolved.to, onTap: () => _pick(context, ref, isFrom: false)),
      ],
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.calendar_today_rounded, size: 14),
      label: Text('$label: $value'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AdminColors.ink,
        side: const BorderSide(color: AdminColors.line),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        minimumSize: const Size(0, 36),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pagination
// ---------------------------------------------------------------------------

/// Revenue bucketing control: day / week / month.
class GranularityControl extends ConsumerWidget {
  const GranularityControl({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(adminGranularityProvider);
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'day', label: Text('Daily')),
        ButtonSegment(value: 'week', label: Text('Weekly')),
        ButtonSegment(value: 'month', label: Text('Monthly')),
      ],
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: (selection) =>
          ref.read(adminGranularityProvider.notifier).state = selection.first,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: compact ? 11 : 12, fontWeight: FontWeight.w700),
        ),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.white : AdminColors.inkSoft),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? AdminColors.brand : AdminColors.card),
        side: const WidgetStatePropertyAll(BorderSide(color: AdminColors.line)),
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: compact ? 9 : 13, vertical: 8),
        ),
      ),
    );
  }
}

/// Shared refresh action for every admin page.
class AdminRefreshButton extends StatelessWidget {
  const AdminRefreshButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.refresh_rounded, size: 16),
      label: const Text('Refresh'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AdminColors.ink,
        side: const BorderSide(color: AdminColors.line),
        minimumSize: const Size(0, 40),
        textStyle: AdminType.body,
      ),
    );
  }
}

class PaginationBar extends StatelessWidget {
  const PaginationBar({
    super.key,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.onPageChanged,
    this.onPageSizeChanged,
    this.pageSizeOptions = const [10, 20, 50],
  });

  final int page;
  final int pageSize;
  final int total;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int>? onPageSizeChanged;
  final List<int> pageSizeOptions;

  int get _pageCount => total == 0 ? 1 : ((total + pageSize - 1) ~/ pageSize);

  @override
  Widget build(BuildContext context) {
    final from = total == 0 ? 0 : ((page - 1) * pageSize) + 1;
    final to = (page * pageSize).clamp(0, total);
    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('$from–$to of $total', style: AdminType.caption),
        if (onPageSizeChanged != null)
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Rows', style: AdminType.caption),
              for (final size in pageSizeOptions)
                _PageSizeChip(
                  size: size,
                  selected: size == pageSize,
                  onTap: () => onPageSizeChanged!(size),
                ),
            ],
          ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: 'First page',
              onPressed: page > 1 ? () => onPageChanged(1) : null,
              icon: const Icon(Icons.first_page_rounded, size: 18),
            ),
            IconButton(
              tooltip: 'Previous page',
              onPressed: page > 1 ? () => onPageChanged(page - 1) : null,
              icon: const Icon(Icons.chevron_left_rounded, size: 20),
            ),
            Text('Page $page / $_pageCount', style: AdminType.label),
            IconButton(
              tooltip: 'Next page',
              onPressed: page < _pageCount ? () => onPageChanged(page + 1) : null,
              icon: const Icon(Icons.chevron_right_rounded, size: 20),
            ),
            IconButton(
              tooltip: 'Last page',
              onPressed: page < _pageCount ? () => onPageChanged(_pageCount) : null,
              icon: const Icon(Icons.last_page_rounded, size: 18),
            ),
          ],
        ),
      ],
    );
  }
}

class _PageSizeChip extends StatelessWidget {
  const _PageSizeChip({required this.size, required this.selected, required this.onTap});

  final int size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AdminColors.brand : AdminColors.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AdminColors.line),
        ),
        child: Text(
          '$size',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : AdminColors.inkSoft,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data table
// ---------------------------------------------------------------------------

class AdminColumn<T> {
  const AdminColumn({
    required this.label,
    required this.cell,
    this.width,
    this.flex = 1,
    this.align = TextAlign.start,
  });

  final String label;
  final Widget Function(BuildContext context, T row) cell;
  final double? width;
  final int flex;
  final TextAlign align;
}

/// Dense operational table that collapses into stacked cards below the
/// desktop breakpoint, so rows stay readable on a phone without horizontal
/// scrolling.
class AdminTable<T> extends StatelessWidget {
  const AdminTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.cardTitle,
    this.cardSubtitle,
  });

  final List<AdminColumn<T>> columns;
  final List<T> rows;
  final void Function(T row)? onRowTap;
  final String Function(T row)? cardTitle;
  final String Function(T row)? cardSubtitle;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final wide = MediaQuery.sizeOf(context).width >= AppBreakpoints.desktop;
    if (!wide) return _cards(context);
    return _table(context);
  }

  Widget _table(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 9),
          decoration: const BoxDecoration(
            color: AdminColors.metricFill,
            border: Border(
              top: BorderSide(color: AdminColors.line),
              bottom: BorderSide(color: AdminColors.line),
            ),
          ),
          child: Row(
            children: [
              for (final col in columns)
                if (col.width != null)
                  SizedBox(width: col.width, child: _headerCell(col))
                else
                  Expanded(flex: col.flex, child: _headerCell(col)),
            ],
          ),
        ),
        for (var i = 0; i < rows.length; i++) _tableRow(context, rows[i], i),
      ],
    );
  }

  Widget _headerCell(AdminColumn<T> col) => Text(
        col.label.toUpperCase(),
        textAlign: col.align,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AdminType.tableHeader,
      );

  Widget _tableRow(BuildContext context, T row, int index) {
    return Material(
      color: index.isEven ? AdminColors.card : AdminColors.metricFill,
      child: InkWell(
        onTap: onRowTap == null ? null : () => onRowTap!(row),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 11),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AdminColors.lineSoft))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (final col in columns)
                if (col.width != null)
                  SizedBox(width: col.width, child: col.cell(context, row))
                else
                  Expanded(flex: col.flex, child: col.cell(context, row)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cards(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          AdminCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            onTap: onRowTap == null ? null : () => onRowTap!(rows[i]),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (cardTitle != null || cardSubtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (cardTitle != null)
                                Text(cardTitle!(rows[i]), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                              if (cardSubtitle != null) ...[
                                const SizedBox(height: 2),
                                Text(cardSubtitle!(rows[i]), style: AdminType.caption),
                              ],
                            ],
                          ),
                        ),
                        if (onRowTap != null)
                          const Icon(Icons.chevron_right_rounded, size: 18, color: AdminColors.inkMuted),
                      ],
                    ),
                  ),
                const Divider(height: 12),
                for (final col in columns)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 118,
                          child: Text(col.label.toUpperCase(), style: AdminType.tableHeader),
                        ),
                        Expanded(child: col.cell(context, rows[i])),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (i != rows.length - 1) const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

/// Loading placeholder consistent with admin density.
class AdminLoading extends StatelessWidget {
  const AdminLoading({super.key, this.label = 'Loading…', this.rows = 5});

  final String label;
  final int rows;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(label, style: AdminType.caption)),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          for (var i = 0; i < rows; i++) ...[
            SkeletonBox(height: 14, width: 120 + (i % 3) * 90.0),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
      ),
    );
  }
}

/// Calm, non-alarmist empty state — never implies something is broken.
class AdminEmpty extends StatelessWidget {
  const AdminEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AdminColors.metricFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AdminColors.line),
              ),
              child: Icon(icon, size: 22, color: AdminColors.inkSoft),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: AdminType.sectionTitle, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, style: AdminType.bodySoft, textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: AppSpacing.lg), action!],
          ],
        ),
      ),
    );
  }
}

/// Error surface with a retry affordance. Shows the server's own message.
class AdminErrorState extends StatelessWidget {
  const AdminErrorState({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Column(
          children: [
            const Icon(Icons.error_outline_rounded, size: 26, color: AppColors.error),
            const SizedBox(height: AppSpacing.sm),
            Text('Something went wrong', style: AdminType.sectionTitle),
            const SizedBox(height: 4),
            Text(message, style: AdminType.bodySoft, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Try again'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AdminColors.ink,
                side: const BorderSide(color: AdminColors.line),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
