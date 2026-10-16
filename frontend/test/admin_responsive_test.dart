import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quickbite/core/api_client.dart';
import 'package:quickbite/models/models.dart';
import 'package:quickbite/router.dart';
import 'package:quickbite/state/auth_controller.dart';

/// Serves a *full* admin console payload — every catalogue, list and reporting
/// endpoint — so each screen renders its populated layout (tables, charts,
/// metric grids) rather than a loading or empty state. That is what makes the
/// responsive assertions meaningful: an empty screen never overflows.
class _FullAdminApi implements HttpClientAdapter {
  _FullAdminApi({this.withOrder = false});

  final bool withOrder;

  static const _cost = <String, dynamic>{
    'id': 'ord-1',
    'status': 'CONFIRMED',
    'total_minor': 128400,
    'currency': 'INR',
    'created_at': '2026-10-15T10:30:00Z',
    'restaurant_name': 'Paradise Biryani House',
    'item_summary': 'Hyderabadi Chicken Biryani ×2, Butter Naan ×3',
    'customer_id': 'u-9',
    'customer_email': 'asha.venkatesan@example.com',
    'payment_status': 'SUCCESS',
    'payment_attempts': 1,
    'item_count': 5,
    'updated_at': '2026-10-15T10:35:00Z',
  };

  static const _orderDetail = <String, dynamic>{
    'id': 'ord-1',
    'restaurant_id': 'r-1',
    'restaurant_name': 'Paradise Biryani House',
    'status': 'CONFIRMED',
    'total_minor': 128400,
    'currency': 'INR',
    'delivery_address': '12 MG Road, Bengaluru 560001, Karnataka, India',
    'version': 3,
    'failure_reason': null,
    'driver': null,
    'items': [
      {
        'menu_item_id': 'm-1',
        'name': 'Hyderabadi Chicken Biryani (Family Pack)',
        'unit_price_minor': 32000,
        'quantity': 2,
        'image_url': '',
      },
      {
        'menu_item_id': 'm-2',
        'name': 'Butter Naan',
        'unit_price_minor': 4500,
        'quantity': 3,
        'image_url': '',
      },
    ],
    'created_at': '2026-10-15T10:30:00Z',
    'updated_at': '2026-10-15T10:35:00Z',
    'customer_id': 'u-9',
    'customer_email': 'asha.venkatesan@example.com',
    'payment_status': 'SUCCESS',
    'payment_attempts': 1,
    'payment_failure_reason': null,
    'timeline': [
      {'status': 'PENDING', 'version': 1, 'note': 'Order placed by the customer', 'created_at': '2026-10-15T10:30:00Z'},
      {'status': 'PAID', 'version': 2, 'note': 'Simulated payment captured', 'created_at': '2026-10-15T10:31:00Z'},
      {'status': 'CONFIRMED', 'version': 3, 'note': 'Restaurant accepted the order', 'created_at': '2026-10-15T10:32:00Z'},
    ],
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = _route(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  Object _route(RequestOptions options) {
    final path = options.path;
    if (path.startsWith('/admin/summary')) return _summary();
    if (path.startsWith('/admin/analytics')) return _analytics();
    if (path.startsWith('/admin/orders/')) return _orderDetail;
    if (path.startsWith('/admin/orders')) return _page(withOrder ? [_cost] : const [], 1);
    if (path.startsWith('/admin/restaurants')) return _page(_restaurants, 42);
    if (path.startsWith('/admin/menu-items')) return _page(_menuItems, 137);
    if (path.startsWith('/admin/customers')) return _page(_customers, 88);
    if (path.startsWith('/admin/deliveries')) return _page(_deliveries, 12);
    return {'code': 'NOT_FOUND', 'message': 'no stub for $path'};
  }

  Map<String, dynamic> _page(List<Map<String, dynamic>> items, int total) => {
        'items': items,
        'page': 1,
        'page_size': 20,
        'total': total,
      };

  static const _restaurants = <Map<String, dynamic>>[
    {
      'id': 'r-1',
      'name': 'Paradise Biryani House',
      'description': 'Hyderabadi dum biryani since 1953.',
      'cuisine': 'Hyderabadi · Biryani · Mughlai',
      'image_url': '',
      'available': true,
      'menu_item_count': 48,
      'available_item_count': 44,
      'order_count': 1893,
      'revenue_minor': 125000000,
    },
    {
      'id': 'r-2',
      'name': 'The Coorg Table',
      'description': 'Kodava home cooking.',
      'cuisine': 'Kodava · South Indian',
      'image_url': '',
      'available': false,
      'menu_item_count': 31,
      'available_item_count': 12,
      'order_count': 402,
      'revenue_minor': 28400000,
    },
  ];

  static const _menuItems = <Map<String, dynamic>>[
    {
      'id': 'm-1',
      'restaurant_id': 'r-1',
      'restaurant_name': 'Paradise Biryani House',
      'name': 'Hyderabadi Chicken Biryani (Family Pack)',
      'description': 'Serves four.',
      'price_minor': 32000,
      'currency': 'INR',
      'image_url': '',
      'available': true,
      'units_sold': 812,
      'revenue_minor': 25984000,
    },
    {
      'id': 'm-2',
      'restaurant_id': 'r-1',
      'restaurant_name': 'Paradise Biryani House',
      'name': 'Butter Naan',
      'description': 'Fresh from the tandoor.',
      'price_minor': 4500,
      'currency': 'INR',
      'image_url': '',
      'available': false,
      'units_sold': 1520,
      'revenue_minor': 6840000,
    },
  ];

  static const _customers = <Map<String, dynamic>>[
    {
      'id': 'u-9',
      'email': 'asha.venkatesan@example.com',
      'role': 'customer',
      'registered_at': '2026-07-02T09:00:00Z',
      'total_orders': 27,
      'successful_orders': 24,
      'active_orders': 2,
      'last_order_at': '2026-10-15T10:30:00Z',
      'total_spent_minor': 1825000,
      'currency': 'INR',
    },
  ];

  static const _deliveries = <Map<String, dynamic>>[
    {
      'order_id': 'ord-1',
      'driver_name': 'Ravi Kulkarni',
      'vehicle': 'Bike · KA 05 HJ 1234',
      'eta_minutes': 24,
      'order_status': 'DRIVER_ASSIGNED',
      'restaurant_name': 'Paradise Biryani House',
      'customer_email': 'asha.venkatesan@example.com',
      'total_minor': 128400,
      'currency': 'INR',
      'created_at': '2026-10-15T10:30:00Z',
      'delivery_address': '12 MG Road, Bengaluru',
    },
  ];

  Map<String, dynamic> _summary() => {
        'total_orders': 1284,
        'by_status': {
          'PENDING': 12,
          'PAID': 8,
          'CONFIRMED': 34,
          'DRIVER_ASSIGNED': 21,
          'PAYMENT_FAILED': 3,
          'FAILED': 5,
        },
        'pending_outbox': 4,
        'retry_backlog': 1,
        'quarantine_count': 0,
        'currency': 'INR',
        'total_revenue_minor': 125000000,
        'successful_orders': 1189,
        'failed_orders': 8,
        'active_customers': 934,
        'avg_order_value_minor': 62500,
        'date_from': '2026-10-09',
        'date_to': '2026-10-15',
        'granularity': 'day',
        'revenue_by_day': [
          {'date': '2026-10-09', 'orders': 130, 'revenue_minor': 15000000},
          {'date': '2026-10-10', 'orders': 180, 'revenue_minor': 21000000},
          {'date': '2026-10-11', 'orders': 210, 'revenue_minor': 25500000},
          {'date': '2026-10-12', 'orders': 165, 'revenue_minor': 19000000},
          {'date': '2026-10-13', 'orders': 205, 'revenue_minor': 24000000},
          {'date': '2026-10-14', 'orders': 190, 'revenue_minor': 22500000},
          {'date': '2026-10-15', 'orders': 140, 'revenue_minor': 16500000},
        ],
        'top_dishes': [
          {
            'name': 'Hyderabadi Chicken Biryani (Family Pack)',
            'quantity': 812,
            'revenue_minor': 25984000,
            'menu_item_id': 'm-1',
            'image_url': '',
            'restaurant_name': 'Paradise Biryani House',
          },
          {
            'name': 'Butter Naan',
            'quantity': 1520,
            'revenue_minor': 6840000,
            'menu_item_id': 'm-2',
            'image_url': '',
            'restaurant_name': 'Paradise Biryani House',
          },
        ],
        'top_restaurants': [
          {
            'restaurant_id': 'r-1',
            'name': 'Paradise Biryani House',
            'image_url': '',
            'orders': 640,
            'revenue_minor': 125000000,
          },
        ],
        'attention': [
          {'key': 'awaiting_payment', 'label': '12 orders awaiting payment', 'count': 12},
          {'key': 'awaiting_confirmation', 'label': '8 paid orders awaiting confirm', 'count': 8},
          {'key': 'payment_failed', 'label': '3 payments failed', 'count': 3},
          {'key': 'unavailable_menu_items', 'label': '4 dishes hidden from customers', 'count': 4},
        ],
        'comparison': {
          'date_from': '2026-10-02',
          'date_to': '2026-10-08',
          'orders': {'current': 1284, 'previous': 1102, 'change_pct': 16.5},
          'revenue_minor': {'current': 125000000, 'previous': 118000000, 'change_pct': 5.9},
          'active_customers': {'current': 934, 'previous': 901, 'change_pct': 3.7},
          'avg_order_value_minor': {'current': 62500, 'previous': 61000, 'change_pct': 2.5},
        },
        'unavailable_menu_items': 4,
        'unavailable_restaurants': 1,
        'total_customers': 934,
        'active_deliveries': 21,
        'payment_failed_orders': 3,
      };

  Map<String, dynamic> _analytics() => {
        'currency': 'INR',
        'date_from': '2026-10-09',
        'date_to': '2026-10-15',
        'granularity': 'day',
        'total_orders': 1284,
        'total_revenue_minor': 125000000,
        'successful_orders': 1189,
        'failed_orders': 8,
        'avg_order_value_minor': 62500,
        'active_customers': 934,
        'avg_items_per_order': 3.4,
        'revenue_by_day': [
          {'date': '2026-10-09', 'orders': 130, 'revenue_minor': 15000000},
          {'date': '2026-10-10', 'orders': 180, 'revenue_minor': 21000000},
          {'date': '2026-10-11', 'orders': 210, 'revenue_minor': 25500000},
          {'date': '2026-10-12', 'orders': 165, 'revenue_minor': 19000000},
          {'date': '2026-10-13', 'orders': 205, 'revenue_minor': 24000000},
        ],
        'revenue_by_restaurant': [
          {
            'restaurant_id': 'r-1',
            'name': 'Paradise Biryani House',
            'image_url': '',
            'orders': 640,
            'revenue_minor': 66000000,
          },
          {
            'restaurant_id': 'r-2',
            'name': 'The Coorg Table',
            'image_url': '',
            'orders': 402,
            'revenue_minor': 28400000,
          },
        ],
        'orders_by_weekday': [
          {'label': 'Mon', 'count': 140, 'revenue_minor': 0},
          {'label': 'Tue', 'count': 165, 'revenue_minor': 0},
          {'label': 'Wed', 'count': 190, 'revenue_minor': 0},
          {'label': 'Thu', 'count': 205, 'revenue_minor': 0},
          {'label': 'Fri', 'count': 260, 'revenue_minor': 0},
          {'label': 'Sat', 'count': 210, 'revenue_minor': 0},
          {'label': 'Sun', 'count': 114, 'revenue_minor': 0},
        ],
        'orders_by_hour': [
          {'label': '12:00', 'count': 90, 'revenue_minor': 0},
          {'label': '13:00', 'count': 130, 'revenue_minor': 0},
          {'label': '19:00', 'count': 210, 'revenue_minor': 0},
          {'label': '20:00', 'count': 260, 'revenue_minor': 0},
          {'label': '21:00', 'count': 180, 'revenue_minor': 0},
        ],
        'orders_by_status': {
          'PENDING': 12,
          'PAID': 8,
          'CONFIRMED': 34,
          'DRIVER_ASSIGNED': 21,
          'PAYMENT_FAILED': 3,
          'FAILED': 5,
        },
      };
  @override
  void close({bool force = false}) {}
}

class _FakeAuth extends AuthController {
  _FakeAuth(this._initial);
  final AuthState _initial;

  @override
  AuthState build() => _initial;
}

class _Host extends ConsumerStatefulWidget {
  const _Host({required this.initialLocation});
  final String initialLocation;

  @override
  ConsumerState<_Host> createState() => _HostState();
}

class _HostState extends ConsumerState<_Host> {
  late final AuthRefresher _refresher;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _refresher = AuthRefresher(ref);
    _refresher.currentState = SignedIn(
      User(id: 'u-1', email: 'admin@quickbite.dev', role: 'admin'),
    );
    _router = buildRouter(_refresher, initialLocation: widget.initialLocation);
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(routerConfig: _router);
}

Future<void> _pumpAt(
  WidgetTester tester, {
  required String location,
  required Size size,
  bool withOrder = false,
}) async {
  final dio = Dio(BaseOptions(baseUrl: 'http://stub/api/v1'));
  dio.httpClientAdapter = _FullAdminApi(withOrder: withOrder);

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(ApiClient(dio: dio)),
        authControllerProvider.overrideWith(
          () => _FakeAuth(
            SignedIn(User(id: 'u-1', email: 'admin@quickbite.dev', role: 'admin')),
          ),
        ),
      ],
      child: _Host(initialLocation: location),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const routes = <String, String>{
    '/admin': 'Operations overview',
    '/admin/orders': 'Orders',
    '/admin/restaurants': 'Restaurants',
    '/admin/menu': 'Menu management',
    '/admin/customers': 'Customers',
    '/admin/deliveries': 'Deliveries',
    '/admin/analytics': 'Analytics',
    '/admin/settings': 'Settings',
  };

  const sizes = <String, Size>{
    'small phone': Size(320, 720),
    'phone': Size(390, 844),
    'tablet': Size(834, 1112),
    'desktop': Size(1440, 900),
  };

  for (final route in routes.entries) {
    for (final size in sizes.entries) {
      testWidgets(
        '${route.value} renders without overflow on a ${size.key}',
        (tester) async {
          await _pumpAt(tester, location: route.key, size: size.value);
          expect(
            tester.takeException(),
            isNull,
            reason: '${route.value} overflowed at ${size.value.width.toInt()}px',
          );
        },
      );
    }
  }

  for (final size in sizes.entries) {
    testWidgets('order detail renders without overflow on a ${size.key}', (tester) async {
      await _pumpAt(
        tester,
        location: '/admin/orders',
        size: size.value,
        withOrder: true,
      );
      // The fulfilment table sits below the page header; bring the action
      // into view before tapping so the test drives the real navigation.
      final viewButton = find.text('View').first;
      await tester.ensureVisible(viewButton);
      await tester.pumpAndSettle();
      await tester.tap(viewButton);
      await tester.pumpAndSettle();

      expect(find.text('Customer & delivery'), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: 'order detail overflowed at ${size.value.width.toInt()}px',
      );
    });
  }

  testWidgets('KPI tiles use a two-column grid on a phone', (tester) async {
    await _pumpAt(tester, location: '/admin', size: const Size(390, 844));

    final first = tester.getTopLeft(find.text('TOTAL ORDERS'));
    final second = tester.getTopLeft(find.text('REVENUE (INR)'));

    expect(second.dy, first.dy,
        reason: 'the second KPI sits beside the first on a phone (two columns)');
    expect(second.dx, greaterThan(first.dx),
        reason: 'the second KPI must occupy the second column, not a new row');
  });
}
