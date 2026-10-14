import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';

class CartState {
  const CartState({this.restaurantId, this.restaurantName = '', this.items = const {}});

  final String? restaurantId;
  final String restaurantName;
  final Map<String, OrderLine> items;

  int get totalQuantity => items.values.fold(0, (sum, l) => sum + l.quantity);
  int get subtotalMinor => items.values.fold(0, (sum, l) => sum + l.lineTotalMinor);
  bool get isEmpty => items.isEmpty;

  CartState copyWith({String? restaurantId, String? restaurantName, Map<String, OrderLine>? items}) => CartState(
        restaurantId: restaurantId ?? this.restaurantId,
        restaurantName: restaurantName ?? this.restaurantName,
        items: items ?? this.items,
      );
}

class CartController extends Notifier<CartState> {
  @override
  CartState build() => const CartState();

  void add(MenuItem item, {int quantity = 1}) {
    final current = state;
    if (current.restaurantId != null && current.restaurantId != item.restaurantId) {
      throw CartRestaurantMismatch();
    }
    final existing = current.items[item.id];
    final merged = {
      ...current.items,
      item.id: OrderLine(
        menuItemId: item.id,
        name: item.name,
        unitPriceMinor: item.priceMinor,
        quantity: (existing?.quantity ?? 0) + quantity,
      ),
    };
    state = current.copyWith(restaurantId: item.restaurantId, items: merged);
  }

  void setQuantity(String menuItemId, int quantity) {
    final items = {...state.items};
    if (quantity <= 0) {
      items.remove(menuItemId);
    } else {
      final line = items[menuItemId]!;
      items[menuItemId] = OrderLine(
        menuItemId: line.menuItemId,
        name: line.name,
        unitPriceMinor: line.unitPriceMinor,
        quantity: quantity,
      );
    }
    state = state.copyWith(items: items);
  }

  void remove(String menuItemId) => setQuantity(menuItemId, 0);

  void replaceRestaurant(MenuItem item, {int quantity = 1}) {
    state = const CartState();
    add(item, quantity: quantity);
  }

  void clear() => state = const CartState();
}

class CartRestaurantMismatch implements Exception {}

final cartProvider = NotifierProvider<CartController, CartState>(CartController.new);
