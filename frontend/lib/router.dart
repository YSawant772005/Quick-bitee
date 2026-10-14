import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/admin/admin_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/cart/cart_screen.dart';
import 'features/checkout/checkout_screen.dart';
import 'features/home/home_screen.dart';
import 'features/menu/menu_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/orders/order_detail_screen.dart';
import 'features/orders/order_history_screen.dart';
import 'models/models.dart';
import 'state/auth_controller.dart';

GoRouter buildRouter(AuthRefresher refresher) => GoRouter(
      initialLocation: '/',
      refreshListenable: refresher,
      redirect: (context, state) {
        final auth = refresher.currentState;
        final location = state.matchedLocation;
        if (auth is AuthUnknown) return location == '/splash' ? null : '/splash';
        if (auth is SignedOut) return location == '/login' ? null : '/login';
        final user = (auth as SignedIn).user;
        if (location == '/login' || location == '/splash') return '/';
        if (location.startsWith('/admin') && user.role != 'admin') return '/';
        return null;
      },
      routes: [
        GoRoute(
          path: '/splash',
          builder: (context, state) => const Scaffold(body: Center(child: CircularProgressIndicator())),
        ),
        GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        GoRoute(
          path: '/restaurant/:id',
          builder: (context, state) => MenuScreen(restaurantId: state.pathParameters['id']!),
        ),
        GoRoute(path: '/cart', builder: (context, state) => const CartScreen()),
        GoRoute(path: '/checkout', builder: (context, state) => const CheckoutScreen()),
        GoRoute(
          path: '/checkout-ack',
          builder: (context, state) {
            final accepted = state.extra as OrderAccepted;
            return CheckoutAckScreen(accepted: accepted);
          },
        ),
        GoRoute(path: '/orders', builder: (context, state) => const OrderHistoryScreen()),
        GoRoute(
          path: '/orders/:id',
          builder: (context, state) => OrderDetailScreen(orderId: state.pathParameters['id']!),
        ),
        GoRoute(path: '/notifications', builder: (context, state) => const NotificationsScreen()),
        GoRoute(path: '/admin', builder: (context, state) => const AdminScreen()),
      ],
    );

/// Bridges Riverpod auth state changes into go_router's refreshListenable.
class AuthRefresher extends ChangeNotifier {
  AuthRefresher(Ref ref) {
    ref.listen<AuthState>(authControllerProvider, (_, next) {
      currentState = next;
      notifyListeners();
    });
  }

  AuthState currentState = const AuthUnknown();
}
