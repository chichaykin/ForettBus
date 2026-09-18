import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shuttle_bus/bus_arrivals.dart';
import 'package:shuttle_bus/main.dart';
import 'package:shuttle_bus/schedule.dart';
import 'package:shuttle_bus/screens/home_screen.dart';

class _UnavailableArrivalsRepository implements BusArrivalsRepository {
  @override
  bool get isConfigured => true;

  @override
  Future<BusArrivalsSnapshot> fetch(Direction direction) {
    throw const BusArrivalsException(
      BusArrivalsErrorType.unauthorized,
      'secret upstream detail',
    );
  }
}

class _LiveArrivalsRepository implements BusArrivalsRepository {
  _LiveArrivalsRepository(this.snapshot);

  final BusArrivalsSnapshot snapshot;

  @override
  bool get isConfigured => true;

  @override
  Future<BusArrivalsSnapshot> fetch(Direction direction) async => snapshot;
}

void main() {
  testWidgets('launches the shuttle app and navigates between tabs', (
    tester,
  ) async {
    await tester.pumpWidget(const ShuttleBusApp());
    await tester.pump();

    expect(find.text('To Beauty World'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);

    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();

    expect(find.text('Full Schedule'), findsOneWidget);
    expect(find.text('06:30'), findsOneWidget);

    await tester.tap(find.text('To Forett'));
    await tester.pumpAndSettle();

    expect(find.text('06:37'), findsOneWidget);
    expect(find.text('06:30'), findsNothing);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Resident'), findsOneWidget);
    expect(find.text('Management Office'), findsOneWidget);
  });

  testWidgets('profile controls and support contacts are usable', (
    tester,
  ) async {
    await tester.pumpWidget(const ShuttleBusApp());
    await tester.pump();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('mo@forettcondo.sg'), findsOneWidget);
    expect(find.text('Light theme enabled'), findsOneWidget);

    final switches = find.byType(Switch);
    expect(switches, findsNWidgets(2));
    await tester.tap(switches.last);
    await tester.pumpAndSettle();
    expect(find.text('Dark theme enabled'), findsOneWidget);

    await tester.tap(find.text('Management Office'));
    await tester.pumpAndSettle();
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('60285615'), findsOneWidget);
  });

  testWidgets('live arrival failures fall back to scheduled times', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          onDirectionChanged: (_) {},
          arrivalRepository: _UnavailableArrivalsRepository(),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Live access unavailable · using Scheduled times'),
      findsOneWidget,
    );
    expect(find.textContaining('Scheduled'), findsWidgets);
    expect(find.text('Scheduled timetable'), findsOneWidget);
    expect(find.textContaining('in '), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('live arrivals show a countdown and exact arrival time', (
    tester,
  ) async {
    final now = BusSchedule.now();
    final arrival = now.add(const Duration(minutes: 5, seconds: 30));
    final snapshot = BusArrivalsSnapshot(
      direction: Direction.forettToBeautyWorld,
      stop: BusStopConfig.forDirection(Direction.forettToBeautyWorld),
      fetchedAt: now,
      routes: [
        BusRouteArrivals(
          serviceNumber: '41',
          arrivals: [BusArrival(estimatedArrival: arrival, monitored: true)],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          onDirectionChanged: (_) {},
          arrivalRepository: _LiveArrivalsRepository(snapshot),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('in 5 min'), findsOneWidget);
    expect(find.text('Live ETA'), findsOneWidget);
    expect(find.text(DateFormat('HH:mm').format(arrival)), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('stale live arrivals keep exact time without a countdown', (
    tester,
  ) async {
    final now = BusSchedule.now();
    final arrival = now.add(const Duration(minutes: 5));
    final snapshot = BusArrivalsSnapshot(
      direction: Direction.forettToBeautyWorld,
      stop: BusStopConfig.forDirection(Direction.forettToBeautyWorld),
      fetchedAt: now.subtract(const Duration(seconds: 60, milliseconds: 500)),
      routes: [
        BusRouteArrivals(
          serviceNumber: '41',
          arrivals: [BusArrival(estimatedArrival: arrival, monitored: true)],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          onDirectionChanged: (_) {},
          arrivalRepository: _LiveArrivalsRepository(snapshot),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Stale'), findsOneWidget);
    expect(find.textContaining('in '), findsNothing);
    expect(find.text(DateFormat('HH:mm').format(arrival)), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
