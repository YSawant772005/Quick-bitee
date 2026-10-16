import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickbite/core/api_client.dart';
import 'package:quickbite/features/menu/menu_screen.dart';
import 'package:quickbite/features/offers/offers_screen.dart';
import 'package:quickbite/models/models.dart';
import 'package:quickbite/shared/promo_carousel.dart';
import 'package:quickbite/state/auth_controller.dart';

Map<String, dynamic> _restaurant() => {
      'id': 'r-detail',
      'name': 'Spice Route',
      'description': 'A neighbourhood kitchen with a full menu.',
      'cuisine': 'North Indian',
      'image_url': '',
      'available': true,
      'address': '42 Demo Lane, Bengaluru',
      'opening_hours': '9:00 AM – 11:00 PM',
      'eta_minutes_min': 25,
      'eta_minutes_max': 40,
      'rating': 4.5,
      'review_count': 12,
      'order_count': 130,
      'dish_count': 2,
      'categories': ['Biryani', 'North Indian'],
      'offers': ['Free delivery week'],
    };

Map<String, dynamic> _menuItem(String id, String name, bool? isVeg, int price,
        List<Map<String, dynamic>> tags) =>
    {
      'id': id,
      'restaurant_id': 'r-detail',
      'name': name,
      'description': 'Cooked fresh to order.',
      'price_minor': price,
      'currency': 'INR',
      'image_url': '',
      'available': true,
      'is_veg': isVeg,
      'tags': tags,
      'order_count': 3,
    };

Map<String, dynamic> _promotions() => {
      'banners': [
        {
          'id': 'welcome',
          'title': 'Welcome to QuickBitee',
          'subtitle': 'Hot meals, delivered fast.',
          'image_url': '',
          'cta_label': 'Browse restaurants',
          'target': '/explore',
          'badge': 'Demo offer',
          'is_demo': true,
        },
        {
          'id': 'veg',
          'title': 'Fresh vegetarian picks',
          'subtitle': 'Meat-free favourites.',
          'image_url': '',
          'cta_label': 'Explore vegetarian',
          'target': '/explore?food_type=veg&view=dishes',
          'badge': 'Demo offer',
          'is_demo': true,
        },
      ],
      'offers': [
        {
          'id': 'free-delivery',
          'title': 'Free delivery week',
          'description': 'Demo offer with no delivery fee advertised.',
          'kind': 'delivery',
          'image_url': '',
          'cta_label': 'Browse restaurants',
          'target': '/explore',
          'badge': 'Demo offer',
          'is_demo': true,
          'disclosure':
              'Demo promotion - it links to real browsing pages but applies no discount at checkout.',
        },
      ],
    };

/// Serves the restaurant detail, its menu and the promotions payload.
class _DetailsApi implements HttpClientAdapter {
  _DetailsApi({this.emptyOffers = false});

  final bool emptyOffers;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    final Object body;
    if (path == '/restaurants/r-detail/menu') {
      body = {
        'items': [
          _menuItem('m-1', 'Paneer Tikka', true, 22000, [
            {'slug': 'vegetarian', 'name': 'Vegetarian', 'kind': 'global'},
            {'slug': 'starters', 'name': 'Starters', 'kind': 'menu'},
          ]),
          _menuItem('m-2', 'Chicken Biryani', false, 32000, [
            {'slug': 'non-vegetarian', 'name': 'Non-Vegetarian', 'kind': 'global'},
            {'slug': 'biryani', 'name': 'Biryani', 'kind': 'global'},
          ]),
        ],
        'page': 1,
        'page_size': 100,
        'total': 2,
      };
    } else if (path == '/restaurants/r-detail') {
      body = _restaurant();
    } else if (path == '/restaurants') {
      body = {
        'items': [_restaurant()],
        'page': 1,
        'page_size': 100,
        'total': 1,
      };
    } else if (path == '/promotions') {
      final promo = _promotions();
      if (emptyOffers) promo['offers'] = <Map<String, dynamic>>[];
      body = promo;
    } else {
      body = {
        'items': <Map<String, dynamic>>[],
        'page': 1,
        'page_size': 100,
        'total': 0,
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

Widget _app(Widget child, {bool emptyOffers = false}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://stub/api/v1'));
  dio.httpClientAdapter = _DetailsApi(emptyOffers: emptyOffers);
  return ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(ApiClient(dio: dio))],
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('restaurant detail shows real facts, rating and offers',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(const MenuScreen(restaurantId: 'r-detail')));
    await tester.pumpAndSettle();

    expect(find.text('Spice Route'), findsWidgets);
    expect(find.textContaining('42 Demo Lane'), findsOneWidget);
    expect(find.textContaining('9:00 AM'), findsOneWidget);
    expect(find.textContaining('25–40 min'), findsOneWidget);
    expect(find.text('4.5 · 12 reviews'), findsOneWidget);
    expect(find.text('Free delivery week'), findsOneWidget);
    expect(find.text('Paneer Tikka'), findsOneWidget);
    expect(find.text('Chicken Biryani'), findsOneWidget);
  });

  testWidgets('menu filters combine and reset restores every dish',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(const MenuScreen(restaurantId: 'r-detail')));
    await tester.pumpAndSettle();

    // Veg filter narrows the list.
    await tester.tap(find.text('Veg'));
    await tester.pumpAndSettle();
    expect(find.text('Paneer Tikka'), findsOneWidget);
    expect(find.text('Chicken Biryani'), findsNothing);

    // Search + food type combine to a genuine "no match".
    final menuSearch = find.byWidgetPredicate((w) =>
        w is TextField && w.decoration?.hintText == 'Search this menu…');
    await tester.enterText(menuSearch, 'chicken');
    await tester.pumpAndSettle();
    expect(find.text('No dishes match your filters'), findsOneWidget);

    // Reset clears every filter.
    final reset = find.widgetWithText(FilledButton, 'Reset filters');
    await tester.ensureVisible(reset);
    await tester.pumpAndSettle();
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(find.text('Paneer Tikka'), findsOneWidget);
    expect(find.text('Chicken Biryani'), findsOneWidget);
  });

  testWidgets('promo carousel shows banners, honours next/prev',
      (tester) async {
    PromoCarousel.autoAdvance = false;
    addTearDown(() => PromoCarousel.autoAdvance = true);

    final banners = (_promotions()['banners'] as List)
        .map((b) => PromoBanner.fromJson((b as Map).cast<String, dynamic>()))
        .toList();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PromoCarousel(banners: banners)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to QuickBitee'), findsOneWidget);
    expect(find.byTooltip('Next promotion'), findsOneWidget);
    expect(find.textContaining('apply no discount at checkout'),
        findsOneWidget);

    await tester.tap(find.byTooltip('Next promotion'));
    await tester.pumpAndSettle();
    final page = tester.widget<PageView>(find.byType(PageView)).controller;
    expect(page!.page, closeTo(1, 0.001));
  });

  testWidgets('offers page prints the demo disclosure and links out',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(const OffersScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Free delivery week'), findsOneWidget);
    expect(find.text('Demo offer'), findsOneWidget);
    expect(find.textContaining('applies no discount at checkout'),
        findsOneWidget);
    expect(find.text('Browse restaurants'), findsOneWidget);
  });

  testWidgets('offers page says so honestly when nothing is configured',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(const OffersScreen(), emptyOffers: true));
    await tester.pumpAndSettle();

    expect(find.text('No offers right now'), findsOneWidget);
  });
}
