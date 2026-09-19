import 'bus_arrivals.dart';
import 'trip_cards.dart';

class TripBoarding {
  const TripBoarding(
    this.service,
    this.arrival, {
    required this.connectionChecked,
  });
  final String service;
  final BusArrival arrival;
  // False means only a prediction at the stop, not a catchable connection.
  final bool connectionChecked;
}

class TripForecast {
  const TripForecast({
    required this.boardings,
    required this.arrivalAtDestination,
  });
  final Map<int, TripBoarding> boardings;
  final DateTime? arrivalAtDestination;

  factory TripForecast.calculate(
    TripPlan plan,
    Map<String, StopArrivalsSnapshot> stops,
    DateTime now,
  ) {
    DateTime? ready = now;
    var busesSeen = 0;
    final boardings = <int, TripBoarding>{};
    for (var index = 0; index < plan.legs.length; index++) {
      final leg = plan.legs[index];
      final duration = leg.durationMinutes;
      if (!leg.isBus) {
        ready = ready != null && duration != null
            ? ready.add(Duration(minutes: duration))
            : null;
        continue;
      }
      if (busesSeen > 0 && ready != null) {
        ready = ready.add(const Duration(minutes: 2));
      }
      busesSeen++;
      final snapshot = stops[leg.from.code];
      final choices = <TripBoarding>[];
      if (snapshot != null && !snapshot.isStale(now)) {
        final allowed = leg.services
            .map(normalizeBusService)
            .whereType<String>()
            .toSet();
        for (final route in snapshot.routes.where(
          (route) => allowed.contains(route.serviceNumber),
        )) {
          for (final arrival in route.arrivals) {
            if (arrival.estimatedArrival.isBefore(ready ?? now)) continue;
            choices.add(
              TripBoarding(
                route.serviceNumber,
                arrival,
                connectionChecked: ready != null,
              ),
            );
          }
        }
      }
      choices.sort(
        (a, b) =>
            a.arrival.estimatedArrival.compareTo(b.arrival.estimatedArrival),
      );
      final next = choices.firstOrNull;
      if (next != null) boardings[index] = next;
      ready = next != null && ready != null && duration != null
          ? next.arrival.estimatedArrival.add(Duration(minutes: duration))
          : null;
    }
    return TripForecast(boardings: boardings, arrivalAtDestination: ready);
  }
}
