import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'theme.dart';

/// How a catalogue list reveals more results.
///
/// * [infinite] — the next page loads automatically as the user scrolls to the
///   bottom of the list.
/// * [pagination] — the user moves page by page with Previous / Next controls
///   and numbered page buttons.
enum BrowseMode {
  infinite,
  pagination;

  String get label => switch (this) {
        BrowseMode.infinite => 'Infinite scroll',
        BrowseMode.pagination => 'Numbered pages',
      };

  String get shortLabel => switch (this) {
        BrowseMode.infinite => 'Scroll',
        BrowseMode.pagination => 'Pages',
      };

  IconData get icon => switch (this) {
        BrowseMode.infinite => Icons.swipe_vertical_rounded,
        BrowseMode.pagination => Icons.menu_book_rounded,
      };

  String get tooltip => switch (this) {
        BrowseMode.infinite =>
          'Load more automatically as you scroll to the end',
        BrowseMode.pagination =>
          'Browse page by page with Previous / Next controls',
      };
}

/// Session-wide browse preference.
///
/// A single provider (rather than per-screen state) is what keeps the user's
/// chosen mode consistent while they navigate between the home page, Explore
/// and restaurant menus.
class BrowseModeController extends Notifier<BrowseMode> {
  @override
  BrowseMode build() => BrowseMode.infinite;

  void select(BrowseMode mode) {
    if (state != mode) state = mode;
  }
}

final browseModeProvider =
    NotifierProvider<BrowseModeController, BrowseMode>(BrowseModeController.new);

/// Fetches one page of results. Used for backend pagination.
typedef PagedFetch<T> = Future<Paginated<T>> Function(int page, int pageSize);

/// Read-only surface every paged list exposes, so the shared footer/controls can
/// be typed without knowing the element type.
abstract class PagedListState extends ChangeNotifier {
  int get page;
  int get total;
  int get totalPages;
  int get rangeStart;
  int get rangeEnd;

  /// A full (re)load is in flight and the list is expected to be replaced.
  bool get loading;

  /// A single page hop (pagination mode) is in flight; current items stay put.
  bool get paging;

  /// The next page is being appended (infinite mode).
  bool get loadingMore;

  bool get busy;
  bool get hasMore;
  bool get isEmpty;
  bool get isPaged;
  String? get error;
  String? get moreError;

  Future<void> refresh();
  Future<void> loadMore();
  Future<void> goToPage(int page);
}

/// A paginated list, backed either by the API (one page per request) or by a
/// fully-loaded in-memory list that is sliced client-side.
///
/// The controller guarantees no duplicate rows (items are de-duplicated by id)
/// and exposes loading / empty / error / end-of-list state so screens can render
/// the right thing in every case.
class PagedListController<T> extends PagedListState {
  PagedListController({
    PagedFetch<T>? fetch,
    List<T>? local,
    required String Function(T item) idOf,
    this.pageSize = 24,
  })  : _fetch = fetch,
        _local = local,
        _idOf = idOf {
    _serverPageSize = pageSize;
  }

  PagedFetch<T>? _fetch;
  List<T>? _local;
  final String Function(T item) _idOf;
  final int pageSize;

  final List<T> _items = [];
  final Set<String> _ids = {};
  int _page = 1;
  int _total = 0;
  int _serverPageSize = 24;
  bool _loading = false;
  bool _paging = false;
  bool _loadingMore = false;
  bool _disposed = false;
  String? _error;
  String? _moreError;

  List<T> get items => List.unmodifiable(_items);

  @override
  int get page => _page;

  @override
  int get total => _total;

  @override
  int get totalPages {
    if (_total == 0) return 1;
    final size = _serverPageSize > 0 ? _serverPageSize : pageSize;
    return (_total + size - 1) ~/ size;
  }

  int get _effectiveSize => _serverPageSize > 0 ? _serverPageSize : pageSize;

  @override
  int get rangeStart => _total == 0 || _items.isEmpty
      ? 0
      : (_page - 1) * _effectiveSize + 1;

  @override
  int get rangeEnd =>
      _total == 0 || _items.isEmpty ? 0 : rangeStart + _items.length - 1;

  @override
  bool get loading => _loading;

  @override
  bool get paging => _paging;

  @override
  bool get loadingMore => _loadingMore;

  @override
  bool get busy => _loading || _paging || _loadingMore;

  @override
  bool get hasMore => _page < totalPages;

  @override
  bool get isEmpty => _items.isEmpty;

  @override
  bool get isPaged => totalPages > 1;

  @override
  String? get error => _error;

  @override
  String? get moreError => _moreError;

  /// Points the controller at a new API endpoint (used when filters change) and,
  /// by default, reloads the first page.
  void updateFetch(PagedFetch<T> fetch, {bool reload = true}) {
    _fetch = fetch;
    _local = null;
    if (reload) refresh();
  }

  /// Swaps in a client-side list. Paging is synchronous and immediate, so a
  /// filter change never flashes a loading skeleton.
  void setLocalItems(List<T> items, {bool resetPage = true}) {
    _local = items;
    _total = items.length;
    _serverPageSize = pageSize;
    if (resetPage) _page = 1;
    _page = _page.clamp(1, totalPages);
    _replaceWith(_slice(_page));
    _error = null;
    _moreError = null;
    _loading = false;
    _paging = false;
    _loadingMore = false;
    _notify();
  }

  List<T> _slice(int page) {
    final all = _local;
    if (all == null || all.isEmpty) return const [];
    final start = (page - 1) * pageSize;
    if (start >= all.length) return const [];
    final end = (start + pageSize).clamp(0, all.length);
    return all.sublist(start, end);
  }

  void _replaceWith(List<T> incoming) {
    _items.clear();
    _ids.clear();
    _addAll(incoming);
  }

  void _addAll(List<T> incoming) {
    for (final item in incoming) {
      if (_ids.add(_idOf(item))) _items.add(item);
    }
  }

  @override
  Future<void> refresh() async {
    _error = null;
    _moreError = null;
    _loading = true;
    _notify();

    if (_local != null) {
      _page = 1;
      _total = _local!.length;
      _replaceWith(_slice(1));
      _loading = false;
      _notify();
      return;
    }

    final fetch = _fetch;
    if (fetch == null) {
      _loading = false;
      _notify();
      return;
    }

    try {
      final result = await fetch(1, pageSize);
      if (_disposed) return;
      _page = 1;
      _total = result.total;
      _serverPageSize = result.pageSize > 0 ? result.pageSize : pageSize;
      _replaceWith(result.items);
      _loading = false;
      _notify();
    } catch (e) {
      if (_disposed) return;
      _loading = false;
      _replaceWith(const []);
      _total = 0;
      _page = 1;
      _error = _messageFor(e);
      _notify();
    }
  }

  @override
  Future<void> loadMore() async {
    if (_loading || _paging || _loadingMore || !hasMore) return;

    if (_local != null) {
      _page += 1;
      _addAll(_slice(_page));
      _moreError = null;
      _notify();
      return;
    }

    final fetch = _fetch;
    if (fetch == null) return;
    final next = _page + 1;
    _loadingMore = true;
    _moreError = null;
    _notify();
    try {
      final result = await fetch(next, pageSize);
      if (_disposed) return;
      _addAll(result.items);
      _page = next;
      _total = result.total;
      if (result.pageSize > 0) _serverPageSize = result.pageSize;
      _loadingMore = false;
      _notify();
    } catch (e) {
      if (_disposed) return;
      _loadingMore = false;
      _moreError = _messageFor(e);
      _notify();
    }
  }

  @override
  Future<void> goToPage(int page) async {
    final target = page.clamp(1, totalPages);
    if (_loading || _paging) return;
    if (target == _page && _items.isNotEmpty) return;

    if (_local != null) {
      _page = target;
      _replaceWith(_slice(target));
      _moreError = null;
      _notify();
      return;
    }

    final fetch = _fetch;
    if (fetch == null) return;
    _paging = true;
    _error = null;
    _moreError = null;
    _notify();
    try {
      final result = await fetch(target, pageSize);
      if (_disposed) return;
      _replaceWith(result.items);
      _page = target;
      _total = result.total;
      if (result.pageSize > 0) _serverPageSize = result.pageSize;
      _paging = false;
      _notify();
    } catch (e) {
      if (_disposed) return;
      _paging = false;
      _error = _messageFor(e);
      _notify();
    }
  }

  String _messageFor(Object error) =>
      error is ApiException ? error.message : 'Network error';

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Convenience factory for a fully in-memory paged list (menus, curated home
/// sections) where the whole set is already loaded.
PagedListController<T> localPagedList<T>({
  required List<T> items,
  required String Function(T item) idOf,
  int pageSize = 24,
}) =>
    PagedListController<T>(local: items, idOf: idOf, pageSize: pageSize);

// ---------------------------------------------------------------------------
// Controls
// ---------------------------------------------------------------------------

/// The Pagination / Infinite-scroll switch. Reads and writes the session-wide
/// [browseModeProvider] so the choice carries across screens.
class BrowseModeToggle extends ConsumerWidget {
  const BrowseModeToggle({super.key, this.compact = false});

  /// Icon-only labels for tight toolbars (mobile filter bars).
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(browseModeProvider);
    return Semantics(
      container: true,
      label: 'Browsing mode',
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (!compact)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Text(
                'View:',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          for (final option in BrowseMode.values)
            _ModeOption(
              mode: option,
              selected: option == mode,
              compact: compact,
              onTap: () =>
                  ref.read(browseModeProvider.notifier).select(option),
            ),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.mode,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final BrowseMode mode;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.forestDeep : AppColors.textSecondary;
    return Tooltip(
      message: mode.tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        label: mode.label,
        child: Material(
          color: selected ? AppColors.lime : AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 38),
              padding: EdgeInsets.symmetric(
                  horizontal: compact ? 10 : 14, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: selected ? AppColors.limeDark : AppColors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(mode.icon, size: 16, color: fg),
                  const SizedBox(width: 6),
                  Text(
                    compact ? mode.shortLabel : mode.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A windowed list of page numbers, with `null` marking an ellipsis gap.
@visibleForTesting
List<int?> pageNumberWindow(int current, int total, {int window = 1}) {
  if (total <= 7) return [for (var i = 1; i <= total; i++) i];
  final keep = <int>{1, total};
  for (var i = current - window; i <= current + window; i++) {
    if (i >= 1 && i <= total) keep.add(i);
  }
  final sorted = keep.toList()..sort();
  final out = <int?>[];
  int? previous;
  for (final value in sorted) {
    if (previous != null && value - previous > 1) out.add(null);
    out.add(value);
    previous = value;
  }
  return out;
}

/// Numbered pages plus Previous / Next, with a "showing X–Y of N" summary.
/// Wraps on narrow screens so it never overflows on mobile.
class PaginationControls extends StatelessWidget {
  const PaginationControls({
    super.key,
    required this.page,
    required this.totalPages,
    required this.rangeStart,
    required this.rangeEnd,
    required this.total,
    required this.onPageChanged,
    this.enabled = true,
  });

  final int page;
  final int totalPages;
  final int rangeStart;
  final int rangeEnd;
  final int total;
  final ValueChanged<int> onPageChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final canPrev = enabled && page > 1;
    final canNext = enabled && page < totalPages;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      children: [
        Text(
          total == 0 ? 'No results' : 'Showing $rangeStart–$rangeEnd of $total',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Previous page',
              onPressed: canPrev ? () => onPageChanged(page - 1) : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            for (final number in pageNumberWindow(page, totalPages))
              number == null
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 2),
                      child: Text('…',
                          style: TextStyle(color: AppColors.textMuted)),
                    )
                  : _PageButton(
                      number: number,
                      selected: number == page,
                      enabled: enabled,
                      onTap: () => onPageChanged(number),
                    ),
            IconButton(
              tooltip: 'Next page',
              onPressed: canNext ? () => onPageChanged(page + 1) : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        Text(
          'Page $page of $totalPages',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    required this.number,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final int number;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Page $number',
        child: Tooltip(
          message: 'Go to page $number',
          child: Material(
            color: selected ? AppColors.forest : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: enabled && !selected ? onTap : null,
              child: Container(
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                alignment: Alignment.center,
                child: Text(
                  '$number',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? Colors.white
                        : enabled
                            ? AppColors.textPrimary
                            : AppColors.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bottom-of-list affordance for infinite-scroll mode: an auto-triggered
/// "Load more" (kept as a real button for accessibility and short pages), a
/// spinner while a page is in flight, an inline error with retry, and a
/// "you've reached the end" marker.
class InfiniteScrollFooter extends StatelessWidget {
  const InfiniteScrollFooter({
    super.key,
    required this.hasMore,
    required this.loadingMore,
    required this.error,
    required this.onLoadMore,
    this.endLabel = "You've reached the end",
    this.visible = true,
  });

  final bool hasMore;
  final bool loadingMore;
  final String? error;
  final VoidCallback onLoadMore;
  final String endLabel;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    if (loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }

    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: onLoadMore,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    if (hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: OutlinedButton.icon(
            onPressed: onLoadMore,
            icon: const Icon(Icons.expand_more_rounded, size: 20),
            label: const Text('Load more'),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline_rounded,
                size: 16, color: AppColors.success),
            const SizedBox(width: 6),
            Text(
              endLabel,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders the correct affordance for [mode] given a paged [controller].
///
/// * Pagination mode → numbered [PaginationControls] (only when there is more
///   than one page).
/// * Infinite mode → [InfiniteScrollFooter] (load-more / spinner / end marker).
class PagedResultsFooter extends StatelessWidget {
  const PagedResultsFooter({
    super.key,
    required this.controller,
    required this.mode,
    this.endLabel,
    this.onPageChanged,
  });

  final PagedListState controller;
  final BrowseMode mode;
  final String? endLabel;

  /// Overrides [PagedListState.goToPage] — screens use this to also scroll the
  /// list back to the top when the user hops to another page.
  final ValueChanged<int>? onPageChanged;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    if (controller.isEmpty && !controller.busy) return const SizedBox.shrink();

    if (mode == BrowseMode.pagination) {
      if (!controller.isPaged) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.lg),
        child: PaginationControls(
          page: controller.page,
          totalPages: controller.totalPages,
          rangeStart: controller.rangeStart,
          rangeEnd: controller.rangeEnd,
          total: controller.total,
          enabled: !controller.busy,
          onPageChanged: onPageChanged ?? controller.goToPage,
        ),
      );
    }

    // Infinite: only show the end marker once paging has actually happened, so
    // a short list does not say "you've reached the end" for two rows.
    final showEnd = controller.page > 1 || controller.isPaged;
    return InfiniteScrollFooter(
      hasMore: controller.hasMore,
      loadingMore: controller.loadingMore,
      error: controller.moreError,
      onLoadMore: controller.loadMore,
      endLabel: endLabel ?? "You've reached the end",
      visible: controller.hasMore || showEnd || controller.moreError != null,
    );
  }
}

/// Schedules a one-shot check (after the next frame) that loads the next page
/// when the [anchorKey] widget — typically the list footer — is within
/// [threshold] pixels of the visible bottom of the [scrollableKey] scrollable.
///
/// This is how section-scoped infinite scroll works on a page whose list is
/// only one of several sections: the trigger is the *section* footer's
/// position, not the bottom of the whole page. Call it from scroll
/// notifications, after data loads, and after each completed load so short
/// pages keep auto-filling until the footer is off screen. The controller
/// itself ignores duplicate requests, so repeated calls are safe.
void scheduleNearBottomLoad({
  required GlobalKey anchorKey,
  required GlobalKey scrollableKey,
  required VoidCallback onLoadMore,
  int threshold = 320,
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final anchorContext = anchorKey.currentContext;
    final scrollContext = scrollableKey.currentContext;
    if (anchorContext == null || scrollContext == null) return;
    final anchorBox = anchorContext.findRenderObject() as RenderBox?;
    final scrollBox = scrollContext.findRenderObject() as RenderBox?;
    if (anchorBox == null ||
        scrollBox == null ||
        !anchorBox.attached ||
        !scrollBox.attached ||
        anchorBox.size.isEmpty ||
        scrollBox.size.isEmpty) {
      return;
    }
    final anchorTop = anchorBox.localToGlobal(Offset.zero).dy;
    final scrollBottom =
        scrollBox.localToGlobal(Offset.zero).dy + scrollBox.size.height;
    if (anchorTop - scrollBottom <= threshold) onLoadMore();
  });
}
