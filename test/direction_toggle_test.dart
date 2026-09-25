import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuttle_bus/schedule.dart';
import 'package:shuttle_bus/widgets/direction_toggle.dart';

void main() {
  testWidgets('selection slides in both directions after a tap', (
    tester,
  ) async {
    var direction = Direction.forettToBeautyWorld;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: StatefulBuilder(
                builder: (context, setState) => DirectionToggle(
                  direction: direction,
                  onChanged: (value) => setState(() => direction = value),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final indicator = find.byKey(const Key('direction-selection-indicator'));
    final left = tester.getTopLeft(indicator).dx;

    await tester.tap(find.text('To Forett'));
    await tester.pump();
    expect(direction, Direction.beautyWorldToForett);
    await tester.pump(const Duration(milliseconds: 140));
    final movingRight = tester.getTopLeft(indicator).dx;
    expect(movingRight, greaterThan(left));
    await tester.pumpAndSettle();
    final right = tester.getTopLeft(indicator).dx;
    expect(right, greaterThan(movingRight));

    await tester.tap(find.text('To Beauty World'));
    await tester.pump();
    expect(direction, Direction.forettToBeautyWorld);
    await tester.pump(const Duration(milliseconds: 140));
    final movingLeft = tester.getTopLeft(indicator).dx;
    expect(movingLeft, lessThan(right));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(indicator).dx, closeTo(left, 0.1));
    expect(tester.takeException(), isNull);
  });
}
