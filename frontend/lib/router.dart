import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show WidgetRef;
import 'package:go_router/go_router.dart';

import 'features/admin/admin_shell.dart';
import 'features/admin/analytics_page.dart';
import 'features/admin/customers_page.dart';
import 'features/admin/deliveries_page.dart';
import 'features/admin/menu_page.dart';
import 'features/admin/order_detail_page.dart';
import 'features/admin/orders_page.dart';
import 'features/admin/overview_page.dart';
import 'features/admin/restaurants_page.dart';
import 'features/admin/settings_page.dart';
import 'features/auth/login_screen.dart';
import 'features/cart/cart_screen.dart';
import 'features/checkout/checkout_screen.dart';
import 'features/explore/explore_screen.dart';
import 'features/home/home_screen.dart';
import 'features/menu/menu_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/orders/order_detail_screen.dart';
import 'features/orders/order_history_screen.dart';
import 'features/profile/profile_screen.dart';
import 'models/models.dart';
import 'shared/theme.dart';
import 'shared/widgets.dart';
import 'state/auth_controller.dart';

/// [initialLocation] is overridable so tests can mount the router directly on
/// the route they are asserting about (production always starts at `/`).
GoRouter buildRouter(AuthRefresher refresher, {String initialLocation = '/'}) => GoRouter(
      initialLocation: initialLocation,
      refreshListenable: refresher,
      redirect: (context, state) {
        final auth = refresher.currentState;
        final location = state.matchedLocation;
        if (auth is AuthUnknown) return location == '/splash' ? null : '/splash';
        if (auth is SignedOut) return location == '/login' ? null : '/login';
        final user = (auth as SignedIn).user;
        final isAdmin = user.role == 'admin';
        // `/login` and `/splash` are only meaningful while signed out. Once a
        // session exists, bounce to the surface that session belongs to — an
        // admin must land on the console, never on the customer homepage.
        if (location == '/login' || location == '/splash') {
          return isAdmin ? '/admin' : '/';
        }
        if (location.startsWith('/admin') && !isAdmin) return '/';
        return null;
      },
      routes: [
        GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
        GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        GoRoute(
          path: '/explore',
          builder: (context, state) => ExploreScreen(
            initialQuery: state.uri.queryParameters['q'] ?? '',
            initialCuisine: state.uri.queryParameters['cuisine'] ?? '',
          ),
        ),
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
        GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),

        // Admin console: one shell (sidebar + header) wrapping every admin
        // route, so navigation state and chrome are owned by AdminShell alone.
        // The top-level redirect blocks the whole subtree for non-admins.
        ShellRoute(
          builder: (context, state, child) => AdminShell(child: child),
          routes: [
            GoRoute(path: '/admin', builder: (context, state) => const AdminOverviewPage()),
            GoRoute(path: '/admin/orders', builder: (context, state) => const AdminOrdersPage()),
            GoRoute(
              path: '/admin/orders/:id',
              builder: (context, state) =>
                  AdminOrderDetailPage(orderId: state.pathParameters['id']!),
            ),
            GoRoute(path: '/admin/restaurants', builder: (context, state) => const AdminRestaurantsPage()),
            GoRoute(path: '/admin/menu', builder: (context, state) => const AdminMenuPage()),
            GoRoute(path: '/admin/customers', builder: (context, state) => const AdminCustomersPage()),
            GoRoute(path: '/admin/deliveries', builder: (context, state) => const AdminDeliveriesPage()),
            GoRoute(path: '/admin/analytics', builder: (context, state) => const AdminAnalyticsPage()),
            GoRoute(path: '/admin/settings', builder: (context, state) => const AdminSettingsPage()),
          ],
        ),
      ],
    );

/// Branded splash shown while the stored session is restored.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.cream,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandLogo(size: 48),
            SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bridges Riverpod auth state changes into go_router's refreshListenable.
class AuthRefresher extends ChangeNotifier {
  AuthRefresher(WidgetRef ref) {
    ref.listenManual<AuthState>(authControllerProvider, (_, next) {
      currentState = next;
      notifyListeners();
    });
  }

  AuthState currentState = const AuthUnknown();
}
