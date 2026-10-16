import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../shared/cards.dart';
import '../../shared/layout.dart';
import '../../shared/paged_list.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../../state/auth_controller.dart';

/// What the catalogue is showing: whole restaurants, or individual dishes.
enum _BrowseMode { restaurants, dishes }

/// Every ordering the catalogue exposes. Restaurant and dish lists use the
/// subset that makes sense for them (see [_sortOptions]).
enum _SortMode {
  recommended,
  rating,
  popular,
  eta,
  newest,
  priceAsc,
  priceDesc,
  az,
  za,
  openFirst,
}

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({
    super.key,
    this.initialQuery = '',
    this.initialCategory = '',
    this.initialFoodType = '',
    this.initialSort = '',
    this.initialView = '',
  });

  final String initialQuery;

  /// A selected catalogue category (cuisine **or** global dish category).
  final String initialCategory;

  /// '', 'veg' or 'non_veg'.
  final String initialFoodType;

  /// Backend sort token, e.g. 'rating', 'popular', 'price_asc'.
  final String initialSort;

  /// 'dishes' switches to dish-first browsing.
  final String initialView;

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final _searchController = TextEditingController();
  final _scroll = ScrollController();
  final _listKey = GlobalKey();
  final _dishFooterKey = GlobalKey();
  final _restFooterKey = GlobalKey();

  List<Restaurant> _all = const [];
  List<String> _chipLabels = const [];
  bool _chipsRequested = false;

  /// Dishes are paged by the backend (the dish catalogue is large).
  late final PagedListController<Dish> _dishPaged;

  /// Restaurants are loaded in full, then sliced client-side (the test/stub
  /// contract and the small catalogue both assume the whole set is available).
  late final PagedListController<Restaurant> _restPaged;

  String _query = '';
  String _category = '';
  String _foodType = '';
  bool _onlyOpen = false;
  _BrowseMode _mode = _BrowseMode.restaurants;
  _SortMode _sort = _SortMode.recommended;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _dishPaged = PagedListController<Dish>(idOf: (d) => d.id, pageSize: 24);
    _restPaged = PagedListController<Restaurant>(
      idOf: (r) => r.id,
      pageSize: 24,
      local: const [],
    );
    _dishPaged.addListener(_onPagedChanged);
    _restPaged.addListener(_onPagedChanged);
    _applyInitial();
    _load();
  }

  @override
  void dispose() {
    _dishPaged.removeListener(_onPagedChanged);
    _restPaged.removeListener(_onPagedChanged);
    _dishPaged.dispose();
    _restPaged.dispose();
    _searchController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onPagedChanged() {
    if (!mounted) return;
    setState(() {});
    _maybeLoadMore();
  }

  /// Infinite mode: fetch/append the next slice when the active footer nears the
  /// viewport bottom. The controllers ignore duplicate calls.
  void _maybeLoadMore() {
    if (!mounted) return;
    if (ref.read(browseModeProvider) != BrowseMode.infinite) return;
    final controller = _mode == _BrowseMode.dishes ? _dishPaged : _restPaged;
    if (controller.busy || !controller.hasMore) return;
    scheduleNearBottomLoad(
      anchorKey:
          _mode == _BrowseMode.dishes ? _dishFooterKey : _restFooterKey,
      scrollableKey: _listKey,
      onLoadMore: controller.loadMore,
    );
  }

  /// Applies a change to the *restaurant* filters and re-slices locally.
  void _applyRestFilters(VoidCallback change) {
    setState(change);
    _restPaged.setLocalItems(_visibleRestaurants);
  }

  @override
  void didUpdateWidget(covariant ExploreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The desktop header search re-navigates to /explore?q=… while Explore may
    // already be mounted, so react to changed params rather than only initState.
    if (oldWidget.initialQuery != widget.initialQuery ||
        oldWidget.initialCategory != widget.initialCategory ||
        oldWidget.initialFoodType != widget.initialFoodType ||
        oldWidget.initialSort != widget.initialSort ||
        oldWidget.initialView != widget.initialView) {
      _applyInitial();
      _load();
    }
  }

  void _applyInitial() {
    _query = widget.initialQuery;
    _category = widget.initialCategory;
    _foodType = widget.initialFoodType;
    _mode = widget.initialView == 'dishes'
        ? _BrowseMode.dishes
        : _BrowseMode.restaurants;
    _sort = _sortFromParam(widget.initialSort) ??
        (_mode == _BrowseMode.dishes ? _SortMode.popular : _SortMode.recommended);
    if (!_sortOptions.contains(_sort)) {
      _sort = _mode == _BrowseMode.dishes
          ? _SortMode.popular
          : _SortMode.recommended;
    }
    _searchController.text = widget.initialQuery;
  }

  static _SortMode? _sortFromParam(String value) => switch (value) {
        'rating' => _SortMode.rating,
        'popular' => _SortMode.popular,
        'eta' => _SortMode.eta,
        'newest' => _SortMode.newest,
        'price_asc' => _SortMode.priceAsc,
        'price_desc' => _SortMode.priceDesc,
        'name' => _SortMode.az,
        _ => null,
      };

  List<_SortMode> get _sortOptions => _mode == _BrowseMode.dishes
      ? const [
          _SortMode.popular,
          _SortMode.priceAsc,
          _SortMode.priceDesc,
          _SortMode.newest,
          _SortMode.az,
        ]
      : const [
          _SortMode.recommended,
          _SortMode.rating,
          _SortMode.popular,
          _SortMode.eta,
          _SortMode.newest,
          _SortMode.az,
          _SortMode.za,
          _SortMode.openFirst,
        ];

  String get _restaurantSortParam => switch (_sort) {
        _SortMode.rating => 'rating',
        _SortMode.popular => 'popular',
        _SortMode.eta => 'eta',
        _SortMode.newest => 'newest',
        _ => 'name',
      };

  String get _dishSortParam => switch (_sort) {
        _SortMode.priceAsc => 'price_asc',
        _SortMode.priceDesc => 'price_desc',
        _SortMode.newest => 'newest',
        _SortMode.az => 'name',
        _ => 'popular',
      };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ref.read(apiClientProvider);
    if (_mode == _BrowseMode.dishes) {
      // Backend pagination: one page per request, filters/sort sent upstream.
      _dishPaged.updateFetch(
        (page, pageSize) => api.dishes(
          page: page,
          pageSize: pageSize,
          search: _query.isEmpty ? null : _query,
          category: _category.isEmpty ? null : _category,
          foodType: _foodType.isEmpty ? null : _foodType,
          sort: _dishSortParam,
        ),
      );
      if (mounted) setState(() => _loading = false);
      await _ensureChips();
      return;
    }
    try {
      final data = await api.allRestaurants(
        search: _query.isEmpty ? null : _query,
        category: _category.isEmpty ? null : _category,
        foodType: _foodType.isEmpty ? null : _foodType,
        sort: _restaurantSortParam,
      );
      if (!mounted) return;
      setState(() => _all = data.items);
      _restPaged.setLocalItems(_visibleRestaurants);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Network error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    await _ensureChips();
  }

  /// Chip list of cuisines + global dish categories, fetched once from the
  /// unfiltered catalogue so it stays stable while filters change.
  Future<void> _ensureChips() async {
    if (_chipLabels.isNotEmpty || _chipsRequested) return;
    _chipsRequested = true;
    try {
      final all = await ref.read(apiClientProvider).allRestaurants();
      final labels = <String>{};
      for (final r in all.items) {
        if (r.cuisine.trim().isNotEmpty) labels.add(r.cuisine.trim());
        for (final c in r.categories) {
          if (c.trim().isNotEmpty) labels.add(c.trim());
        }
      }
      final sorted = labels.toList()..sort();
      if (mounted) setState(() => _chipLabels = sorted);
    } catch (_) {
      _chipsRequested = false;
    }
  }

  List<Restaurant> get _visibleRestaurants {
    final list = List<Restaurant>.from(_all);
    if (_onlyOpen) list.retainWhere((r) => r.available);
    switch (_sort) {
      case _SortMode.az:
        list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case _SortMode.za:
        list.sort(
            (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
      case _SortMode.openFirst:
        list.sort((a, b) {
          if (a.available == b.available) return a.name.compareTo(b.name);
          return a.available ? -1 : 1;
        });
      default:
        break;
    }
    return list;
  }

  void _reloadWith(VoidCallback change) {
    setState(change);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final dishesMode = _mode == _BrowseMode.dishes;
    final browseMode = ref.watch(browseModeProvider);
    final controller = dishesMode ? _dishPaged : _restPaged;
    final resultCount = controller.total;
    // Re-slice on mode toggle so the two browsing modes agree on the current page.
    ref.listen(browseModeProvider, (_, __) {
      if (_mode == _BrowseMode.dishes) {
        if (!_dishPaged.isEmpty) _dishPaged.refresh();
      } else {
        _restPaged.setLocalItems(_visibleRestaurants);
      }
    });
    return CustomerShell(
      navIndex: 1,
      title: 'Explore',
      body: RefreshIndicator(
        onRefresh: _load,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollEndNotification) _maybeLoadMore();
            return false;
          },
          child: ListView(
            key: _listKey,
            controller: _scroll,
            padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
            children: [
            ContentWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSpacing.lg),
                  Text('Find your next favourite',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: AppSpacing.md),
                  _SearchField(
                    controller: _searchController,
                    onSubmit: () =>
                        _reloadWith(() => _query = _searchController.text.trim()),
                    onClear: () => _reloadWith(() {
                      _searchController.clear();
                      _query = '';
                    }),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _ModeToggle(
                    mode: _mode,
                    onChanged: (m) => _reloadWith(() {
                      _mode = m;
                      if (!_sortOptions.contains(_sort)) {
                        _sort = m == _BrowseMode.dishes
                            ? _SortMode.popular
                            : _SortMode.recommended;
                      }
                    }),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_chipLabels.isNotEmpty)
                    HorizontalChipScroller(
                      semanticLabel: 'Filter by category',
                      child: Row(
                        children: [
                          _FilterChip(
                            label: 'All',
                            icon: Icons.grid_view_rounded,
                            selected: _category.isEmpty,
                            onTap: () => _reloadWith(() => _category = ''),
                          ),
                          for (final c in _chipLabels)
                            _FilterChip(
                              label: c,
                              selected: _category == c,
                              onTap: () => _reloadWith(() => _category = c),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _FoodTypeChips(
                        value: _foodType,
                        onChanged: (v) => _reloadWith(() => _foodType = v),
                      ),
                      if (!dishesMode)
                        _ToggleChip(
                          label: 'Open now',
                          icon: Icons.check_circle_outline_rounded,
                          selected: _onlyOpen,
                          onTap: () =>
                              _applyRestFilters(() => _onlyOpen = !_onlyOpen),
                        ),
                      _SortDropdown(
                        value: _sort,
                        options: _sortOptions,
                        onChanged: (v) => _reloadWith(() => _sort = v),
                      ),
                      const BrowseModeToggle(compact: true),
                      Text(
                        _loading
                            ? 'Searching…'
                            : '$resultCount result${resultCount == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
            if (dishesMode)
              _dishesSection(browseMode)
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: ErrorState(message: _error!, onRetry: _load),
              )
            else if (_loading)
              ContentWidth(
                child: ResponsiveWrap(
                  minItemWidth: 300,
                  children: List.generate(
                      6, (_) => const SkeletonCard(imageHeight: 168)),
                ),
              )
            else if (_restPaged.isEmpty)
              ContentWidth(
                child: AppCard(
                  child: EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No matches found',
                    subtitle: _emptySubtitle,
                    action: FilledButton(
                      onPressed: _clearFilters,
                      child: const Text('Clear filters'),
                    ),
                  ),
                ),
              )
            else
              ContentWidth(
                child: Column(
                  children: [
                    ResponsiveWrap(
                      minItemWidth: 300,
                      children: [
                        for (final r in _restPaged.items)
                          RestaurantCard(
                              restaurant: r,
                              onTap: () =>
                                  context.push('/restaurant/${r.id}')),
                      ],
                    ),
                    KeyedSubtree(
                      key: _restFooterKey,
                      child: PagedResultsFooter(
                        controller: _restPaged,
                        mode: browseMode,
                        endLabel: 'All restaurants loaded',
                        onPageChanged: (page) {
                          _restPaged.goToPage(page);
                          _scrollToTop();
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
          ),
        ),
      ),
    );
  }

  /// Dishes are paged by the backend, so loading / empty / error all come from
  /// the controller rather than the screen's own `_loading` / `_error`.
  Widget _dishesSection(BrowseMode browseMode) {
    if (_dishPaged.loading) {
      return ContentWidth(
        child: ResponsiveWrap(
          minItemWidth: 300,
          children:
              List.generate(6, (_) => const SkeletonCard(imageHeight: 168)),
        ),
      );
    }
    if (_dishPaged.error != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ErrorState(
            message: _dishPaged.error!, onRetry: _dishPaged.refresh),
      );
    }
    return ContentWidth(
      child: Column(
        children: [
          if (_dishPaged.isEmpty)
            AppCard(
              child: EmptyState(
                icon: Icons.search_off_rounded,
                title: 'No dishes found',
                subtitle: _emptySubtitle,
                action: FilledButton(
                  onPressed: _clearFilters,
                  child: const Text('Clear filters'),
                ),
              ),
            )
          else
            DishGrid(
              minItemWidth: 260,
              dishes: [
                for (final d in _dishPaged.items) DishCardData.fromDish(d),
              ],
            ),
          KeyedSubtree(
            key: _dishFooterKey,
            child: PagedResultsFooter(
              controller: _dishPaged,
              mode: browseMode,
              endLabel: 'All dishes loaded',
              onPageChanged: (page) {
                _dishPaged.goToPage(page);
                _scrollToTop();
              },
            ),
          ),
        ],
      ),
    );
  }

  void _scrollToTop() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  String get _emptySubtitle {
    if (_query.isNotEmpty) {
      return 'Nothing matched “$_query”. Try a different dish, cuisine or restaurant.';
    }
    return 'Try another category or clear your filters.';
  }

  void _clearFilters() {
    _searchController.clear();
    _reloadWith(() {
      _query = '';
      _category = '';
      _foodType = '';
      _onlyOpen = false;
    });
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField(
      {required this.controller,
      required this.onSubmit,
      required this.onClear});

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => onSubmit(),
      decoration: InputDecoration(
        hintText: 'Search restaurants, cuisines or dishes…',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: IconButton(
          tooltip: 'Clear',
          onPressed: onClear,
          icon: const Icon(Icons.close_rounded),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: const BorderSide(color: AppColors.forest, width: 1.8),
        ),
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final _BrowseMode mode;
  final ValueChanged<_BrowseMode> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget option(_BrowseMode m, IconData icon, String label) {
      final selected = mode == m;
      return Material(
        color: selected ? AppColors.forest : AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: () => onChanged(m),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                  color: selected ? AppColors.forest : AppColors.border),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 16,
                    color: selected ? AppColors.lime : AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: selected ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: AppSpacing.sm,
      children: [
        option(_BrowseMode.restaurants, Icons.storefront_outlined, 'Restaurants'),
        option(_BrowseMode.dishes, Icons.ramen_dining_outlined, 'Dishes'),
      ],
    );
  }
}

class _FoodTypeChips extends StatelessWidget {
  const _FoodTypeChips({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String v, String label, IconData icon) => _ToggleChip(
          label: label,
          icon: icon,
          selected: value == v,
          onTap: () => onChanged(value == v ? '' : v),
        );
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        chip('veg', 'Veg', Icons.eco_outlined),
        chip('non_veg', 'Non-veg', Icons.set_meal_outlined),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(
      {required this.label,
      required this.selected,
      required this.onTap,
      this.icon});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Material(
        color: selected ? AppColors.forest : AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                  color: selected ? AppColors.forest : AppColors.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: 16,
                      color:
                          selected ? AppColors.lime : AppColors.textSecondary),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: selected ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.lime : AppColors.white,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
                color: selected ? AppColors.limeDark : AppColors.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppColors.forestDeep),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.forestDeep)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SortDropdown extends StatelessWidget {
  const _SortDropdown(
      {required this.value,
      required this.options,
      required this.onChanged});

  final _SortMode value;
  final List<_SortMode> options;
  final ValueChanged<_SortMode> onChanged;

  static String label(_SortMode m) => switch (m) {
        _SortMode.recommended => 'Recommended',
        _SortMode.rating => 'Top rated',
        _SortMode.popular => 'Most popular',
        _SortMode.eta => 'Fastest delivery',
        _SortMode.newest => 'Newest',
        _SortMode.priceAsc => 'Price: low to high',
        _SortMode.priceDesc => 'Price: high to low',
        _SortMode.az => 'Name A–Z',
        _SortMode.za => 'Name Z–A',
        _SortMode.openFirst => 'Open first',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_SortMode>(
          value: value,
          isDense: true,
          borderRadius: BorderRadius.circular(AppRadius.md),
          icon: const Icon(Icons.swap_vert_rounded, size: 18),
          style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AppColors.textPrimary),
          items: [
            for (final m in options)
              DropdownMenuItem(value: m, child: Text(label(m))),
          ],
          onChanged: (m) => m == null ? null : onChanged(m),
        ),
      ),
    );
  }
}
