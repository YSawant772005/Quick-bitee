import 'package:flutter/material.dart';

import '../models/models.dart';
import 'catalog_meta.dart';
import 'theme.dart';
import 'widgets.dart';

/// Restaurant cover card used on home and explore.
class RestaurantCard extends StatelessWidget {
  const RestaurantCard(
      {super.key, required this.restaurant, required this.onTap, this.width});

  final Restaurant restaurant;
  final VoidCallback onTap;
  final double? width;

  @override
  Widget build(BuildContext context) {
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
              ],
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
  final double? width;
  final double imageAspect;

  @override
  Widget build(BuildContext context) {
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
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
