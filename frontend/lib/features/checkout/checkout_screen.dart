import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../models/models.dart';
import '../../shared/widgets.dart';
import '../../state/auth_controller.dart';
import '../../state/cart_controller.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _address = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;
  String? _error;
  late final String _idempotencyKey = const Uuid().v4();

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _placeOrder() async {
    if (!_formKey.currentState!.validate()) return;
    final cart = ref.read(cartProvider);
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final accepted = await ref.read(apiClientProvider).placeOrder(
            restaurantId: cart.restaurantId!,
            deliveryAddress: _address.text.trim(),
            items: cart.items.values.toList(),
            idempotencyKey: _idempotencyKey,
          );
      ref.read(cartProvider.notifier).clear();
      if (mounted) context.go('/checkout-ack', extra: accepted);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Network error. Your cart is kept — retry with the same key.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: cart.isEmpty
          ? const EmptyState(
              icon: Icons.remove_shopping_cart_outlined,
              title: 'Your cart is empty',
              subtitle: 'Add items before checking out.',
            )
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Order summary', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final line in cart.items.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(child: Text('${line.quantity} × ${line.name}')),
                          Text(formatMinor(line.lineTotalMinor)),
                        ],
                      ),
                    ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Estimated total'),
                      Text(formatMinor(cart.subtotalMinor),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Semantics(
                    label: 'Delivery address',
                    child: TextFormField(
                      controller: _address,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Delivery address',
                        hintText: 'Flat, street, area, city, PIN',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                      validator: (v) => (v == null || v.trim().length < 10)
                          ? 'Enter a full delivery address (min 10 characters)'
                          : null,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C))),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _placeOrder,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_outlined),
                    label: Text(_submitting ? 'Placing order…' : 'Place order'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Retries use the same idempotency key, so a timeout will never double-charge or duplicate your order.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF7C2D12)),
                  ),
                ],
              ),
            ),
    );
  }
}

class CheckoutAckScreen extends StatelessWidget {
  const CheckoutAckScreen({super.key, required this.accepted});

  final OrderAccepted accepted;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.check_circle_outline, size: 72, color: Color(0xFF15803D)),
                const SizedBox(height: 12),
                Text('Order accepted!', textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Your order is being processed. Payment has not completed yet — watch its live status on the tracking screen.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _row('Order ID', accepted.orderId),
                        _row('Total', formatMinor(accepted.totalMinor, currency: accepted.currency)),
                        _row('Status', accepted.status),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => context.go('/orders/${accepted.orderId}'),
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: const Text('Track order'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => context.go('/orders'),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('View order history'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'monospace')),
            ),
          ],
        ),
      );
}
