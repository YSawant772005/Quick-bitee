import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../shared/cards.dart';
import '../../shared/cart_actions.dart';
import '../../shared/catalog_meta.dart';
import '../../shared/layout.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../../state/auth_controller.dart';
import '../../state/cart_controller.dart';

class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key, required this.restaurantId});

  final String restaurantId;

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  final _menuSearch = TextEditingController();
  Restaurant? _restaurant;
  List<MenuItem> _menu = const [];
  bool _loading = true;
  String? _error;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _menuSearch.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ref.read(apiClientProvider);
    try {
      final restaurants = await api.allRestaurants();
      final restaurant = restaurants.items
          .where((r) => r.id == widget.restaurantId)
          .firstOrNull;
      final menu = await api.allMenu(widget.restaurantId);
      if (!mounted) return;
      setState(() {
        _restaurant = restaurant;
        _menu = menu.items;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Network error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<MenuItem> get _visibleMenu {
    if (_filter.trim().isEmpty) return _menu;
    final q = _filter.toLowerCase();
    return _menu
        .where((i) =>
            i.name.toLowerCase().contains(q) ||
            i.description.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
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
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                    children: [
                      ContentWidth(
                        maxWidth: 1100,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: AppSpacing.lg),
                            _RestaurantHeader(restaurant: _restaurant),
                            const SizedBox(height: AppSpacing.lg),
                            TextField(
                              controller: _menuSearch,
                              onChanged: (v) => setState(() => _filter = v),
                              decoration: InputDecoration(
                                hintText: 'Search this menu…',
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: _filter.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Clear',
                                        icon: const Icon(Icons.close_rounded),
                                        onPressed: () {
                                          _menuSearch.clear();
                                          setState(() => _filter = '');
                                        },
                                      ),
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.pill),
                                  borderSide:
                                      const BorderSide(color: AppColors.border),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.pill),
                                  borderSide:
                                      const BorderSide(color: AppColors.border),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.pill),
                                  borderSide: const BorderSide(
                                      color: AppColors.forest, width: 1.8),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            SectionHeader(
                              title: 'Menu',
                              subtitle:
                                  '${_visibleMenu.length} dish${_visibleMenu.length == 1 ? '' : 'es'}',
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
                            else if (_visibleMenu.isEmpty)
                              AppCard(
                                child: EmptyState(
                                  icon: Icons.search_off_rounded,
                                  title: 'No dishes match',
                                  subtitle:
                                      'Nothing matched “$_filter”. Try another search.',
                                  action: FilledButton(
                                    onPressed: () {
                                      _menuSearch.clear();
                                      setState(() => _filter = '');
                                    },
                                    child: const Text('Clear search'),
                                  ),
                                ),
                              )
                            else
                              ResponsiveWrap(
                                minItemWidth: 300,
                                children: [
                                  for (final item in _visibleMenu)
                                    Builder(builder: (context) {
                                      final line = cart.items[item.id];
                                      return DishCard(
                                        name: item.name,
                                        description: item.description,
                                        priceMinor: item.priceMinor,
                                        currency: item.currency,
                                        imageUrl: item.imageUrl,
                                        available: item.available,
                                        quantity: line?.quantity ?? 0,
                                        onAdd: () =>
                                            addItemToCart(context, ref, item),
                                        onIncrement: () => ref
                                            .read(cartProvider.notifier)
                                            .setQuantity(item.id,
                                                (line?.quantity ?? 0) + 1),
                                        onDecrement: () => ref
                                            .read(cartProvider.notifier)
                                            .setQuantity(item.id,
                                                (line?.quantity ?? 1) - 1),
                                      );
                                    }),
                                ],
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
          ? SizedBox(
              height: 260,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 420,
                    child: AppImage(
                        url: r.imageUrl, fallbackIcon: cuisineIcon(r.cuisine)),
                  ),
                  Expanded(child: _HeaderInfo(restaurant: r)),
                ],
              ),
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
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Pill(
                label: restaurant.cuisine,
                icon: cuisineIcon(restaurant.cuisine),
                color: AppColors.forest,
                background: AppColors.limeSoft,
              ),
              const SizedBox(width: AppSpacing.sm),
              Pill(
                label: restaurant.available ? 'Open' : 'Closed',
                color:
                    restaurant.available ? AppColors.success : AppColors.error,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(restaurant.name,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          Text(restaurant.description,
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              const Icon(Icons.storefront_outlined,
                  size: 16, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
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
              ),
            ],
          ),
        ],
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
              const SkeletonBox(height: 240, radius: AppRadius.lg),
              const SizedBox(height: AppSpacing.lg),
              const SkeletonBox(height: 52, radius: AppRadius.pill),
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
