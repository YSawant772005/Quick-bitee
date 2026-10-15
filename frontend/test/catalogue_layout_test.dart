import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quickbite/core/api_client.dart';
import 'package:quickbite/features/explore/explore_screen.dart';
import 'package:quickbite/features/menu/menu_screen.dart';
import 'package:quickbite/state/auth_controller.dart';

class _CatalogueAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final page =
        int.tryParse(options.queryParameters['page']?.toString() ?? '1') ?? 1;
    final path = options.path;
    late final Map<String, dynamic> body;

    if (path == '/restaurants') {
      final restaurant =
          (id: 'r-$page', name: page == 1 ? 'First House' : 'Second House');
      body = {
        'items': [
          {
            'id': restaurant.id,
            'name': restaurant.name,
            'description': 'A restaurant with a complete menu.',
            'cuisine': 'Cafe',
            'image_url': '',
            'available': true,
          }
        ],
        'page': page,
        'page_size': 100,
        'total': 101,
      };
    } else if (path.startsWith('/restaurants/r-1/menu')) {
      body = {
        'items': [
          {
            'id': page == 1 ? 'dish-1' : 'dish-2',
            'restaurant_id': 'r-1',
            'name': page == 1 ? 'First-page Rice' : 'Second-page Noodles',
            'description': 'A dish that must remain visible after pagination.',
            'price_minor': 12000,
            'currency': 'INR',
            'image_url': '',
            'available': true,
          }
        ],
        'page': page,
        'page_size': 100,
        'total': 101,
      };
    } else {
      body = {
        'items': <Map<String, dynamic>>[],
        'page': page,
        'page_size': 100,
        'total': 0
      };
    }

    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Widget _app(Widget child) {
  final dio = Dio(BaseOptions(baseUrl: 'http://stub/api/v1'));
  dio.httpClientAdapter = _CatalogueAdapter();
  return ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(ApiClient(dio: dio))],
    child: MaterialApp(home: child),
  );
}

void main() {
  for (final size in [const Size(1440, 900), const Size(800, 600)]) {
    testWidgets(
        'catalogue content remains visible at ${size.width}x${size.height}',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(const ExploreScreen()));
      await tester.pumpAndSettle();

      expect(find.text('First House'), findsOneWidget);
      expect(find.text('Second House'), findsOneWidget);
    });
  }

  testWidgets('restaurant menu loads items beyond the first API page',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(const MenuScreen(restaurantId: 'r-1')));
    await tester.pumpAndSettle();

    expect(find.text('Second-page Noodles'), findsOneWidget);
    expect(find.textContaining('1 dish'), findsNothing);
  });
}
