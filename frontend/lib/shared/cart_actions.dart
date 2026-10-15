import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../state/cart_controller.dart';
import 'widgets.dart';

/// Adds an item to the cart with immediate, visible feedback and safe handling
/// of the single-restaurant cart rule. Shared by home, explore and menu so the
/// interaction behaves identically everywhere.
Future<bool> addItemToCart(
  BuildContext context,
  WidgetRef ref,
  MenuItem item, {
  bool notify = true,
}) async {
  final cart = ref.read(cartProvider.notifier);
  try {
    cart.add(item);
  } on CartRestaurantMismatch {
    final replace = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start a new cart?'),
        content: Text(
          'Your cart has items from another restaurant. Replace them with ${item.name}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep current cart'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start new cart'),
          ),
        ],
      ),
    );
    if (replace != true) return false;
    cart.replaceRestaurant(item);
    if (notify && context.mounted) {
      showAppSnack(context, '${item.name} added — started a new cart');
    }
    return true;
  }
  if (notify && context.mounted) {
    showAppSnack(context, '${item.name} added to cart');
  }
  return true;
}
