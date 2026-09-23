import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuttle_bus/schedule.dart';
import 'package:shuttle_bus/screens/schedule_screen.dart';

void main() {
  tearDown(BusSchedule.resetForTests);

  Color? departureBackground(WidgetTester tester, String time) {
    final departure = find.byKey(ValueKey('schedule-departure-$time'));
    final tile = tester.widget<AnimatedContainer>(departure);
    return (tile.decoration! as BoxDecoration).color;
  }

  Future<void> pumpSchedule(
    WidgetTester tester, {
    required DateTime now,
    Direction direction = Direction.forettToBeautyWorld,
    bool isActive = true,
    bool disableAnimations = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: ScheduleScreen(
            isActive: isActive,
            direction: direction,
            now: () => now,
            onDirectionChanged: (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('centres and highlights the next Forett departure', (
    tester,
  ) async {
    await pumpSchedule(tester, now: DateTime(2026, 9, 14, 11, 50));
    await tester.pumpAndSettle();

    expect(departureBackground(tester, '12:00'), isNot(Colors.transparent));
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('schedule-departure-12:00')))
          .dy,
      lessThan(450),
    );
  });

  testWidgets('uses the selected direction when finding the next departure', (
    tester,
  ) async {
    await pumpSchedule(
      tester,
      now: DateTime(2026, 9, 14, 6, 30, 1),
      direction: Direction.beautyWorldToForett,
    );
    await tester.pumpAndSettle();

    expect(departureBackground(tester, '06:37'), isNot(Colors.transparent));
  });

  testWidgets('focuses only after Schedule becomes active', (tester) async {
    final now = DateTime(2026, 9, 14, 6);
    await pumpSchedule(tester, now: now, isActive: false);
    await tester.pumpAndSettle();
    expect(departureBackground(tester, '06:30'), Colors.transparent);

    await pumpSchedule(tester, now: now);
    await tester.pumpAndSettle();
    expect(departureBackground(tester, '06:30'), isNot(Colors.transparent));
  });

  testWidgets('refocuses when the direction changes while Schedule is open', (
    tester,
  ) async {
    final now = DateTime(2026, 9, 14, 6, 30, 1);
    await pumpSchedule(tester, now: now);
    await tester.pumpAndSettle();
    expect(departureBackground(tester, '06:50'), isNot(Colors.transparent));

    await pumpSchedule(
      tester,
      now: now,
      direction: Direction.beautyWorldToForett,
    );
    await tester.pumpAndSettle();

    expect(departureBackground(tester, '06:37'), isNot(Colors.transparent));
  });

  testWidgets('refocuses after the active timetable changes', (tester) async {
    await pumpSchedule(tester, now: DateTime(2026, 9, 14, 12, 40, 1));
    await tester.pumpAndSettle();
    expect(departureBackground(tester, '14:30'), isNot(Colors.transparent));

    await BusSchedule.save(
      ShuttleSchedule.original().copyWith(forettTimes: ['12:41', '14:30']),
    );
    await tester.pumpAndSettle();

    expect(departureBackground(tester, '12:41'), isNot(Colors.transparent));
  });

  testWidgets('blinks the next row twice then leaves a soft highlight', (
    tester,
  ) async {
    await pumpSchedule(tester, now: DateTime(2026, 9, 14, 6));
    final departure = find.byKey(const ValueKey('schedule-departure-06:30'));
    final colors = Theme.of(tester.element(departure)).colorScheme;
    var wasBright = false;
    var brightPeaks = 0;

    for (var index = 0; index < 100; index++) {
      await tester.pump(const Duration(milliseconds: 25));
      final color = departureBackground(tester, '06:30')!;
      final isBright = color.a > 0.75;
      if (isBright && !wasBright) brightPeaks++;
      wasBright = isBright;
    }

    expect(brightPeaks, 2);
    expect(
      departureBackground(tester, '06:30'),
      colors.primaryContainer.withValues(alpha: 0.45),
    );
  });

  testWidgets('skips movement and blinking when animations are disabled', (
    tester,
  ) async {
    await pumpSchedule(
      tester,
      now: DateTime(2026, 9, 14, 6),
      disableAnimations: true,
    );
    await tester.pump();
    await tester.pump();

    expect(tester.hasRunningAnimations, isFalse);
    final departure = find.byKey(const ValueKey('schedule-departure-06:30'));
    final colors = Theme.of(tester.element(departure)).colorScheme;
    expect(
      departureBackground(tester, '06:30'),
      colors.primaryContainer.withValues(alpha: 0.45),
    );
  });

  testWidgets('does not highlight a departure after service has ended', (
    tester,
  ) async {
    await pumpSchedule(tester, now: DateTime(2026, 9, 14, 19, 20, 1));
    await tester.pumpAndSettle();

    expect(departureBackground(tester, '19:20'), Colors.transparent);
    expect(
      tester
          .getBottomLeft(find.byKey(const ValueKey('schedule-departure-19:20')))
          .dy,
      lessThanOrEqualTo(
        tester.view.physicalSize.height / tester.view.devicePixelRatio,
      ),
    );
  });

  testWidgets('does not highlight a departure on a non-operating day', (
    tester,
  ) async {
    await pumpSchedule(tester, now: DateTime(2026, 9, 13, 10));
    await tester.pumpAndSettle();

    expect(departureBackground(tester, '06:30'), Colors.transparent);
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('schedule-departure-06:30')))
          .dy,
      greaterThanOrEqualTo(0),
    );
  });
}
