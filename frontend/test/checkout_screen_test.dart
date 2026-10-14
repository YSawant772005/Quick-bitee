import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quickbite/core/api_client.dart';
import 'package:quickbite/features/checkout/checkout_screen.dart';
import 'package:quickbite/models/models.dart';
import 'package:quickbite/state/auth_controller.dart';
import 'package:quickbite/state/cart_controller.dart';

/// One recorded `POST /orders` attempt.
class _Attempt {
  _Attempt(this.headers, this.payload);
  final Map<String, dynamic> headers;
  final Map<String, dynamic> payload;
}

/// Answers `/orders` with a scripted sequence of outcomes and records every
/// attempt (headers + body) so the test can compare the retry against the
/// original request.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.outcomes);

  /// Either a status code + body, or a timeout.
  final List<Object> outcomes;
  final List<_Attempt> attempts = [];

  int get callCount => attempts.length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    attempts.add(_Attempt(
      Map<String, dynamic>.from(options.headers),
      Map<String, dynamic>.from(options.data as Map),
    ));

    final outcome = outcomes.length > 1 ? outcomes.removeAt(0) : outcomes.first;
    if (outcome is String) {
      throw DioException.receiveTimeout(
        timeout: const Duration(seconds: 15),
        requestOptions: options,
      );
    }
    final result = outcome as List<Object?>;
    final status = result[0] as int;
    final body = result[1] as Map<String, dynamic>;
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final _menuItem = MenuItem(
  id: 'f9292865-8959-46de-bc24-283c740780fb',
  restaurantId: 'a9b09801-6bf4-4df1-9c05-5f9b3d3df61b',
  name: 'Chicken 65 Biryani',
  description: 'Fiery Chicken 65 tossed through classic dum biryani.',
  priceMinor: 34000,
  currency: 'INR',
  imageUrl: '/static/catalog/dish-chicken65-biryani.jpg',
  available: true,
);

const _address = '221B Industrial Estate, Andheri East, Mumbai 400059';

const _accepted = {
  'order_id': '5b882aa3-d48f-4be2-92d7-ffa8c0cf5cca',
  'status': 'PENDING',
  'total_minor': 68000,
  'currency': 'INR',
};

/// Mounts the real CheckoutScreen behind a GoRouter (the screen navigates with
/// `context.go` on success) and seeds a one-item cart.
Widget _app(HttpClientAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://stub/api/v1'));
  dio.httpClientAdapter = adapter;
  final client = ApiClient(dio: dio);

  final router = GoRouter(
    initialLocation: '/checkout',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('home'))),
      GoRoute(path: '/checkout', builder: (_, __) => const CheckoutScreen()),
      GoRoute(
        path: '/checkout-ack',
        builder: (_, state) => Scaffold(
          body: Text('ack:${(state.extra! as OrderAccepted).orderId}'),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      cartProvider.overrideWith(() => _SeededCart()),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

/// Pre-loaded cart so the test does not have to drive the menu screen.
class _SeededCart extends CartController {
  @override
  CartState build() => CartState(
        restaurantId: _menuItem.restaurantId,
        restaurantName: 'Biryani Blues House',
        items: {
          _menuItem.id: OrderLine(
            menuItemId: _menuItem.id,
            name: _menuItem.name,
            unitPriceMinor: _menuItem.priceMinor,
            quantity: 2,
          ),
        },
      );
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Place order'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'a timeout retry reuses the same Idempotency-Key and clears the cart only after success',
      (tester) async {
    final adapter = _ScriptedAdapter([
      'receive timed out', // first attempt
      [202, _accepted], // retry
    ]);

    await tester.pumpWidget(_app(adapter));

    // Seeded cart is rendered before anything is submitted.
    expect(find.text('2 × Chicken 65 Biryani'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), _address);

    // --- Attempt 1: the request times out -------------------------------
    await _submit(tester);

    expect(adapter.callCount, 1, reason: 'the first POST /orders must be sent');
    expect(
      find.textContaining('You can safely retry'),
      findsOneWidget,
      reason: 'a receive timeout must surface the retryable error message',
    );
    expect(
      find.text('2 × Chicken 65 Biryani'),
      findsOneWidget,
      reason: 'the cart must survive a failed submission',
    );

    // --- Attempt 2: the user taps Place order again ---------------------
    await _submit(tester);

    expect(adapter.callCount, 2, reason: 'the retry must reach the API');
    expect(find.textContaining('You can safely retry'), findsNothing);
    expect(
      find.text('ack:5b882aa3-d48f-4be2-92d7-ffa8c0cf5cca'),
      findsOneWidget,
      reason: 'the accepted order is routed to the acknowledgement screen',
    );
    expect(
      find.text('2 × Chicken 65 Biryani'),
      findsNothing,
      reason: 'the cart is cleared only once the order is accepted',
    );

    // --- The guarantee: the retry is the same order, not a new one ------
    final first = adapter.attempts[0];
    final second = adapter.attempts[1];

    expect(first.headers['Idempotency-Key'], isNotNull);
    expect(
      second.headers['Idempotency-Key'],
      first.headers['Idempotency-Key'],
      reason: 'a retry after a timeout MUST reuse the idempotency key, '
          'otherwise the server creates a second order for one user intent',
    );
    expect(second.payload, equals(first.payload),
        reason: 'the retried payload must be identical so the server replays '
            'the stored response instead of conflicting with 409');
  });
}