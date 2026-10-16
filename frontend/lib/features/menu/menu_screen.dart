import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../shared/cards.dart';
import '../../shared/catalog_meta.dart';
import '../../shared/layout.dart';
import '../../shared/paged_list.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../../state/auth_controller.dart';
import '../../state/cart_controller.dart';

enum _MenuSort { recommended, name, priceAsc, priceDesc, popular }

/// One restaurant's page: the full detail header (image, address, hours, ETA,
/// rating when real data exists), any configured offers, and a menu that can be
/// searched, filtered by food type / category and sorted — all combinable, with
/// a one-tap reset and a clear "nothing matched" state.
class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key, required this.restaurantId});

  final String restaurantId;

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  final _menuSearch = TextEditingController();
  final _scroll = ScrollController();
  final _listKey = GlobalKey();
  final _footerKey = GlobalKey();
  Restaurant? _restaurant;
  List<MenuItem> _menu = const [];
  bool _loading = true;
  String? _error;

  /// Slices the (client-side filtered) menu into pages so the shared
  /// pagination controls / infinite-scroll footer can drive it.
  late final PagedListController<MenuItem> _paged;

  String _query = '';
  String _foodType = ''; // '', 'veg' or 'non_veg'
  String _category = ''; // tag slug
  _MenuSort _sort = _MenuSort.recommended;

  @override
  void initState() {
    super.initState();
    _paged = PagedListController<MenuItem>(
      idOf: (i) => i.id,
      pageSize: 24,
      local: const [],
    );
    _paged.addListener(_onPagedChanged);
    _load();
  }

  @override
  void dispose() {
    _paged.removeListener(_onPagedChanged);
    _paged.dispose();
    _menuSearch.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onPagedChanged() {
    if (!mounted) return;
    setState(() {});
    _maybeLoadMore();
  }

  /// Infinite mode: when the page footer is close to the viewport's bottom,
  /// fetch the next slice. The controller ignores duplicate calls.
  void _maybeLoadMore() {
    if (!mounted || _paged.busy || !_paged.hasMore) return;
    if (ref.read(browseModeProvider) != BrowseMode.infinite) return;
    scheduleNearBottomLoad(
      anchorKey: _footerKey,
      scrollableKey: _listKey,
      onLoadMore: _paged.loadMore,
    );
  }

  /// Re-slices after any filter/search/sort change. Page resets to 1.
  void _applyFiltersLocal(VoidCallback change) {
    setState(change);
    _paged.setLocalItems(_visibleMenu);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ref.read(apiClientProvider);

    // Prefer the dedicated detail endpoint; fall back to the listing when an
    // older backend (or a test stub) has no detail route.
    Restaurant? restaurant;
    try {
      restaurant = await api.restaurantDetail(widget.restaurantId);
    } catch (_) {
      restaurant = null;
    }
    if (restaurant == null) {
      try {
        final list = await api.allRestaurants();
        for (final r in list.items) {
          if (r.id == widget.restaurantId) {
            restaurant = r;
            break;
          }
        }
      } catch (_) {
        // Leave the header as "unavailable" rather than failing the menu.
      }
    }

    try {
      final menu = await api.allMenu(widget.restaurantId);
      if (!mounted) return;
      setState(() {
        _restaurant = restaurant;
        _menu = menu.items;
      });
      _paged.setLocalItems(_visibleMenu);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _restaurant = restaurant;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _restaurant = restaurant;
          _error = 'Network error';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _hasFilters =>
      _query.isNotEmpty ||
      _foodType.isNotEmpty ||
      _category.isNotEmpty ||
      _sort != _MenuSort.recommended;

  List<CategoryTag> get _categoryOptions {
    final seen = <String>{};
    final out = <CategoryTag>[];
    for (final item in _menu) {
      for (final tag in item.tags) {
        final slug = tag.slug.toLowerCase();
        if (slug == 'vegetarian' || slug == 'non-vegetarian') continue;
        if (tag.name.trim().isEmpty) continue;
        if (seen.add(tag.slug)) out.add(tag);
      }
    }
    return out;
  }

  List<MenuItem> get _visibleMenu {
    final q = _query.toLowerCase();
    final list = _menu.where((i) {
      if (_foodType == 'veg' && i.isVeg != true) return false;
      if (_foodType == 'non_veg' && i.isVeg != false) return false;
      if (_category.isNotEmpty &&
          !i.tags.any((t) => t.slug == _category)) {
        return false;
      }
      if (q.isNotEmpty &&
          !i.name.toLowerCase().contains(q) &&
          !i.description.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();

    switch (_sort) {
      case _MenuSort.name:
        list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case _MenuSort.priceAsc:
        list.sort((a, b) => a.priceMinor.compareTo(b.priceMinor));
      case _MenuSort.priceDesc:
        list.sort((a, b) => b.priceMinor.compareTo(a.priceMinor));
      case _MenuSort.popular:
        list.sort((a, b) => b.orderCount.compareTo(a.orderCount));
      case _MenuSort.recommended:
        break;
    }
    return list;
  }

  void _reset() {
    _menuSearch.clear();
    _applyFiltersLocal(() {
      _query = '';
      _foodType = '';
      _category = '';
      _sort = _MenuSort.recommended;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final browseMode = ref.watch(browseModeProvider);
    // Re-slice when the user switches mode so infinite-scroll accumulation and
    // numbered pages stay consistent with each other.
    ref.listen(browseModeProvider, (_, __) {
      if (_menu.isNotEmpty) _paged.setLocalItems(_visibleMenu);
    });
    final title = _restaurant?.name ?? 'Menu';
    return CustomerShell(
      navIndex: null,
      showBack: true,
      title: title,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: IconButton(
            tooltip: 'Cart',
            onPressed: () => context.go('/cart'),
            icon: Badge(
              isLabelVisible: cart.totalQuantity > 0,
              label: Text('${cart.totalQuantity}'),
              backgroundColor: AppColors.forest,
              child: const Icon(Icons.shopping_bag_outlined),
            ),
          ),
        ),
      ],
      body: _loading
          ? const _MenuSkeleton()
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification is ScrollEndNotification) {
                        _maybeLoadMore();
                      }
                      return false;
                    },
                    child: ListView(
                      key: _listKey,
                      controller: _scroll,
                      padding:
                          const EdgeInsets.only(bottom: AppSpacing.xxl),
                      children: [
                      ContentWidth(
                        maxWidth: 1100,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: AppSpacing.lg),
                            _RestaurantHeader(restaurant: _restaurant),
                            if (_restaurant != null &&
                                _restaurant!.offers.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.lg),
                              _OffersCard(offers: _restaurant!.offers),
                            ],
                            const SizedBox(height: AppSpacing.lg),
                            _FilterBar(
                              searchController: _menuSearch,
                              foodType: _foodType,
                              category: _category,
                              sort: _sort,
                              categoryOptions: _categoryOptions,
                              hasFilters: _hasFilters,
                              onQueryChanged: (v) =>
                                  _applyFiltersLocal(() => _query = v.trim()),
                              onSearchCleared: () {
                                _menuSearch.clear();
                                _applyFiltersLocal(() => _query = '');
                              },
                              onFoodType: (v) =>
                                  _applyFiltersLocal(() => _foodType = v),
                              onCategory: (v) =>
                                  _applyFiltersLocal(() => _category = v),
                              onSort: (v) =>
                                  _applyFiltersLocal(() => _sort = v),
                              onReset: _reset,
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: _MenuHeading(
                                    visible: _paged.total,
                                    total: _menu.length,
                                  ),
                                ),
                                const BrowseModeToggle(compact: true),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            if (_menu.isEmpty)
                              const AppCard(
                                child: EmptyState(
                                  icon: Icons.restaurant_menu,
                                  title: 'No menu items yet',
                                  subtitle:
                                      'This restaurant has not published a menu.',
                                ),
                              )
                            else if (_paged.isEmpty)
                              AppCard(
                                child: EmptyState(
                                  icon: Icons.search_off_rounded,
                                  title: 'No dishes match your filters',
                                  subtitle:
                                      'Nothing on this menu matched. Try clearing '
                                      'a filter or searching for something else.',
                                  action: FilledButton(
                                    onPressed: _reset,
                                    child: const Text('Reset filters'),
                                  ),
                                ),
                              )
                            else ...[
                              DishGrid(
                                minItemWidth: 300,
                                dishes: [
                                  for (final item in _paged.items)
                                    DishCardData.fromMenuItem(item,
                                        restaurantName: _restaurant?.name),
                                ],
                              ),
                              KeyedSubtree(
                                key: _footerKey,
                                child: PagedResultsFooter(
                                  controller: _paged,
                                  mode: browseMode,
                                  endLabel: "That's the whole menu",
                                  onPageChanged: (page) {
                                    _paged.goToPage(page);
                                    if (_scroll.hasClients) {
                                      _scroll.animateTo(
                                        0,
                                        duration:
                                            const Duration(milliseconds: 220),
                                        curve: Curves.easeOut,
                                      );
                                    }
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    ),
                  ),
                ),
    );
  }
}

/// Menu heading with an item count. Counts are worded as "items" so a raw total
/// can never read as a food-quantity claim.
class _MenuHeading extends StatelessWidget {
  const _MenuHeading({required this.visible, required this.total});

  final int visible;
  final int total;

  @override
  Widget build(BuildContext context) {
    final filtered = visible != total;
    return SectionHeader(
      title: 'Menu',
      subtitle: filtered
          ? 'Showing $visible of $total items'
          : '$total items',
    );
  }
}

class _RestaurantHeader extends StatelessWidget {
  const _RestaurantHeader({required this.restaurant});

  final Restaurant? restaurant;

  @override
  Widget build(BuildContext context) {
    if (restaurant == null) {
      return const AppCard(
          child: Text('Restaurant details unavailable.',
              style: TextStyle(color: AppColors.textSecondary)));
    }
    final r = restaurant!;
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = AppBreakpoints.isDesktop(width);
    return AppCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: isDesktop
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 420,
                  child: AppImage(
                      url: r.imageUrl,
                      aspectRatio: 4 / 3,
                      fallbackIcon: cuisineIcon(r.cuisine)),
                ),
                Expanded(child: _HeaderInfo(restaurant: r)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppImage(
                    url: r.imageUrl,
                    aspectRatio: 16 / 9,
                    fallbackIcon: cuisineIcon(r.cuisine)),
                _HeaderInfo(restaurant: r),
              ],
            ),
    );
  }
}

class _HeaderInfo extends StatelessWidget {
  const _HeaderInfo({required this.restaurant});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context) {
    final eta = restaurant.etaLabel;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Pill(
                label: restaurant.cuisine,
                icon: cuisineIcon(restaurant.cuisine),
                color: AppColors.forest,
                background: AppColors.limeSoft,
              ),
              Pill(
                label: restaurant.available ? 'Open' : 'Closed',
                color:
                    restaurant.available ? AppColors.success : AppColors.error,
              ),
              if (restaurant.hasRating)
                Pill(
                  label: restaurant.reviewCount != null
                      ? '${restaurant.ratingLabel} · ${restaurant.reviewCount} reviews'
                      : restaurant.ratingLabel!,
                  icon: Icons.star_rounded,
                  color: AppColors.forestDeep,
                  background: AppColors.lime,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(restaurant.name,
              style: Theme.of(context).textTheme.headlineSmall),
          if (restaurant.description.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(restaurant.description,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _Fact(
                icon: Icons.schedule_rounded,
                label: eta ?? 'Delivery time varies',
              ),
              if (restaurant.address.isNotEmpty)
                _Fact(
                    icon: Icons.location_on_outlined,
                    label: restaurant.address),
              if (restaurant.openingHours.isNotEmpty)
                _Fact(
                    icon: Icons.access_time_rounded,
                    label: restaurant.openingHours),
              if (restaurant.dishCount > 0)
                _Fact(
                    icon: Icons.restaurant_menu,
                    label: '${restaurant.dishCount} menu items'),
            ],
          ),
          if (restaurant.categories.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in restaurant.categories)
                  Pill(
                    label: c,
                    color: AppColors.forest,
                    background: AppColors.creamDeep,
                    dense: true,
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Icon(
                restaurant.available
                    ? Icons.check_circle_rounded
                    : Icons.pause_circle_outline_rounded,
                size: 16,
                color: restaurant.available
                    ? AppColors.success
                    : AppColors.error,
              ),
              const SizedBox(width: 6),
              Text(
                restaurant.available
                    ? 'Accepting orders now'
                    : 'Currently not accepting orders',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: restaurant.available
                      ? AppColors.success
                      : AppColors.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _OffersCard extends StatelessWidget {
  const _OffersCard({required this.offers});

  final List<String> offers;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_offer_outlined,
                  size: 18, color: AppColors.warning),
              const SizedBox(width: 8),
              Text('Offers on this restaurant',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton(
                onPressed: () => context.push('/offers'),
                child: const Text('See all offers'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final title in offers)
                Pill(
                  label: title,
                  icon: Icons.local_offer_outlined,
                  color: AppColors.forestDeep,
                  background: AppColors.limeSoft,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 14, color: AppColors.textMuted),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Demo promotions — they link to real pages and apply no '
                  'discount at checkout.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.searchController,
    required this.foodType,
    required this.category,
    required this.sort,
    required this.categoryOptions,
    required this.hasFilters,
    required this.onQueryChanged,
    required this.onSearchCleared,
    required this.onFoodType,
    required this.onCategory,
    required this.onSort,
    required this.onReset,
  });

  final TextEditingController searchController;
  final String foodType;
  final String category;
  final _MenuSort sort;
  final List<CategoryTag> categoryOptions;
  final bool hasFilters;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onSearchCleared;
  final ValueChanged<String> onFoodType;
  final ValueChanged<String> onCategory;
  final ValueChanged<_MenuSort> onSort;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: searchController,
            onChanged: onQueryChanged,
            decoration: InputDecoration(
              hintText: 'Search this menu…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: onSearchCleared,
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
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _ChoiceChip(
                label: 'All',
                selected: foodType.isEmpty,
                onTap: () => onFoodType(''),
              ),
              _ChoiceChip(
                label: 'Veg',
                icon: Icons.eco_outlined,
                selected: foodType == 'veg',
                onTap: () => onFoodType('veg'),
              ),
              _ChoiceChip(
                label: 'Non-veg',
                icon: Icons.set_meal_outlined,
                selected: foodType == 'non_veg',
                onTap: () => onFoodType('non_veg'),
              ),
              _SortDropdown(value: sort, onChanged: onSort),
              if (hasFilters)
                TextButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text('Reset'),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.error),
                ),
            ],
          ),
          if (categoryOptions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            HorizontalChipScroller(
              semanticLabel: 'Filter by menu category',
              child: Row(
                children: [
                  _ChoiceChip(
                    label: 'All categories',
                    selected: category.isEmpty,
                    onTap: () => onCategory(''),
                  ),
                  for (final tag in categoryOptions)
                    Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.sm),
                      child: _ChoiceChip(
                        label: tag.name,
                        selected: category == tag.slug,
                        onTap: () => onCategory(tag.slug),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip(
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
    return Material(
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
                    color: selected ? AppColors.lime : AppColors.textSecondary),
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
    );
  }
}

class _SortDropdown extends StatelessWidget {
  const _SortDropdown({required this.value, required this.onChanged});

  final _MenuSort value;
  final ValueChanged<_MenuSort> onChanged;

  static String _label(_MenuSort m) => switch (m) {
        _MenuSort.recommended => 'Recommended',
        _MenuSort.name => 'Name A–Z',
        _MenuSort.priceAsc => 'Price: low to high',
        _MenuSort.priceDesc => 'Price: high to low',
        _MenuSort.popular => 'Most popular',
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
        child: DropdownButton<_MenuSort>(
          value: value,
          isDense: true,
          borderRadius: BorderRadius.circular(AppRadius.md),
          icon: const Icon(Icons.swap_vert_rounded, size: 18),
          style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AppColors.textPrimary),
          items: [
            for (final m in _MenuSort.values)
              DropdownMenuItem(value: m, child: Text(_label(m))),
          ],
          onChanged: (m) => m == null ? null : onChanged(m),
        ),
      ),
    );
  }
}

class _MenuSkeleton extends StatelessWidget {
  const _MenuSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      children: [
        ContentWidth(
          maxWidth: 1100,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.lg),
              const SkeletonBox(height: 260, radius: AppRadius.lg),
              const SizedBox(height: AppSpacing.lg),
              const SkeletonBox(height: 132, radius: AppRadius.lg),
              const SizedBox(height: AppSpacing.xl),
              ResponsiveWrap(
                minItemWidth: 300,
                children: List.generate(
                    6, (_) => const SkeletonCard(imageHeight: 160)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
