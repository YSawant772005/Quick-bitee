import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickbite/core/api_client.dart';
import 'package:quickbite/features/orders/order_detail_screen.dart';
import 'package:quickbite/state/auth_controller.dart';

/// Serves canned JSON so the widget test never touches the network.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.routes);

  final Map<String, Map<String, dynamic>> routes;
  final List<String> requested = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    requested.add(path);
    final body = routes.entries.firstWhere(
      (e) => path.endsWith(e.key),
      orElse: () => const MapEntry('', <String, dynamic>{}),
    ).value;
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _orderId = '5b882aa3-d48f-4be2-92d7-ffa8c0cf5cca';

Map<String, dynamic> _orderJson() => {
      'id': _orderId,
      'restaurant_id': 'r-1',
      'restaurant_name': 'Biryani Blues House',
      'status': 'DRIVER_ASSIGNED',
      'total_minor': 68000,
      'currency': 'INR',
      'delivery_address': '221B Industrial Estate, Andheri East, Mumbai 400059',
      'version': 4,
      'failure_reason': null,
      'driver': {
        'driver_name': 'Neha Singh',
        'vehicle': 'KA-07-EF-7654, Honda Dio',
        'eta_minutes': 25,
      },
      'items': [
        {
          'menu_item_id': 'f9292865-8959-46de-bc24-283c740780fb',
          'name': 'Chicken 65 Biryani',
          'unit_price_minor': 34000,
          'quantity': 2,
          'line_total_minor': 68000,
        }
      ],
      'created_at': '2026-10-14T17:06:43Z',
      'updated_at': '2026-10-14T17:06:48Z',
    };

Map<String, dynamic> _paginated(List<Map<String, dynamic>> items) => {
      'items': items,
      'page': 1,
      'page_size': 100,
      'total': items.length,
    };

Map<String, dynamic> _notification(String eventType, String title) => {
      'id': 'n-$eventType',
      'order_id': _orderId,
      'event_type': eventType,
      'title': title,
      'message': 'Message for $eventType',
      'created_at': '2026-10-14T17:06:48Z',
    };

Widget _app(HttpClientAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://stub/api/v1'));
  dio.httpClientAdapter = adapter;
  final client = ApiClient(dio: dio);
  return ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(client)],
    child: const MaterialApp(home: OrderDetailScreen(orderId: _orderId)),
  );
}

void main() {
  testWidgets('tracking screen renders the timeline and this order\'s notifications', (tester) async {
    final adapter = _StubAdapter({
      '/history': _paginated([
        {
          'status': 'PENDING',
          'version': 1,
          'note': 'Order accepted',
          'created_at': '2026-10-14T17:06:41Z',
        },
        {
          'status': 'PAID',
          'version': 2,
          'note': 'Payment captured',
          'created_at': '2026-10-14T17:06:44Z',
        },
      ]),
      '/notifications': _paginated([
        _notification('order.created', 'Order received'),
        _notification('order.driver.assigned', 'Driver on the way'),
      ]),
      _orderId: _orderJson(),
    });

    await tester.pumpWidget(_app(adapter));
    await tester.pumpAndSettle();

    // The order itself must load.
    expect(find.text('DRIVER ASSIGNED'), findsOneWidget);

    // Timeline entries from /orders/{id}/history must be shown.
    expect(find.text('Order accepted'), findsOneWidget);
    expect(find.text('Payment captured'), findsOneWidget);

    // Scroll to the Updates section: notifications for this order must be
    // rendered, not the "no notifications" empty state.
    await tester.dragUntilVisible(
      find.text('Updates'),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    expect(find.text('No notifications yet.'), findsNothing);
    expect(find.text('Driver on the way'), findsOneWidget);
  });
}