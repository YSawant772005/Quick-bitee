import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../state/cart_controller.dart';
import 'cart_actions.dart';
import 'catalog_meta.dart';
import 'layout.dart';
import 'theme.dart';
import 'widgets.dart';

/// Small veg / non-veg marker (the familiar Indian square-with-a-dot). Renders
/// nothing when the dish carries no diet tag — the app never guesses.
class VegMarker extends StatelessWidget {
  const VegMarker({super.key, required this.isVeg, this.size = 14});

  final bool? isVeg;
  final double size;

  @override
  Widget build(BuildContext context) {
    final veg = isVeg;
    if (veg == null) return const SizedBox.shrink();
    final color = veg ? AppColors.success : AppColors.error;
    return Semantics(
      label: veg ? 'Vegetarian' : 'Non-vegetarian',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 1.6),
          borderRadius: BorderRadius.circular(3),
        ),
        alignment: Alignment.center,
        child: Container(
          width: size * 0.42,
          height: size * 0.42,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

/// Star rating shown only when genuine review data exists.
class RatingPill extends StatelessWidget {
  const RatingPill({super.key, required this.rating, this.reviewCount});

  final String rating;
  final int? reviewCount;

  @override
  Widget build(BuildContext context) {
    final reviews = reviewCount ?? 0;
    return Pill(
      label: reviews > 0 ? '$rating · $reviews' : rating,
      icon: Icons.star_rounded,
      color: AppColors.forestDeep,
      background: AppColors.lime,
      dense: true,
    );
  }
}

/// Restaurant cover card used on home and explore.
class RestaurantCard extends StatelessWidget {
  const RestaurantCard(
      {super.key, required this.restaurant, required this.onTap, this.width});

  final Restaurant restaurant;
  final VoidCallback onTap;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final eta = restaurant.etaLabel;
    return AppCard(
      padding: EdgeInsets.zero,
      clip: true,
      width: width,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              AppImage(
                url: restaurant.imageUrl,
                aspectRatio: 16 / 9,
                fallbackIcon: cuisineIcon(restaurant.cuisine),
              ),
              Positioned(
                left: AppSpacing.md,
                top: AppSpacing.md,
                child: Pill(
                  label: restaurant.cuisine,
                  icon: cuisineIcon(restaurant.cuisine),
                  color: AppColors.forestDeep,
                  background: AppColors.white.withValues(alpha: 0.92),
                  dense: true,
                ),
              ),
              if (restaurant.hasRating)
                Positioned(
                  right: AppSpacing.md,
                  top: AppSpacing.md,
                  child: RatingPill(
                    rating: restaurant.ratingLabel!,
                    reviewCount: restaurant.reviewCount,
                  ),
                ),
              if (!restaurant.available)
                Positioned(
                  left: AppSpacing.md,
                  bottom: AppSpacing.md,
                  child: Pill(
                    label: 'Closed',
                    color: AppColors.error,
                    background: AppColors.white.withValues(alpha: 0.94),
                    dense: true,
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  restaurant.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  restaurant.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (restaurant.categories.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final label in restaurant.categories.take(3))
                        Pill(
                          label: label,
                          color: AppColors.forest,
                          background: AppColors.limeSoft,
                          dense: true,
                        ),
                    ],
                  ),
                ],
                if (restaurant.offers.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _OfferBadge(title: restaurant.offers.first),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Icon(Icons.storefront_outlined,
                        size: 15, color: AppColors.textMuted),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        restaurant.available
                            ? 'Open for orders'
                            : 'Currently closed',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: restaurant.available
                              ? AppColors.success
                              : AppColors.error,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      'View menu',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.forest,
                      ),
                    ),
                    const Icon(Icons.arrow_forward_rounded,
                        size: 15, color: AppColors.forest),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: 4,
                  children: [
                    if (eta != null)
                      _MetaRow(
                          icon: Icons.schedule_rounded, label: eta),
                    if (restaurant.dishCount > 0)
                      _MetaRow(
                          icon: Icons.restaurant_menu,
                          label: '${restaurant.dishCount} dishes'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}

/// "Demo offer" chip. Every restaurant-level offer the API returns is a
/// development-only demo (production serves none), so it is labelled as such
/// and never implies a discount checkout will not apply.
class _OfferBadge extends StatelessWidget {
  const _OfferBadge({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Demo promotion — no discount is applied at checkout.',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Pill(
            label: 'Demo offer',
            icon: Icons.local_offer_outlined,
            color: AppColors.warning,
            dense: true,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A food/dish card with price, availability and immediate add-to-cart control.
class DishCard extends StatelessWidget {
  const DishCard({
    super.key,
    required this.name,
    required this.description,
    required this.priceMinor,
    required this.currency,
    required this.imageUrl,
    required this.available,
    required this.quantity,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
    this.restaurantName,
    this.orderCount,
    this.isVeg,
    this.tags = const [],
    this.width,
    this.imageAspect = 4 / 3,
  });

  final String name;
  final String description;
  final int priceMinor;
  final String currency;
  final String imageUrl;
  final bool available;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final String? restaurantName;
  final int? orderCount;

  /// Diet indicator; null means "unknown", never guessed.
  final bool? isVeg;

  /// Category labels (menu sections + global tags).
  final List<CategoryTag> tags;
  final double? width;
  final double imageAspect;

  List<CategoryTag> get _chips {
    final seen = <String>{};
    final out = <CategoryTag>[];
    for (final t in tags) {
      final slug = t.slug.toLowerCase();
      if (slug == 'vegetarian' || slug == 'non-vegetarian') continue;
      if (t.name.trim().isEmpty) continue;
      if (!seen.add(t.name)) continue;
      out.add(t);
      if (out.length == 2) break;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final chips = _chips;
    return AppCard(
      padding: EdgeInsets.zero,
      clip: true,
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              AppImage(url: imageUrl, aspectRatio: imageAspect),
              if (!available)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.42),
                    alignment: Alignment.center,
                    child: const Pill(
                      label: 'Unavailable',
                      color: AppColors.white,
                      background: Colors.black54,
                    ),
                  ),
                ),
              if (orderCount != null && orderCount! > 0)
                Positioned(
                  top: AppSpacing.md,
                  left: AppSpacing.md,
                  child: Pill(
                    label: '$orderCount ordered',
                    icon: Icons.local_fire_department_rounded,
                    color: AppColors.forestDeep,
                    background: AppColors.lime,
                    dense: true,
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (restaurantName != null && restaurantName!.isNotEmpty) ...[
                  Text(
                    restaurantName!.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isVeg != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 4, right: 6),
                        child: VegMarker(isVeg: isVeg),
                      ),
                    ],
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in chips)
                        Pill(
                          label: t.name,
                          color: AppColors.forest,
                          background: AppColors.creamDeep,
                          dense: true,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    PriceText(minor: priceMinor, currency: currency, size: 17),
                    const Spacer(),
                    if (!available)
                      const Text('Unavailable',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.error,
                              fontWeight: FontWeight.w700))
                    else if (quantity == 0)
                      _AddButton(onTap: onAdd)
                    else
                      QtyStepper(
                          quantity: quantity,
                          compact: true,
                          onChanged: (q) =>
                              q > quantity ? onIncrement() : onDecrement()),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Display data for a dish card, bridging menu items and dish-first results.
class DishCardData {
  const DishCardData({required this.menuItem, this.restaurantName});

  final MenuItem menuItem;
  final String? restaurantName;

  factory DishCardData.fromMenuItem(MenuItem item, {String? restaurantName}) =>
      DishCardData(menuItem: item, restaurantName: restaurantName);

  factory DishCardData.fromDish(Dish dish) =>
      DishCardData(menuItem: dish.asMenuItem(), restaurantName: dish.restaurantName);

  String get id => menuItem.id;
  String get name => menuItem.name;
  String get description => menuItem.description;
  int get priceMinor => menuItem.priceMinor;
  String get currency => menuItem.currency;
  String get imageUrl => menuItem.imageUrl;
  bool get available => menuItem.available;
  bool? get isVeg => menuItem.isVeg;
  List<CategoryTag> get tags => menuItem.tags;
  int get orderCount => menuItem.orderCount;
}

/// A responsive grid of dish cards wired to the cart. Shared by home, explore
/// and the restaurant detail page so add-to-cart behaves identically.
class DishGrid extends ConsumerWidget {
  const DishGrid({
    super.key,
    required this.dishes,
    this.minItemWidth = 260,
    this.emptyIcon = Icons.ramen_dining_outlined,
    this.emptyTitle = 'No dishes to show',
    this.emptySubtitle,
    this.emptyAction,
  });

  final List<DishCardData> dishes;
  final double minItemWidth;
  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptySubtitle;
  final Widget? emptyAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (dishes.isEmpty) {
      return AppCard(
        child: EmptyState(
          icon: emptyIcon,
          title: emptyTitle,
          subtitle: emptySubtitle,
          action: emptyAction,
        ),
      );
    }
    final cart = ref.watch(cartProvider);
    return ResponsiveWrap(
      minItemWidth: minItemWidth,
      children: [
        for (final dish in dishes)
          Builder(builder: (context) {
            final line = cart.items[dish.id];
            final qty = line?.quantity ?? 0;
            return DishCard(
              name: dish.name,
              description: dish.description,
              priceMinor: dish.priceMinor,
              currency: dish.currency,
              imageUrl: dish.imageUrl,
              available: dish.available,
              orderCount: dish.orderCount,
              restaurantName: dish.restaurantName,
              isVeg: dish.isVeg,
              tags: dish.tags,
              quantity: qty,
              onAdd: () => addItemToCart(context, ref, dish.menuItem),
              onIncrement: () =>
                  ref.read(cartProvider.notifier).setQuantity(dish.id, qty + 1),
              onDecrement: () => ref
                  .read(cartProvider.notifier)
                  .setQuantity(dish.id, (qty <= 1 ? 1 : qty) - 1),
            );
          }),
      ],
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.forest,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 18, color: AppColors.lime),
              SizedBox(width: 4),
              Text('Add',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5)),
            ],
          ),
        ),
      ),
    );
  }
}
