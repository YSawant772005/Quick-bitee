import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../models/models.dart';
import '../../shared/layout.dart';
import '../../shared/theme.dart';
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
    if (_submitting) return; // guard against rapid double-taps
    if (!_formKey.currentState!.validate()) return;
    final cart = ref.read(cartProvider);
    if (cart.isEmpty || cart.restaurantId == null) return;
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
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Network error. Your cart is kept — you can safely retry.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    return CustomerShell(
      navIndex: null,
      showBack: true,
      title: 'Checkout',
      body: cart.isEmpty
          ? const EmptyState(
              icon: Icons.remove_shopping_cart_outlined,
              title: 'Your cart is empty',
              subtitle: 'Add items before checking out.',
            )
          : Form(
              key: _formKey,
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                      children: [
                        ContentWidth(
                          maxWidth: 760,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: AppSpacing.lg),
                              Text('Complete your order', style: Theme.of(context).textTheme.headlineSmall),
                              const SizedBox(height: 4),
                              Text('Confirm your items, delivery address and payment.',
                                  style: Theme.of(context).textTheme.bodyMedium),
                              const SizedBox(height: AppSpacing.xl),
                              _ItemsSection(cart: cart),
                              const SizedBox(height: AppSpacing.lg),
                              _DeliverySection(address: _address),
                              const SizedBox(height: AppSpacing.lg),
                              const _PaymentSection(),
                              const SizedBox(height: AppSpacing.lg),
                              _PriceBreakdown(cart: cart),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _CheckoutBar(
                    cart: cart,
                    submitting: _submitting,
                    error: _error,
                    onSubmit: _placeOrder,
                  ),
                ],
              ),
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.icon, required this.child});

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(color: AppColors.limeSoft, shape: BoxShape.circle),
                child: Icon(icon, size: 19, color: AppColors.forest),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }
}

class _ItemsSection extends StatelessWidget {
  const _ItemsSection({required this.cart});

  final CartState cart;

  @override
  Widget build(BuildContext context) {
    final lines = cart.items.values.toList();
    return _SectionCard(
      title: 'Your items',
      icon: Icons.shopping_bag_outlined,
      child: Column(
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppImage(url: lines[i].imageUrl, height: 52, width: 52, radius: AppRadius.sm),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${lines[i].quantity} × ${lines[i].name}',
                          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(formatMinor(lines[i].unitPriceMinor),
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                PriceText(minor: lines[i].lineTotalMinor, size: 14.5),
              ],
            ),
            if (i != lines.length - 1) const SizedBox(height: AppSpacing.lg),
          ],
        ],
      ),
    );
  }
}

class _DeliverySection extends StatelessWidget {
  const _DeliverySection({required this.address});

  final TextEditingController address;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Delivery details',
      icon: Icons.location_on_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: 'Delivery address',
            child: TextFormField(
              controller: address,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                labelText: 'Delivery address',
                hintText: 'Flat, street, area, city, PIN code',
                prefixIcon: Icon(Icons.location_on_outlined),
                alignLabelWithHint: true,
              ),
              validator: (v) => (v == null || v.trim().length < 10)
                  ? 'Enter a full delivery address (at least 10 characters)'
                  : null,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'We deliver to the address above. Make sure it is complete so the driver can find you.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _PaymentSection extends StatelessWidget {
  const _PaymentSection();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Payment',
      icon: Icons.payments_outlined,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.cream,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.autorenew_rounded, color: AppColors.forest),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Simulated card payment',
                      style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  SizedBox(height: 2),
                  Text(
                    'Payment is captured automatically by the demo payment worker as soon as you place the order. You will see each stage on the tracking screen.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
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

class _PriceBreakdown extends StatelessWidget {
  const _PriceBreakdown({required this.cart});

  final CartState cart;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Price breakdown',
      icon: Icons.receipt_long_outlined,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Items (${cart.totalQuantity})', style: Theme.of(context).textTheme.bodyMedium),
              Text(formatMinor(cart.subtotalMinor),
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: AppSpacing.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total payable', style: Theme.of(context).textTheme.titleMedium),
              PriceText(minor: cart.subtotalMinor, size: 20),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Confirmed by the server when the order is accepted.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }
}

/// Always-visible checkout action bar. The total and the place-order button are
/// pinned so the primary action is never scrolled off screen.
class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({
    required this.cart,
    required this.submitting,
    required this.error,
    required this.onSubmit,
  });

  final CartState cart;
  final bool submitting;
  final String? error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: AppShadows.subtle,
      ),
      child: SafeArea(
        top: false,
        child: ContentWidth(
          maxWidth: 760,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.errorSoft,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.error),
                      const SizedBox(width: 8),
                      Expanded(child: Text(error!, style: const TextStyle(color: AppColors.error, fontSize: 13))),
                    ],
                  ),
                ),
              ],
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Total payable', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      PriceText(minor: cart.subtotalMinor, size: 20),
                    ],
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: submitting ? null : onSubmit,
                      icon: submitting
                          ? const SizedBox(
                              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_circle_outline_rounded, size: 19),
                      label: Text(submitting ? 'Placing order…' : 'Place order'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Retries reuse the same idempotency key, so a timeout never double-charges or duplicates your order.',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Order confirmation. Fetches the accepted order so the confirmed items and
/// total are real, never assumed.
class CheckoutAckScreen extends ConsumerStatefulWidget {
  const CheckoutAckScreen({super.key, required this.accepted});

  final OrderAccepted accepted;

  @override
  ConsumerState<CheckoutAckScreen> createState() => _CheckoutAckScreenState();
}

class _CheckoutAckScreenState extends ConsumerState<CheckoutAckScreen> {
  OrderDetail? _order;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final order = await ref.read(apiClientProvider).order(widget.accepted.orderId);
      if (mounted) setState(() => _order = order);
    } catch (_) {
      // Non-fatal: the confirmation still shows the order id and total.
    }
  }

  @override
  Widget build(BuildContext context) {
    final accepted = widget.accepted;
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _SuccessIllustration(),
                  const SizedBox(height: AppSpacing.xl),
                  Text('Your order is confirmed!',
                      textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'We have your order ${accepted.orderId.substring(0, 8)} and the kitchen is getting started. Track every step below.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text('Order #${accepted.orderId.substring(0, 8)}',
                                  style: Theme.of(context).textTheme.titleMedium),
                            ),
                            StatusChip(status: accepted.status),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (_order != null && _order!.items.isNotEmpty) ...[
                          for (final item in _order!.items)
                            Padding(
                              padding: const EdgeInsets.only(bottom: AppSpacing.md),
                              child: Row(
                                children: [
                                  AppImage(url: item.imageUrl, height: 48, width: 48, radius: AppRadius.sm),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: Text('${item.quantity} × ${item.name}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                  ),
                                  PriceText(minor: item.lineTotalMinor, size: 14),
                                ],
                              ),
                            ),
                          const Divider(height: AppSpacing.xl),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Total', style: Theme.of(context).textTheme.titleMedium),
                            PriceText(minor: accepted.totalMinor, currency: accepted.currency, size: 18),
                          ],
                        ),
                        if (_order != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text('Delivering to: ${_order!.deliveryAddress}',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton.icon(
                    onPressed: () => context.go('/orders/${accepted.orderId}'),
                    icon: const Icon(Icons.local_shipping_outlined, size: 20),
                    label: const Text('Track order'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/explore'),
                    icon: const Icon(Icons.explore_rounded, size: 20),
                    label: const Text('Continue exploring'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuccessIllustration extends StatelessWidget {
  const _SuccessIllustration();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 160,
        height: 160,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 160,
              height: 160,
              decoration: const BoxDecoration(color: AppColors.limeSoft, shape: BoxShape.circle),
            ),
            Container(
              width: 116,
              height: 116,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [AppColors.forestSoft, AppColors.forestDeep]),
                shape: BoxShape.circle,
                boxShadow: AppShadows.card,
              ),
              child: const Icon(Icons.delivery_dining_rounded, color: AppColors.lime, size: 56),
            ),
            Positioned(
              right: 12,
              bottom: 16,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
