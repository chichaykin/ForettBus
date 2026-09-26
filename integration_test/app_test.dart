import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuttle_bus/main.dart' as app;
import 'package:shuttle_bus/bus_arrivals.dart';
import 'package:shuttle_bus/schedule.dart';
import 'package:shuttle_bus/screens/home_screen.dart';
import 'package:shuttle_bus/trip_cards.dart';
import 'package:shuttle_bus/widgets/direction_toggle.dart';

import '../test/support/trip_fixtures.dart';

class _NoPublicLive implements BusArrivalsRepository {
  @override
  bool get isConfigured => false;
  @override
  Future<BusArrivalsSnapshot> fetch(Direction direction) =>
      throw UnimplementedError();
}

class _TripPredictions extends HttpBusStopArrivalsRepository {
  _TripPredictions(this.now);
  final DateTime now;
  @override
  bool get isConfigured => true;
  @override
  Future<StopArrivalsSnapshot> fetch(String code) async =>
      tripSnapshots(now)[code]!;
}

Future<void> _pumpUi(WidgetTester tester) async {
  // Home owns a one-second countdown timer, so pump a bounded duration instead
  // of waiting for the whole app to become idle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'home, schedule, directions and profile work; theme restores after restart',
    (tester) async {
      await app.main();
      await _pumpUi(tester);
      expect(find.text('Forett Shuttle'), findsOneWidget);
      expect(find.text('Public buses'), findsOneWidget);
      await tester.tap(find.text('Schedule').last);
      await _pumpUi(tester);
      expect(find.text('Full Schedule'), findsOneWidget);
      await tester.tap(find.text('To Forett'));
      await _pumpUi(tester);
      await tester.tap(find.text('Profile').last);
      await _pumpUi(tester);
      expect(find.text('Management Office'), findsOneWidget);
      expect(find.text('Back up app data'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Restore app data'), 200);
      await _pumpUi(tester);
      expect(find.text('Restore app data'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Dark Mode'), -200);
      await _pumpUi(tester);
      await tester.tap(find.byType(Switch).last);
      await _pumpUi(tester);
      expect(find.text('Dark theme enabled'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await app.main();
      await _pumpUi(tester);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      await tester.tap(find.text('Schedule').last);
      await _pumpUi(tester);
      expect(
        tester.widget<DirectionToggle>(find.byType(DirectionToggle)).direction,
        Direction.beautyWorldToForett,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('trip card on Pixel: ${brightness.name}', (tester) async {
      final preferences = await SharedPreferences.getInstance();
      final controller = TripCardsController(preferences: preferences);
      await controller.load();
      await controller.add(testTripCard);
      final now = BusSchedule.now();
      final repository = _TripPredictions(now);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: brightness == Brightness.dark
                  ? const Color(0xFF81C784)
                  : const Color(0xFF2E7D32),
              brightness: brightness,
            ),
          ),
          home: HomeScreen(
            onDirectionChanged: (_) {},
            tripCardsController: controller,
            arrivalRepository: _NoPublicLive(),
            tripArrivalRepository: repository,
          ),
        ),
      );
      await _pumpUi(tester);
      await tester.ensureVisible(find.text('Route details'));
      await _pumpUi(tester);
      expect(find.text('To Grab HQ'), findsOneWidget);
      expect(find.text('Bus 963'), findsOneWidget);
      expect(find.textContaining('TTS BUS'), findsNothing);
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await binding.takeScreenshot('trip-${brightness.name}');
      await tester.tap(find.text('Route details'));
      await _pumpUi(tester);
      await tester.ensureVisible(find.text('Change to bus 41'));
      await _pumpUi(tester);
      expect(find.text('Change to bus 41'), findsOneWidget);
      expect(find.text('Change to bus 963'), findsNothing);
      await binding.takeScreenshot('trip-${brightness.name}-details');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      repository.close();
    });
  }
}
