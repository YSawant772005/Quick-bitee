import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quickbite/core/api_client.dart';
import 'package:quickbite/core/auth_storage.dart';
import 'package:quickbite/features/auth/login_screen.dart';
import 'package:quickbite/router.dart';
import 'package:quickbite/state/auth_controller.dart';

/// The router under test, kept reachable so assertions can read the location
/// the redirect actually landed on (rather than guessing from rendered pixels).
GoRouter? debugRouter;

/// Session-scoped token storage stub: a fresh page load has no stored session,
/// exactly like the real web build (which keeps the token in memory only).
class _NoSessionStorage extends AuthStorage {
  String? _token;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> saveToken(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}

/// Answers `/auth/login` with the role supplied by the test, so the redirect
/// under test is driven by a real login response rather than a hand-set state.
class _AuthApi implements HttpClientAdapter {
  _AuthApi({required this.role, required this.email});

  final String role;
  final String email;
  final List<String> requested = [];

  Map<String, dynamic> get _user => {'id': 'u-1', 'email': email, 'role': role};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options.path);

    final Object body;
    var status = 200;

    if (options.path.startsWith('/auth/login')) {
      body = {
        'access_token': 'test-token',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': _user,
      };
    } else if (options.path.startsWith('/auth/me')) {
      body = _user;
    } else if (options.path.startsWith('/admin/summary')) {
      // Minimal but complete summary so the admin page can render its data.
      body = {
        'total_orders': 0,
        'by_status': <String, int>{},
        'pending_outbox': 0,
        'retry_backlog': 0,
        'quarantine_count': 0,
        'currency': 'INR',
        'total_revenue_minor': 0,
        'successful_orders': 0,
        'failed_orders': 0,
        'active_customers': 0,
        'avg_order_value_minor': 0,
        'revenue_by_day': <Map<String, dynamic>>[],
        'top_dishes': <Map<String, dynamic>>[],
        'top_restaurants': <Map<String, dynamic>>[],
        'attention': <Map<String, dynamic>>[],
        'total_customers': 0,
        'active_deliveries': 0,
        'payment_failed_orders': 0,
        'unavailable_menu_items': 0,
        'unavailable_restaurants': 0,
      };
    } else if (options.path.startsWith('/admin/')) {
      status = 403;
      body = {'code': 'FORBIDDEN', 'message': 'admin only'};
    } else {
      body = {'items': <Map<String, dynamic>>[], 'page': 1, 'page_size': 20, 'total': 0};
    }

    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Host extends ConsumerStatefulWidget {
  const _Host({required this.role, required this.email, required this.location});

  final String role;
  final String email;
  final String location;

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
    _router = buildRouter(_refresher, initialLocation: widget.location);
    debugRouter = _router;
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(routerConfig: _router);
}

Future<_AuthApi> _mount(
  WidgetTester tester, {
  required String role,
  required String location,
  String? email,
}) async {
  final resolvedEmail = email ?? (role == 'admin' ? 'admin@quickbite.dev' : 'customer@quickbite.dev');
  final api = _AuthApi(role: role, email: resolvedEmail);
  final dio = Dio(BaseOptions(baseUrl: 'http://stub/api/v1'));
  dio.httpClientAdapter = api;

  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  addTearDown(() => debugRouter = null);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(ApiClient(dio: dio)),
        authStorageProvider.overrideWithValue(_NoSessionStorage()),
      ],
      child: _Host(role: role, email: resolvedEmail, location: location),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

String get _location => debugRouter!.routerDelegate.currentConfiguration.uri.toString();

Future<void> _signIn(WidgetTester tester, {required String email}) async {
  await tester.tap(find.text(email));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Sign in'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('/login shows the login screen when signed out', (tester) async {
    await _mount(tester, role: 'customer', location: '/login');

    expect(find.byType(LoginScreen), findsOneWidget,
        reason: 'a signed-out browser on /login must see the login form');
    expect(find.text('Welcome back'), findsOneWidget);
    expect(_location, '/login');
  });

  testWidgets('a signed-out browser on / is redirected to /login', (tester) async {
    await _mount(tester, role: 'customer', location: '/');

    expect(_location, '/login');
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('a successful admin login lands on the admin console', (tester) async {
    final api = await _mount(tester, role: 'admin', location: '/login');
    expect(find.byType(LoginScreen), findsOneWidget);

    await _signIn(tester, email: 'admin@quickbite.dev');

    expect(api.requested.first, '/auth/login');
    expect(_location, '/admin',
        reason: 'an admin signing in must be routed to their own console, '
            'not the customer homepage');
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('an authenticated admin is not bounced to the customer homepage', (tester) async {
    await _mount(tester, role: 'admin', location: '/login');
    await _signIn(tester, email: 'admin@quickbite.dev');
    expect(_location, '/admin');

    // Re-entering /login (or /splash) must not dump an admin on the customer
    // homepage — that is what made the console unreachable in practice.
    debugRouter!.go('/login');
    await tester.pumpAndSettle();

    expect(_location, '/admin', reason: 'signed-in admins never land on /');
  });

  testWidgets('a successful customer login lands on the customer home', (tester) async {
    await _mount(tester, role: 'customer', location: '/login');

    await _signIn(tester, email: 'customer@quickbite.dev');

    expect(_location, '/');
    expect(find.byType(LoginScreen), findsNothing);
  });
}
