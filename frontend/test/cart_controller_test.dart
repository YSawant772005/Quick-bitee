import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickbite/models/models.dart';
import 'package:quickbite/shared/widgets.dart';
import 'package:quickbite/state/cart_controller.dart';

MenuItem item(String id, String restaurantId, int price) => MenuItem(
      id: id,
      restaurantId: restaurantId,
      name: 'Item $id',
      description: '',
      priceMinor: price,
      currency: 'INR',
      imageUrl: '',
      available: true,
    );

void main() {
  group('CartController', () {
    test('add accumulates quantity and totals in minor units', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final cart = container.read(cartProvider.notifier);

      cart.add(item('a', 'r1', 25000));
      cart.add(item('a', 'r1', 25000));
      cart.add(item('b', 'r1', 5000), quantity: 2);

      final state = container.read(cartProvider);
      expect(state.totalQuantity, 4);
      expect(state.subtotalMinor, 25000 * 2 + 5000 * 2);
      expect(state.restaurantId, 'r1');
    });

    test('mixing restaurants throws CartRestaurantMismatch', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final cart = container.read(cartProvider.notifier);

      cart.add(item('a', 'r1', 100));
      expect(() => cart.add(item('b', 'r2', 100)), throwsA(isA<CartRestaurantMismatch>()));
    });

    test('setQuantity to zero removes the line', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final cart = container.read(cartProvider.notifier);

      cart.add(item('a', 'r1', 100));
      cart.setQuantity('a', 0);
      expect(container.read(cartProvider).isEmpty, isTrue);
    });

    test('replaceRestaurant swaps the cart contents', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final cart = container.read(cartProvider.notifier);

      cart.add(item('a', 'r1', 100));
      cart.replaceRestaurant(item('x', 'r2', 200), quantity: 3);
      final state = container.read(cartProvider);
      expect(state.restaurantId, 'r2');
      expect(state.totalQuantity, 3);
      expect(state.subtotalMinor, 600);
    });
  });

  group('formatMinor', () {
    test('formats INR paise with rupee symbol', () {
      expect(formatMinor(65000), '₹650');
      expect(formatMinor(505), '₹5.05');
    });
  });
}
