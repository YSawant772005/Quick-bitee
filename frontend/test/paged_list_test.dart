import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quickbite/models/models.dart';
import 'package:quickbite/shared/paged_list.dart';

/// Builds a [Paginated] page of ints out of [all] with the given page size.
Paginated<int> _page(List<int> all, int page, int pageSize) {
  final start = (page - 1) * pageSize;
  final end = (start + pageSize).clamp(0, all.length);
  return Paginated(
    items: start >= all.length ? const [] : all.sublist(start, end),
    page: page,
    pageSize: pageSize,
    total: all.length,
  );
}

void main() {
  group('PagedListController (backend fetch)', () {
    test('refresh loads the first page and reports totals', () async {
      final all = List.generate(25, (i) => i + 1);
      final controller = PagedListController<int>(
        fetch: (page, pageSize) async => _page(all, page, pageSize),
        idOf: (i) => '$i',
        pageSize: 10,
      );

      await controller.refresh();

      expect(controller.items, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      expect(controller.total, 25);
      expect(controller.totalPages, 3);
      expect(controller.page, 1);
      expect(controller.hasMore, isTrue);
      expect(controller.isPaged, isTrue);
      expect(controller.rangeStart, 1);
      expect(controller.rangeEnd, 10);
      expect(controller.error, isNull);
    });

    test('loadMore appends the next page and never duplicates rows', () async {
      final all = List.generate(25, (i) => i + 1);
      final controller = PagedListController<int>(
        fetch: (page, pageSize) async => _page(all, page, pageSize),
        idOf: (i) => '$i',
        pageSize: 10,
      );
      await controller.refresh();
      await controller.loadMore();

      expect(controller.items.length, 20);
      expect(controller.items.first, 1);
      expect(controller.items.last, 20);
      expect(controller.page, 2);
      expect(controller.hasMore, isTrue);
    });

    test('stops at the last page (no further requests)', () async {
      var calls = 0;
      final all = List.generate(15, (i) => i + 1);
      final controller = PagedListController<int>(
        fetch: (page, pageSize) async {
          calls++;
          return _page(all, page, pageSize);
        },
        idOf: (i) => '$i',
        pageSize: 10,
      );
      await controller.refresh();
      await controller.loadMore();
      await controller.loadMore(); // no-op: no more pages

      expect(calls, 2);
      expect(controller.items.length, 15);
      expect(controller.hasMore, isFalse);
    });

    test('goToPage replaces the current page', () async {
      final all = List.generate(25, (i) => i + 1);
      final controller = PagedListController<int>(
        fetch: (page, pageSize) async => _page(all, page, pageSize),
        idOf: (i) => '$i',
        pageSize: 10,
      );
      await controller.refresh();
      await controller.goToPage(3);

      expect(controller.page, 3);
      expect(controller.items, [21, 22, 23, 24, 25]);
      expect(controller.rangeStart, 21);
      expect(controller.rangeEnd, 25);
      expect(controller.hasMore, isFalse);
    });

    test('a failed refresh surfaces an error and clears the list', () async {
      final controller = PagedListController<int>(
        fetch: (page, pageSize) async =>
            throw ApiException(500, 'server_error', 'boom'),
        idOf: (i) => '$i',
        pageSize: 10,
      );
      await controller.refresh();

      expect(controller.error, 'boom');
      expect(controller.items, isEmpty);
      expect(controller.isEmpty, isTrue);
      expect(controller.loading, isFalse);
    });

    test('a failed loadMore keeps the rows and exposes moreError', () async {
      final all = List.generate(25, (i) => i + 1);
      var failNext = false;
      final controller = PagedListController<int>(
        fetch: (page, pageSize) async {
          if (failNext) throw ApiException(500, 'server_error', 'nope');
          return _page(all, page, pageSize);
        },
        idOf: (i) => '$i',
        pageSize: 10,
      );
      await controller.refresh();
      failNext = true;
      await controller.loadMore();

      expect(controller.items.length, 10);
      expect(controller.moreError, 'nope');
      expect(controller.page, 1);
    });
  });

  group('PagedListController (client-side slice)', () {
    test('setLocalItems slices without any async work', () {
      final all = List.generate(25, (i) => i + 1);
      final controller = PagedListController<int>(
        local: const [],
        idOf: (i) => '$i',
        pageSize: 10,
      );
      controller.setLocalItems(all);

      expect(controller.items, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      expect(controller.total, 25);
      expect(controller.totalPages, 3);
      expect(controller.loading, isFalse);
      expect(controller.hasMore, isTrue);
    });

    test('loadMore appends the next local slice and goToPage hops', () {
      final all = List.generate(25, (i) => i + 1);
      final controller = PagedListController<int>(
        local: all,
        idOf: (i) => '$i',
        pageSize: 10,
      );
      controller.setLocalItems(all);
      controller.goToPage(2);
      expect(controller.items, [11, 12, 13, 14, 15, 16, 17, 18, 19, 20]);
      expect(controller.page, 2);

      controller.loadMore();
      expect(controller.items.length, 15);
      expect(controller.items.last, 25);
    });

    test('setLocalItems resets to the first page by default', () {
      final controller = PagedListController<int>(
        local: List.generate(25, (i) => i + 1),
        idOf: (i) => '$i',
        pageSize: 10,
      );
      controller.setLocalItems(List.generate(25, (i) => i + 1));
      controller.goToPage(3);
      expect(controller.page, 3);

      controller.setLocalItems(List.generate(7, (i) => i + 1));
      expect(controller.page, 1);
      expect(controller.total, 7);
      expect(controller.totalPages, 1);
      expect(controller.items, [1, 2, 3, 4, 5, 6, 7]);
    });
  });

  group('pageNumberWindow', () {
    test('lists every page when there are few', () {
      expect(pageNumberWindow(1, 5), [1, 2, 3, 4, 5]);
    });

    test('inserts an ellipsis gap in the middle of a long range', () {
      expect(pageNumberWindow(10, 20), [1, null, 9, 10, 11, null, 20]);
    });

    test('keeps the first and last page visible', () {
      final window = pageNumberWindow(1, 20);
      expect(window.first, 1);
      expect(window.last, 20);
      expect(window.contains(null), isTrue);
    });
  });

  group('BrowseModeToggle', () {
    testWidgets('switches the session-wide browse mode', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: Center(child: BrowseModeToggle())),
          ),
        ),
      );

      expect(container.read(browseModeProvider), BrowseMode.infinite);
      // Tap the "Numbered pages" option.
      await tester.tap(find.text('Numbered pages'));
      await tester.pumpAndSettle();
      expect(container.read(browseModeProvider), BrowseMode.pagination);
    });
  });

  group('PagedResultsFooter', () {
    testWidgets('pagination mode shows the numbered controls', (tester) async {
      final all = List.generate(25, (i) => i + 1);
      final controller = PagedListController<int>(
        local: all,
        idOf: (i) => '$i',
        pageSize: 10,
      );
      controller.setLocalItems(all);
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PagedResultsFooter(
            controller: controller,
            mode: BrowseMode.pagination,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Showing 1–10 of 25'), findsOneWidget);
      expect(find.text('Page 1 of 3'), findsOneWidget);

      // Next page button advances.
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(controller.page, 2);
      expect(find.text('Page 2 of 3'), findsOneWidget);
    });

    testWidgets('infinite mode shows Load more then the end marker',
        (tester) async {
      final all = List.generate(15, (i) => i + 1);
      final controller = PagedListController<int>(
        local: all,
        idOf: (i) => '$i',
        pageSize: 10,
      );
      controller.setLocalItems(all);
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PagedResultsFooter(
            controller: controller,
            mode: BrowseMode.infinite,
            endLabel: 'All done',
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Load more'), findsOneWidget);
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      expect(controller.items.length, 15);
      expect(find.text('All done'), findsOneWidget);
    });

    testWidgets('a single short list renders nothing', (tester) async {
      final controller = PagedListController<int>(
        local: const [1, 2, 3],
        idOf: (i) => '$i',
        pageSize: 10,
      );
      controller.setLocalItems(const [1, 2, 3]);
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PagedResultsFooter(
            controller: controller,
            mode: BrowseMode.infinite,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Load more'), findsNothing);
      expect(find.textContaining('reached the end'), findsNothing);
    });
  });
}
