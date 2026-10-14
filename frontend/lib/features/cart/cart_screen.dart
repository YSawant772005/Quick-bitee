import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets.dart';
import '../../state/cart_controller.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Your cart')),
      body: cart.isEmpty
          ? EmptyState(
              icon: Icons.remove_shopping_cart_outlined,
              title: 'Your cart is empty',
              subtitle: 'Browse restaurants and add something tasty.',
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final line in cart.items.values)
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      title: Text(line.name),
                      subtitle: Text(formatMinor(line.unitPriceMinor)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          QtyStepper(
                            quantity: line.quantity,
                            compact: true,
                            onChanged: (q) => notifier.setQuantity(line.menuItemId, q),
                          ),
                          IconButton(
                            tooltip: 'Remove item',
                            icon: const Icon(Icons.delete_outline, color: Color(0xFFB91C1C)),
                            onPressed: () => notifier.remove(line.menuItemId),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Subtotal (estimated)',
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(formatMinor(cart.subtotalMinor),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'The final total is calculated and confirmed by the server at checkout.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF7C2D12)),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => context.push('/checkout'),
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: const Text('Proceed to checkout'),
                ),
              ],
            ),
    );
  }
}
