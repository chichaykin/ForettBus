import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuttle_bus/trip_cards.dart';
import 'package:shuttle_bus/widgets/trip_card_view.dart';
import 'package:shuttle_bus/screens/trip_cards_screen.dart';
import 'support/trip_fixtures.dart';

void main() {
  testWidgets(
    'compact card uses human labels, expands correct transfers and fits large text',
    (tester) async {
      final now = DateTime.parse('2026-09-19T13:00:00+08:00');
      tester.view.physicalSize = const Size(360, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: TripCardView(
                  card: testTripCard,
                  stops: tripSnapshots(now),
                  now: now,
                  onDirectionChanged: (_) {},
                  onEdit: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('To Grab HQ'), findsOneWidget);
      expect(find.text('To 138498'), findsNothing);
      expect(find.text('Bus 963'), findsOneWidget);
      expect(find.text('in 12 min'), findsOneWidget);
      expect(find.textContaining('TTS'), findsNothing);
      expect(find.text('Change to bus 41'), findsNothing);
      await tester.ensureVisible(find.text('Route details'));
      await tester.tap(find.text('Route details'));
      await tester.pumpAndSettle();
      expect(find.text('Change to bus 41'), findsOneWidget);
      expect(find.text('Change to bus 963'), findsNothing);
      expect(find.textContaining('Grab HQ → Science Pk'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('editor preserves durations on rename and save', (tester) async {
    TripCard? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await Navigator.of(context).push<TripCard>(
                MaterialPageRoute(
                  builder: (_) => const TripCardEditor(card: testTripCard),
                ),
              );
            },
            child: const Text('Edit'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Work');
    await tester.tap(find.text('Save').first);
    await tester.pumpAndSettle();
    expect(saved!.title, 'Work');
    expect(saved!.toOrigin.durationMinutes, 42);
    expect(saved!.toOrigin.legs.first.durationMinutes, 10);
  });
}
