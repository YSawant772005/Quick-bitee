import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quickbite/core/api_client.dart';
import 'package:quickbite/features/explore/explore_screen.dart';
import 'package:quickbite/features/home/home_screen.dart';
import 'package:quickbite/features/menu/menu_screen.dart';
import 'package:quickbite/shared/paged_list.dart';
import 'package:quickbite/state/auth_controller.dart';

/// A stub catalogue with enough rows to exercise real paging:
/// * `/dishes` is paged by the backend (60 dishes, 24 per page).
/// * `/restaurants/{id}/menu` returns 30 rows in one page (client-sliced).
class _PagingAdapter implements HttpClientAdapter {
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
    if (path == '/dishes') {
      const total = 60;
      const perPage = 24;
      final start = (page - 1) * perPage;
      final items = <Map<String, dynamic>>[];
      for (var i = start; i < (start + perPage).clamp(0, total); i++) {
        items.add({
          'id': 'dish-${i + 1}',
          'restaurant_id': 'r-1',
          'restaurant_name': 'First House',
          'name': 'Dish ${i + 1}',
          'description': 'A dish for paging tests.',
          'price_minor': 10000 + i,
          'currency': 'INR',
          'image_url': '',
          'available': true,
        });
      }
      body = {
        'items': items,
        'page': page,
        'page_size': perPage,
        'total': total,
      };
    } else if (path == '/restaurants') {
      // 30 restaurants returned in one API page; the home screen slices them.
      final items = <Map<String, dynamic>>[
        for (var i = 0; i < 30; i++)
          {
            'id': 'r-${i + 1}',
            'name': 'House ${i + 1}',
            'description': 'A restaurant for paging tests.',
            'cuisine': 'Cafe',
            'image_url': '',
            'available': true,
          },
      ];
      body = {
        'items': items,
        'page': page,
        'page_size': 100,
        'total': items.length,
      };
    } else if (path.startsWith('/restaurants/r-1/menu')) {
      // 30 rows in a single API page; the screen slices them client-side.
      final items = <Map<String, dynamic>>[
        for (var i = 0; i < 30; i++)
          {
            'id': 'm-${i + 1}',
            'restaurant_id': 'r-1',
            'name': 'Menu Item ${i + 1}',
            'description': 'A menu row.',
            'price_minor': 15000 + i,
            'currency': 'INR',
            'image_url': '',
            'available': true,
          },
      ];
      body = {
        'items': items,
        'page': page,
        'page_size': 100,
        'total': items.length,
      };
    } else {
      body = {
        'items': <Map<String, dynamic>>[],
        'page': page,
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

Widget _app(Widget child) {
  final dio = Dio(BaseOptions(baseUrl: 'http://stub/api/v1'));
  dio.httpClientAdapter = _PagingAdapter();
  return ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(ApiClient(dio: dio))],
    child: MaterialApp(home: child),
  );
}

/// Same as [_app] but starts in numbered-pages mode (no automatic loading).
class _PaginationMode extends BrowseModeController {
  @override
  BrowseMode build() => BrowseMode.pagination;
}

Widget _appPaged(Widget child) {
  final dio = Dio(BaseOptions(baseUrl: 'http://stub/api/v1'));
  dio.httpClientAdapter = _PagingAdapter();
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(ApiClient(dio: dio)),
      browseModeProvider.overrideWith(_PaginationMode.new),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets(
      'Explore (dishes): infinite scroll shows Load more, then pagination '
      'numbers take over', (tester) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(const ExploreScreen(initialView: 'dishes')));
    await tester.pumpAndSettle();

    // Default mode is infinite scroll: the first page is shown and a
    // "Load more" affordance is offered.
    expect(find.text('Dish 1'), findsOneWidget);
    expect(find.text('Load more'), findsOneWidget);

    // Switch to numbered pages via the shared toggle.
    await tester.tap(find.text('Pages'));
    await tester.pumpAndSettle();

    expect(find.text('Page 1 of 3'), findsOneWidget);
    expect(find.textContaining('Showing 1–24 of 60'), findsOneWidget);
    expect(find.text('Dish 25'), findsNothing);

    // Next page replaces the visible rows.
    await tester.ensureVisible(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();

    expect(find.text('Page 2 of 3'), findsOneWidget);
    expect(find.text('Dish 1'), findsNothing);
    expect(find.text('Dish 25'), findsOneWidget);
  });

  testWidgets('Menu screen slices a long menu into numbered pages',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(const MenuScreen(restaurantId: 'r-1')));
    await tester.pumpAndSettle();

    // 30 menu rows, page size 24, infinite mode by default.
    expect(find.text('Menu Item 1'), findsOneWidget);
    expect(find.text('Load more'), findsOneWidget);

    await tester.tap(find.text('Pages'));
    await tester.pumpAndSettle();

    // Client-side slicing keeps the rows (no network round-trip needed).
    expect(find.text('Page 1 of 2'), findsOneWidget);
    expect(find.text('Menu Item 25'), findsNothing);

    await tester.ensureVisible(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 2'), findsOneWidget);
    expect(find.text('Menu Item 25'), findsOneWidget);
  });

  testWidgets('Home: the dish and restaurant sections page together',
      (tester) async {
    // Tall viewport so both listing sections are instantiated by the lazy
    // ListView; start in pagination mode so nothing auto-loads.
    tester.view.physicalSize = const Size(900, 3400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_appPaged(const HomeScreen()));
    await tester.pumpAndSettle();

    // Dishes section — backend paginated (server sends 24/page, total 60).
    expect(find.text('Dish 1'), findsOneWidget);
    expect(find.text('Showing 1–24 of 60'), findsOneWidget);

    // The list is lazy, so scroll down to the restaurants section, which is
    // sliced client-side (12/page, total 30).
    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pumpAndSettle();

    expect(find.text('Restaurants near you'), findsOneWidget);
    expect(find.text('House 1'), findsOneWidget);
    expect(find.text('Showing 1–12 of 30'), findsOneWidget);
  });

  testWidgets('Home exposes a single browse-mode toggle for both sections',
      (tester) async {
    tester.view.physicalSize = const Size(900, 3400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_appPaged(const HomeScreen()));
    await tester.pumpAndSettle();

    // One shared control, not one per section.
    expect(find.byType(BrowseModeToggle), findsOneWidget);
    expect(find.text('Browse dishes & restaurants'), findsOneWidget);
    expect(find.text('Popular right now'), findsOneWidget);

    // The same control sits above the restaurant section further down.
    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pumpAndSettle();
    expect(find.text('Restaurants near you'), findsOneWidget);
  });

  testWidgets('the browse mode carries between screens via the provider',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final dio = Dio(BaseOptions(baseUrl: 'http://stub/api/v1'));
    dio.httpClientAdapter = _PagingAdapter();
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(ApiClient(dio: dio)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ExploreScreen(initialView: 'dishes'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to pages, then confirm the shared provider reflects it.
    await tester.tap(find.text('Pages'));
    await tester.pumpAndSettle();
    expect(container.read(browseModeProvider), BrowseMode.pagination);
  });
}
