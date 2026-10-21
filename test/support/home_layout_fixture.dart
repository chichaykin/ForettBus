import 'package:flutter/material.dart';
import 'package:shuttle_bus/bus_arrivals.dart';
import 'package:shuttle_bus/schedule.dart';
import 'package:shuttle_bus/screens/home_screen.dart';
import 'package:shuttle_bus/trip_cards.dart';
import 'package:timezone/timezone.dart' as tz;

import 'trip_fixtures.dart';

final homePreviewTime = tz.TZDateTime(
  BusSchedule.singaporeLocation,
  2026,
  10,
  21,
  8,
  50,
  12,
);

class PreviewPublicArrivals implements BusArrivalsRepository {
  @override
  bool get isConfigured => true;

  @override
  Future<BusArrivalsSnapshot> fetch(Direction direction) async =>
      BusArrivalsSnapshot(
        direction: direction,
        stop: BusStopConfig.forDirection(direction),
        fetchedAt: homePreviewTime,
        routes: [
          for (final service in ['41', '77'])
            BusRouteArrivals(
              serviceNumber: service,
              arrivals: [
                for (final minutes in [4, 12, 25])
                  BusArrival(
                    estimatedArrival: homePreviewTime.add(
                      Duration(minutes: minutes),
                    ),
                    monitored: minutes != 25,
                  ),
              ],
            ),
        ],
      );
}

class PreviewTripArrivals extends HttpBusStopArrivalsRepository {
  @override
  bool get isConfigured => true;

  @override
  Future<StopArrivalsSnapshot> fetch(String code) async =>
      tripSnapshots(homePreviewTime)[code]!;
}

/// Uses synthetic data and mock preferences only; never install as the app.
class HomeLayoutPreview extends StatefulWidget {
  const HomeLayoutPreview({
    super.key,
    required this.controller,
    required this.tripRepository,
    this.brightness = Brightness.light,
    this.textScale = 1,
  });

  final TripCardsController controller;
  final PreviewTripArrivals tripRepository;
  final Brightness brightness;
  final double textScale;

  @override
  State<HomeLayoutPreview> createState() => _HomeLayoutPreviewState();
}

class _HomeLayoutPreviewState extends State<HomeLayoutPreview> {
  Direction direction = Direction.forettToBeautyWorld;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      colorScheme: ColorScheme.fromSeed(
        seedColor: widget.brightness == Brightness.dark
            ? const Color(0xFF81C784)
            : const Color(0xFF2E7D32),
        brightness: widget.brightness,
      ),
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(widget.textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: HomeScreen(
        clock: () => homePreviewTime,
        direction: direction,
        onDirectionChanged: (value) => setState(() => direction = value),
        tripCardsController: widget.controller,
        arrivalRepository: PreviewPublicArrivals(),
        tripArrivalRepository: widget.tripRepository,
      ),
      bottomNavigationBar: NavigationBar(
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            label: 'Schedule',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    ),
  );
}
