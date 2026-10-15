import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../shared/layout.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../../state/cart_controller.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    return CustomerShell(
      navIndex: 2,
      title: 'Your cart',
      body: cart.isEmpty
          ? EmptyState(
              icon: Icons.remove_shopping_cart_outlined,
              title: 'Your cart is empty',
              subtitle: 'Browse restaurants and add something tasty.',
              action: FilledButton.icon(
                onPressed: () => context.go('/explore'),
                icon: const Icon(Icons.explore_rounded, size: 19),
                label: const Text('Explore restaurants'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
              children: [
                ContentWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppSpacing.lg),
                      Text('Review your order', style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text('${cart.totalQuantity} item${cart.totalQuantity == 1 ? '' : 's'} ready for checkout',
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: AppSpacing.xl),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 860;
                          final items = _ItemsCard(cart: cart, notifier: notifier);
                          final summary = _SummaryCard(cart: cart, onClear: notifier.clear);
                          if (!isWide) {
                            return Column(
                              children: [
                                items,
                                const SizedBox(height: AppSpacing.lg),
                                summary,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: items),
                              const SizedBox(width: AppSpacing.xl),
                              SizedBox(width: 360, child: summary),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.cart, required this.notifier});

  final CartState cart;
  final CartController notifier;

  @override
  Widget build(BuildContext context) {
    final lines = cart.items.values.toList();
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            _CartLine(line: lines[i], notifier: notifier),
            if (i != lines.length - 1)
              const Divider(height: 1, indent: AppSpacing.lg, endIndent: AppSpacing.lg),
          ],
        ],
      ),
    );
  }
}

class _CartLine extends StatelessWidget {
  const _CartLine({required this.line, required this.notifier});

  final OrderLine line;
  final CartController notifier;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppImage(url: line.imageUrl, height: 64, width: 64, radius: AppRadius.md),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.name, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text('${formatMinor(line.unitPriceMinor)} each',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    QtyStepper(
                      quantity: line.quantity,
                      compact: true,
                      onChanged: (q) => notifier.setQuantity(line.menuItemId, q),
                    ),
                    const Spacer(),
                    PriceText(minor: line.lineTotalMinor, size: 15),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            tooltip: 'Remove ${line.name}',
            onPressed: () => notifier.remove(line.menuItemId),
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.cart, required this.onClear});

  final CartState cart;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order summary', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.lg),
          _row(context, 'Items (${cart.totalQuantity})', formatMinor(cart.subtotalMinor)),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: AppSpacing.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Estimated total', style: Theme.of(context).textTheme.titleMedium),
              PriceText(minor: cart.subtotalMinor, size: 20),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.limeSoft,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: AppColors.forest),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'The final amount is calculated and confirmed by the server at checkout.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.forestDeep, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.push('/checkout'),
              icon: const Icon(Icons.lock_outline_rounded, size: 19),
              label: const Text('Proceed to checkout'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: onClear,
              style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
              child: const Text('Clear cart'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ],
      );
}
