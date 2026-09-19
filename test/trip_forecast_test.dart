import 'package:flutter_test/flutter_test.dart';
import 'package:shuttle_bus/trip_cards.dart';
import 'package:shuttle_bus/trip_forecast.dart';
import 'support/trip_fixtures.dart';

void main() {
  final now = DateTime.parse('2026-09-19T23:50:00+08:00');
  test('allows walking time and two minutes to transfer, across midnight', () {
    final result = TripForecast.calculate(returnPlan, tripSnapshots(now), now);
    expect(
      result.boardings[1]!.arrival.estimatedArrival,
      now.add(const Duration(minutes: 12)),
    );
    // Bus arrives after 23 min; 36-minute prediction is too early with the buffer.
    expect(
      result.boardings[2]!.arrival.estimatedArrival,
      now.add(const Duration(minutes: 42)),
    );
    expect(result.arrivalAtDestination, now.add(const Duration(minutes: 48)));
  });

  test(
    'chooses earliest qualifying bus among alternatives, not first service',
    () {
      const plan = TripPlan(
        legs: [
          TripLeg(
            type: TripLegType.bus,
            from: sciencePk,
            to: forett,
            services: ['41', '77'],
            durationMinutes: 5,
          ),
        ],
      );
      final result = TripForecast.calculate(plan, {
        '18131': stopSnapshot(now, '18131', {
          '41': [15],
          '77': [7],
        }),
      }, now);
      expect(result.boardings[0]!.service, '77');
    },
  );

  test(
    'stale data and missed last connection do not promise destination arrival',
    () {
      final snapshots = tripSnapshots(now);
      snapshots['28101'] = stopSnapshot(now, '28101', {
        '41': [18, 36],
      });
      expect(
        TripForecast.calculate(returnPlan, snapshots, now).arrivalAtDestination,
        isNull,
      );
      snapshots['18131'] = stopSnapshot(now, '18131', {
        '963': [12],
      }, age: 61);
      final stale = TripForecast.calculate(returnPlan, snapshots, now);
      expect(stale.boardings[1], isNull);
      expect(stale.arrivalAtDestination, isNull);
      expect(stale.boardings[2]!.connectionChecked, isFalse);
    },
  );

  test(
    'legacy cards with no walking duration show stop ETA without claiming catchability',
    () {
      final legacy = TripPlan(
        legs: [
          const TripLeg(type: TripLegType.walk, from: office, to: sciencePk),
          ...returnPlan.legs.skip(1),
        ],
      );
      final result = TripForecast.calculate(legacy, tripSnapshots(now), now);
      expect(result.boardings[1]!.connectionChecked, isFalse);
      expect(result.arrivalAtDestination, isNull);
    },
  );
}
