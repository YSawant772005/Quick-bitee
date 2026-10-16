import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickbite/shared/widgets.dart';

/// A narrow strip of many wide chips: wider than its box, so it must scroll.
Widget _app(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 220, child: child),
        ),
      ),
    );

Widget _chips([int count = 20]) => Row(
      children: [
        for (var i = 0; i < count; i++)
          Container(
            width: 90,
            height: 40,
            alignment: Alignment.center,
            child: Text('Chip $i'),
          ),
      ],
    );

ScrollController _controllerOf(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(find.descendant(
      of: find.byType(HorizontalChipScroller),
      matching: find.byType(SingleChildScrollView),
    ))
    .controller!;

void main() {
  testWidgets(
      'the category strip is horizontally scrollable with the mouse wheel',
      (tester) async {
    await tester.pumpWidget(_app(HorizontalChipScroller(child: _chips())));
    await tester.pumpAndSettle();

    final controller = _controllerOf(tester);
    expect(controller.offset, 0,
        reason: 'the strip starts at the first category');

    // Every category is present in the tree, even the ones past the edge.
    expect(find.text('Chip 19'), findsOneWidget);

    // A plain mouse wheel emits a *vertical* delta; the strip must still move
    // horizontally so categories past the right edge become reachable.
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(find.byType(HorizontalChipScroller)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0));
    expect(controller.offset,
        lessThanOrEqualTo(controller.position.maxScrollExtent));
  });

  testWidgets('the strip can be scrolled back to the start', (tester) async {
    await tester.pumpWidget(_app(HorizontalChipScroller(child: _chips())));
    await tester.pumpAndSettle();

    final controller = _controllerOf(tester);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('Chip 19'), findsOneWidget);

    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
  });
}
