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

/// Records every request the console makes and answers with canned payloads
/// that mirror the real admin API shapes.
class _AdminApi implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  /// When true the orders list and detail endpoints return one confirmed order
  /// instead of an empty page, so a test can open the detail view.
  bool withOrder = false;

  static const _orderListItem = <String, dynamic>{
    'id': 'ord-1',
    'status': 'CONFIRMED',
    'total_minor': 64000,
    'currency': 'INR',
    'created_at': '2026-10-15T10:30:00Z',
    'restaurant_name': 'Paradise Biryani',
    'item_summary': 'Hyderabadi Chicken Biryani ×2',
    'customer_id': 'u-9',
    'customer_email': 'asha@example.com',
    'payment_status': 'SUCCESS',
    'payment_attempts': 1,
    'item_count': 2,
    'updated_at': '2026-10-15T10:35:00Z',
  };

  static const _orderDetail = <String, dynamic>{
    'id': 'ord-1',
    'restaurant_id': 'r-1',
    'restaurant_name': 'Paradise Biryani',
    'status': 'CONFIRMED',
    'total_minor': 64000,
    'currency': 'INR',
    'delivery_address': '12 MG Road, Bengaluru 560001',
    'version': 3,
    'failure_reason': null,
    'driver': null,
    'items': [
      {
        'menu_item_id': 'm-1',
        'name': 'Hyderabadi Chicken Biryani',
        'unit_price_minor': 32000,
        'quantity': 2,
        'image_url': '',
      },
    ],
    'created_at': '2026-10-15T10:30:00Z',
    'updated_at': '2026-10-15T10:35:00Z',
    'customer_id': 'u-9',
    'customer_email': 'asha@example.com',
    'payment_status': 'SUCCESS',
    'payment_attempts': 1,
    'payment_failure_reason': null,
    'timeline': [
      {'status': 'PENDING', 'version': 1, 'note': 'Order placed', 'created_at': '2026-10-15T10:30:00Z'},
      {'status': 'CONFIRMED', 'version': 2, 'note': 'Payment captured', 'created_at': '2026-10-15T10:31:00Z'},
    ],
  };

  List<RequestOptions> requestsTo(String prefix) =>
      requests.where((r) => r.path.startsWith(prefix)).toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);

    final Object body;
    var status = 200;

    if (options.path.startsWith('/admin/summary')) {
      body = _summary(options);
    } else if (withOrder && options.path.startsWith('/admin/orders/')) {
      body = _orderDetail;
    } else if (options.path.startsWith('/admin/orders')) {
      body = {
        'items': withOrder ? [_orderListItem] : <Map<String, dynamic>>[],
        'page': int.tryParse('${options.queryParameters['page']}') ?? 1,
        'page_size': int.tryParse('${options.queryParameters['page_size']}') ?? 20,
        'total': withOrder ? 1 : 0,
      };
    } else {
      status = 404;
      body = {'code': 'NOT_FOUND', 'message': 'no stub for ${options.path}'};
    }

    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}

  /// Echoes the requested period back so tests can prove every widget is
  /// scoped to the range shown in the header.
  Map<String, dynamic> _summary(RequestOptions options) => {
        'total_orders': 3,
        'by_status': {'PENDING': 1, 'PAID': 1, 'DRIVER_ASSIGNED': 1},
        'pending_outbox': 0,
        'retry_backlog': 0,
        'quarantine_count': 0,
        'currency': 'INR',
        'total_revenue_minor': 125000,
        'successful_orders': 2,
        'failed_orders': 0,
        'active_customers': 2,
        'avg_order_value_minor': 62500,
        'date_from': options.queryParameters['date_from'],
        'date_to': options.queryParameters['date_to'],
        'granularity': options.queryParameters['granularity'] ?? 'day',
        'revenue_by_day': [
          {'date': '2026-10-14', 'orders': 1, 'revenue_minor': 50000},
          {'date': '2026-10-15', 'orders': 1, 'revenue_minor': 75000},
        ],
        'top_dishes': <Map<String, dynamic>>[],
        'top_restaurants': <Map<String, dynamic>>[],
        'attention': <Map<String, dynamic>>[],
        'comparison': {
          'date_from': '2026-10-02',
          'date_to': '2026-10-08',
          'orders': {'current': 3, 'previous': 1, 'change_pct': 200.0},
          'revenue_minor': {'current': 125000, 'previous': 60000, 'change_pct': 108.3},
          'active_customers': {'current': 2, 'previous': 1, 'change_pct': 100.0},
          'avg_order_value_minor': {'current': 62500, 'previous': 60000, 'change_pct': 4.2},
        },
        'unavailable_menu_items': 0,
        'unavailable_restaurants': 0,
        'total_customers': 5,
        'active_deliveries': 1,
        'payment_failed_orders': 0,
      };
}

class _FakeAuth extends AuthController {
  _FakeAuth(this._initial);

  final AuthState _initial;

  @override
  AuthState build() => _initial;
}

/// Mounts the real router behind a ProviderScope, with the auth state pinned to
/// a known role before the first frame so the production redirect runs.
class _Host extends ConsumerStatefulWidget {
  const _Host({required this.role, required this.initialLocation});

  final String role;
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
      User(
        id: 'u-1',
        email: widget.role == 'admin' ? 'admin@quickbite.dev' : 'customer@quickbite.dev',
        role: widget.role,
      ),
    );
    _router = buildRouter(_refresher, initialLocation: widget.initialLocation);
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(routerConfig: _router);
}

Future<_AdminApi> _mount(
  WidgetTester tester, {
  required String role,
  String location = '/admin',
  Size size = const Size(1440, 900),
  bool withOrder = false,
}) async {
  final api = _AdminApi()..withOrder = withOrder;
  final dio = Dio(BaseOptions(baseUrl: 'http://stub/api/v1'));
  dio.httpClientAdapter = api;

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(ApiClient(dio: dio)),
        authControllerProvider.overrideWith(() => _FakeAuth(_initial(role))),
      ],
      child: _Host(role: role, initialLocation: location),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

AuthState _initial(String role) => SignedIn(
      User(
        id: 'u-1',
        email: role == 'admin' ? 'admin@quickbite.dev' : 'customer@quickbite.dev',
        role: role,
      ),
    );

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

void main() {
  const sidebarModules = [
    'Overview',
    'Orders',
    'Restaurants',
    'Menu Management',
    'Customers',
    'Deliveries',
    'Analytics',
    'Settings',
  ];

  testWidgets('the admin console has its own shell, nav and real KPIs', (tester) async {
    final api = await _mount(tester, role: 'admin');

    // --- Own chrome: sidebar + operational branding ----------------------
    expect(find.text('OPERATIONS CONSOLE'), findsOneWidget,
        reason: 'the admin shell must render its own sidebar identity');
    expect(find.text('Sign out'), findsOneWidget,
        reason: 'logout lives at the bottom of the admin sidebar');

    for (final module in sidebarModules) {
      expect(find.text(module), findsWidgets, reason: 'sidebar module missing: $module');
    }

    // Modules the backend cannot back must not be advertised.
    expect(find.text('Offers & Coupons'), findsNothing,
        reason: 'no offers/coupons backend exists - do not link to a dead page');
    expect(find.text('Reviews'), findsNothing,
        reason: 'no reviews backend exists - do not link to a dead page');

    // --- Not the customer shell -----------------------------------------
    expect(find.byType(BottomNavigationBar), findsNothing,
        reason: 'the customer bottom nav must never appear in the admin shell');
    expect(find.text('Explore'), findsNothing,
        reason: 'customer navigation must not be reused by the admin console');

    // --- Real, period-scoped KPIs ----------------------------------------
    expect(find.text('TOTAL ORDERS'), findsOneWidget);
    expect(find.text('REVENUE (INR)'), findsOneWidget);
    expect(find.text('ACTIVE CUSTOMERS'), findsOneWidget);
    expect(find.text('AVG ORDER VALUE'), findsOneWidget);
    expect(find.text('₹1250'), findsOneWidget, reason: 'revenue comes from the API payload');
    expect(find.text('+200.0%'), findsOneWidget,
        reason: 'the previous-period comparison must be rendered');

    // --- The overview actually queried the API ---------------------------
    final summaries = api.requestsTo('/admin/summary');
    expect(summaries, isNotEmpty);
    expect(summaries.first.queryParameters['date_from'], isNotNull);
    expect(summaries.first.queryParameters['date_to'], isNotNull);
    expect(api.requestsTo('/admin/orders'), isNotEmpty,
        reason: 'the recent-orders table is server-paginated');
  });

  testWidgets('changing the reporting period re-queries every widget', (tester) async {
    final api = await _mount(tester, role: 'admin');

    final today = _day(DateTime.now());
    final defaultRange = api.requestsTo('/admin/summary').first.queryParameters;
    expect(defaultRange['date_from'], _iso(today.subtract(const Duration(days: 6))),
        reason: 'the default period is the last 7 days');
    expect(defaultRange['date_to'], _iso(today));

    await tester.tap(find.text('Last 30'));
    await tester.pumpAndSettle();

    final summaries = api.requestsTo('/admin/summary');
    final latest = summaries.last.queryParameters;
    expect(summaries.length, greaterThan(1),
        reason: 'selecting a range must trigger a new request');
    expect(latest['date_from'], _iso(today.subtract(const Duration(days: 29))));
    expect(latest['date_to'], _iso(today));

    // The orders table shares the same reporting period.
    final orders = api.requestsTo('/admin/orders').last.queryParameters;
    expect(orders['date_from'], latest['date_from']);
    expect(orders['date_to'], latest['date_to']);

    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    final todayRange = api.requestsTo('/admin/summary').last.queryParameters;
    expect(todayRange['date_from'], _iso(today));
    expect(todayRange['date_to'], _iso(today));
  });

  testWidgets('search and status filters are sent to the server', (tester) async {
    final api = await _mount(tester, role: 'admin', location: '/admin/orders');

    expect(find.text('All orders'), findsOneWidget);
    expect(find.text('No orders in this period'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'biryani');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    final searched = api.requestsTo('/admin/orders').last.queryParameters;
    expect(searched['search'], 'biryani',
        reason: 'the search box must be a server-side filter');

    await tester.tap(find.byWidgetPredicate((w) => w is DropdownButtonFormField).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Payment failed').last);
    await tester.pumpAndSettle();

    final statusFiltered = api.requestsTo('/admin/orders').last.queryParameters;
    expect(statusFiltered['status'], 'PAYMENT_FAILED');
    expect(statusFiltered['search'], 'biryani', reason: 'filters combine');
    expect('${statusFiltered['page']}', '1', reason: 'changing a filter resets to page 1');
  });

  testWidgets('non-admins are redirected away from every admin route', (tester) async {
    final api = await _mount(tester, role: 'customer', location: '/admin');

    expect(find.text('OPERATIONS CONSOLE'), findsNothing,
        reason: 'a customer session must never see the admin shell');
    expect(find.text('Sign out'), findsNothing);
    expect(find.text('Explore'), findsWidgets,
        reason: 'the customer is returned to the customer app, which keeps its own nav');
    expect(api.requestsTo('/admin/'), isEmpty,
        reason: 'the client must not even call admin endpoints as a customer');
  });

  testWidgets('the console adapts to a phone viewport without overflowing', (tester) async {
    await _mount(
      tester,
      role: 'admin',
      location: '/admin/orders',
      size: const Size(390, 844),
    );

    expect(find.text('All orders'), findsOneWidget,
        reason: 'the orders module still renders on mobile');
    expect(find.text('OPERATIONS CONSOLE'), findsNothing,
        reason: 'the sidebar becomes a drawer, not a permanent rail');

    // The drawer toggle is what makes the sidebar reachable on small screens.
    final menuButton = find.byIcon(Icons.menu_rounded);
    expect(menuButton, findsOneWidget);
    await tester.tap(menuButton);
    await tester.pumpAndSettle();
    expect(find.text('OPERATIONS CONSOLE'), findsOneWidget,
        reason: 'the drawer exposes the admin nav');
    expect(find.text('Menu Management'), findsWidgets);

    // No takeException() here: the framework prints the full RenderFlex
    // report (including the offending widget) if anything overflowed.
  });

  testWidgets('an order row opens the full detail view', (tester) async {
    final api = await _mount(
      tester,
      role: 'admin',
      location: '/admin/orders',
      withOrder: true,
    );

    expect(find.text('Paradise Biryani'), findsWidgets,
        reason: 'the list row shows the restaurant');

    await tester.tap(find.text('View').first);
    await tester.pumpAndSettle();

    expect(api.requestsTo('/admin/orders/ord-1'), isNotEmpty,
        reason: 'the detail view loads its own payload');

    expect(find.text('Order details'), findsWidgets);
    expect(find.text('Customer & delivery'), findsOneWidget);
    expect(find.text('asha@example.com'), findsWidgets);
    expect(find.text('12 MG Road, Bengaluru 560001'), findsWidgets,
        reason: 'delivery address is shown to admins');
    expect(find.text('Hyderabadi Chicken Biryani'), findsWidgets,
        reason: 'line items are rendered');
    expect(find.text('Fulfilment timeline'), findsOneWidget);
    expect(find.text('Order placed'), findsWidgets,
        reason: 'real timeline entries only');
    expect(find.text('Status'), findsWidgets);
    expect(find.text('Total'), findsWidgets);

    expect(tester.takeException(), isNull);
  });
}
