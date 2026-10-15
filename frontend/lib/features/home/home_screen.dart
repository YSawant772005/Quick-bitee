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

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  List<Restaurant> _restaurants = const [];
  List<Dish> _popularDishes = const [];
  bool _loading = true;
  bool _dishesLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
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
      if (!mounted) return;
      setState(() {
        _restaurants = restaurants.items;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _error = 'Network error');
      if (mounted) setState(() => _loading = false);
    }
    await _loadDishes();
  }

  Future<void> _loadDishes() async {
    setState(() => _dishesLoading = true);
    try {
      final dishes = await ref
          .read(apiClientProvider)
          .dishes(pageSize: 8, sort: 'popular');
      if (mounted) setState(() => _popularDishes = dishes.items);
    } catch (_) {
      // Non-fatal: the rest of the home page still renders.
      if (mounted) setState(() => _popularDishes = const []);
    } finally {
      if (mounted) setState(() => _dishesLoading = false);
    }
  }

  void _search() {
    final q = _searchController.text.trim();
    context.go(q.isEmpty ? '/explore' : '/explore?q=${Uri.encodeComponent(q)}');
  }

  List<String> get _cuisines {
    final seen = <String>{};
    for (final r in _restaurants) {
      if (r.cuisine.trim().isNotEmpty) seen.add(r.cuisine);
    }
    return seen.toList();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    return CustomerShell(
      navIndex: 0,
      title: 'QuickBitee',
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _Hero(
                searchController: _searchController,
                onSearch: _search,
                onExplore: () => context.go('/explore')),
            const SizedBox(height: AppSpacing.xxl),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: ErrorState(message: _error!, onRetry: _load),
              )
            else ...[
              ContentWidth(
                  child: _Categories(cuisines: _cuisines, loading: _loading)),
              const SizedBox(height: AppSpacing.xxl),
              ContentWidth(
                child: Column(
                  children: [
                    SectionHeader(
                      title: 'Popular right now',
                      subtitle: 'Dishes customers are ordering the most',
                      onSeeAll: () => context.go('/explore'),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _DishGrid(dishes: _popularDishes, loading: _dishesLoading),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              ContentWidth(
                child: Column(
                  children: [
                    SectionHeader(
                      title: 'Restaurants near you',
                      subtitle: '${_restaurants.length} places ready to cook',
                      onSeeAll: () => context.go('/explore'),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_loading)
                      ResponsiveWrap(
                        children: List.generate(
                            3, (_) => const SkeletonCard(imageHeight: 168)),
                      )
                    else if (_restaurants.isEmpty)
                      const AppCard(
                        child: EmptyState(
                          icon: Icons.storefront_outlined,
                          title: 'No restaurants yet',
                          subtitle:
                              'The catalog is empty right now. Pull to refresh.',
                        ),
                      )
                    else
                      ResponsiveWrap(
                        minItemWidth: 300,
                        children: [
                          for (final r in _restaurants)
                            RestaurantCard(
                                restaurant: r,
                                onTap: () =>
                                    context.push('/restaurant/${r.id}')),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              const ContentWidth(child: _ValueStrip()),
              const SizedBox(height: AppSpacing.xxl),
            ],
            const _Footer(),
            if (cart.isEmpty)
              const SizedBox(height: AppSpacing.sm)
            else
              SizedBox(
                  height:
                      MediaQuery.sizeOf(context).width >= AppBreakpoints.desktop
                          ? 0
                          : 96),
          ],
        ),
      ),
      floatingActionButton: cart.isEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.forest,
              foregroundColor: Colors.white,
              onPressed: () => context.go('/cart'),
              icon: const Icon(Icons.shopping_bag_rounded),
              label: Text(
                  '${cart.totalQuantity} · ${formatMinor(cart.subtotalMinor)}'),
            ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero(
      {required this.searchController,
      required this.onSearch,
      required this.onExplore});

  final TextEditingController searchController;
  final VoidCallback onSearch;
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = AppBreakpoints.isDesktop(width);
    return Container(
      color: AppColors.forestDeep,
      child: Stack(
        children: [
          Positioned.fill(
            child: AppImage(
              url: '/static/catalog/rest-burger.jpg',
              fit: BoxFit.cover,
              radius: 0,
              fallbackColor: AppColors.forestDeep,
              fallbackIcon: Icons.lunch_dining,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: isDesktop ? Alignment.centerLeft : Alignment.topCenter,
                  end: isDesktop
                      ? Alignment.centerRight
                      : Alignment.bottomCenter,
                  colors: [
                    AppColors.forestDeep.withValues(alpha: 0.96),
                    AppColors.forestDeep
                        .withValues(alpha: isDesktop ? 0.72 : 0.86),
                    AppColors.forestDeep.withValues(alpha: 0.30),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          ContentWidth(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: isDesktop ? 72 : 40),
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: isDesktop ? 560 : double.infinity),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Pill(
                      label: 'Freshly cooked · Delivered to your door',
                      icon: Icons.restaurant_rounded,
                      color: AppColors.forestDeep,
                      background: AppColors.lime,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Good Food.\nBetter Mood.',
                      style:
                          Theme.of(context).textTheme.displayMedium?.copyWith(
                                color: Colors.white,
                                fontSize: isDesktop ? 54 : 40,
                              ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Discover dishes from the best kitchens around you and get them delivered fresh, fast and beautifully packed.',
                      style: TextStyle(
                        color: AppColors.onForestMuted,
                        fontSize: isDesktop ? 16 : 15,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _HeroSearch(
                        controller: searchController, onSearch: onSearch),
                    const SizedBox(height: AppSpacing.lg),
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.md,
                      children: [
                        FilledButton.icon(
                          onPressed: onExplore,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.lime,
                            foregroundColor: AppColors.forestDeep,
                            minimumSize: const Size(0, 52),
                          ),
                          icon: const Icon(Icons.explore_rounded, size: 20),
                          label: const Text('Explore food'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => context.go('/orders'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 52),
                            side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.5)),
                          ),
                          icon:
                              const Icon(Icons.receipt_long_outlined, size: 20),
                          label: const Text('Your orders'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroSearch extends StatelessWidget {
  const _HeroSearch({required this.controller, required this.onSearch});

  final TextEditingController controller;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: AppShadows.raised,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        children: [
          const SizedBox(width: AppSpacing.md),
          const Icon(Icons.search_rounded, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSearch(),
              decoration: const InputDecoration(
                hintText: 'Search biryani, pizza, burgers…',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          FilledButton(
            onPressed: onSearch,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.forest,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }
}

class _Categories extends StatelessWidget {
  const _Categories({required this.cuisines, required this.loading});

  final List<String> cuisines;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
            title: 'Browse by category',
            subtitle: 'Pick a craving and dive in'),
        const SizedBox(height: AppSpacing.lg),
        if (loading)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(
                6,
                (_) => const Padding(
                  padding: EdgeInsets.only(right: AppSpacing.md),
                  child:
                      SkeletonBox(height: 96, width: 96, radius: AppRadius.lg),
                ),
              ),
            ),
          )
        else if (cuisines.isEmpty)
          const Text('Categories appear once the catalog loads.',
              style: TextStyle(color: AppColors.textSecondary))
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final cuisine in cuisines)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.md),
                    child: _CategoryTile(
                      label: cuisine,
                      icon: cuisineIcon(cuisine),
                      onTap: () => context.go(
                          '/explore?cuisine=${Uri.encodeComponent(cuisine)}'),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.md),
                  child: _CategoryTile(
                    label: 'All',
                    icon: Icons.grid_view_rounded,
                    onTap: () => context.go('/explore'),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile(
      {required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      child: Material(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.border),
            ),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Column(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                      color: AppColors.limeSoft, shape: BoxShape.circle),
                  child: Icon(icon, color: AppColors.forest, size: 24),
                ),
                const SizedBox(height: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        height: 1.2),
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

class _DishGrid extends ConsumerWidget {
  const _DishGrid({required this.dishes, required this.loading});

  final List<Dish> dishes;
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (loading) {
      return ResponsiveWrap(
        minItemWidth: 240,
        children: List.generate(4, (_) => const SkeletonCard(imageHeight: 150)),
      );
    }
    if (dishes.isEmpty) {
      return AppCard(
        child: EmptyState(
          icon: Icons.ramen_dining_outlined,
          title: 'No popular dishes yet',
          subtitle: 'Once orders start coming in, the top dishes appear here.',
          action: FilledButton(
            onPressed: () => context.go('/explore'),
            child: const Text('Browse restaurants'),
          ),
        ),
      );
    }
    final cart = ref.watch(cartProvider);
    return ResponsiveWrap(
      minItemWidth: 240,
      children: [
        for (final dish in dishes)
          Builder(
            builder: (context) {
              final line = cart.items[dish.id];
              return DishCard(
                name: dish.name,
                description: dish.description,
                priceMinor: dish.priceMinor,
                currency: dish.currency,
                imageUrl: dish.imageUrl,
                available: dish.available,
                orderCount: dish.orderCount,
                restaurantName: dish.restaurantName,
                quantity: line?.quantity ?? 0,
                onAdd: () => addItemToCart(context, ref, dish.asMenuItem()),
                onIncrement: () => ref
                    .read(cartProvider.notifier)
                    .setQuantity(dish.id, (line?.quantity ?? 0) + 1),
                onDecrement: () => ref
                    .read(cartProvider.notifier)
                    .setQuantity(dish.id, (line?.quantity ?? 1) - 1),
              );
            },
          ),
      ],
    );
  }
}

class _ValueStrip extends StatelessWidget {
  const _ValueStrip();

  @override
  Widget build(BuildContext context) {
    const features = [
      (
        Icons.delivery_dining_rounded,
        'Live order tracking',
        'Watch every stage from kitchen to your door.'
      ),
      (
        Icons.lock_outline_rounded,
        'Secure checkout',
        'Idempotent payments — no accidental double charges.'
      ),
      (
        Icons.eco_outlined,
        'Made to order',
        'Restaurants prepare your dishes after you order.'
      ),
      (
        Icons.support_agent_rounded,
        'Real-time updates',
        'Notifications land the moment status changes.'
      ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: AppColors.forestDeep,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: ResponsiveWrap(
        minItemWidth: 220,
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.xl,
        children: [
          for (final f in features)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                      color: AppColors.lime, shape: BoxShape.circle),
                  child: Icon(f.$1, color: AppColors.forestDeep, size: 22),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f.$2,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(f.$3,
                          style: const TextStyle(
                              color: AppColors.onForestMuted,
                              fontSize: 13,
                              height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    return Container(
      color: AppColors.white,
      child: Container(
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border))),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrandLogo(size: 36),
              const SizedBox(height: AppSpacing.md),
              Text(
                'QuickBitee is a demo food-ordering platform — Flutter web & mobile, FastAPI, PostgreSQL and RabbitMQ.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xl),
              Wrap(
                spacing: AppSpacing.xxl,
                runSpacing: AppSpacing.lg,
                children: [
                  _FooterColumn(
                    title: 'Explore',
                    links: [
                      ('Home', () => context.go('/')),
                      ('Restaurants', () => context.go('/explore')),
                      ('Your cart', () => context.go('/cart')),
                    ],
                  ),
                  _FooterColumn(
                    title: 'Account',
                    links: [
                      ('Orders', () => context.go('/orders')),
                      ('Notifications', () => context.push('/notifications')),
                      ('Profile', () => context.go('/profile')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.lg),
              Text('© $year QuickBitee. Built for demonstration purposes.',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterColumn extends StatelessWidget {
  const _FooterColumn({required this.title, required this.links});

  final String title;
  final List<(String, VoidCallback)> links;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.4)),
        const SizedBox(height: AppSpacing.sm),
        for (final link in links)
          TextButton(
            onPressed: link.$2,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              alignment: Alignment.centerLeft,
            ),
            child: Text(link.$1,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }
}
