import 'package:shuttle_bus/bus_arrivals.dart';
import 'package:shuttle_bus/trip_cards.dart';

// Stops and service identifiers from OneMap's Grab HQ -> Forett itinerary.
// Times below are synthetic test predictions, never used by the installed app.
const office = TransitStop(code: 'origin', name: 'Origin');
const sciencePk = TransitStop(code: '18131', name: 'SCIENCE PK');
const transferStop = TransitStop(
  code: '28101',
  name: 'OPP SMRT ULU PANDAN DEPOT',
);
const forett = TransitStop(code: '42221', name: 'FORETT @ BT TIMAH');
const destination = TransitStop(code: 'destination', name: 'Destination');
const returnPlan = TripPlan(
  durationMinutes: 42,
  legs: [
    TripLeg(
      type: TripLegType.walk,
      from: office,
      to: sciencePk,
      durationMinutes: 10,
    ),
    TripLeg(
      type: TripLegType.bus,
      from: sciencePk,
      to: transferStop,
      services: ['963'],
      durationMinutes: 23,
    ),
    TripLeg(
      type: TripLegType.bus,
      from: transferStop,
      to: forett,
      services: ['41'],
      durationMinutes: 5,
    ),
    TripLeg(
      type: TripLegType.walk,
      from: forett,
      to: destination,
      durationMinutes: 1,
    ),
  ],
);
const testTripCard = TripCard(
  id: 'test-grab',
  title: 'Grab HQ',
  originName: 'Forett',
  destinationName: '138498',
  toDestination: returnPlan,
  toOrigin: returnPlan,
  selectedDirection: TripDirection.toOrigin,
);

StopArrivalsSnapshot stopSnapshot(
  DateTime now,
  String code,
  Map<String, List<int>> predictions, {
  int age = 0,
}) => StopArrivalsSnapshot(
  stopCode: code,
  fetchedAt: now.subtract(Duration(seconds: age)),
  routes: predictions.entries
      .map(
        (entry) => BusRouteArrivals(
          serviceNumber: entry.key,
          arrivals: entry.value
              .map(
                (minutes) => BusArrival(
                  estimatedArrival: now.add(Duration(minutes: minutes)),
                  monitored: true,
                ),
              )
              .toList(),
        ),
      )
      .toList(),
);

Map<String, StopArrivalsSnapshot> tripSnapshots(DateTime now) => {
  '18131': stopSnapshot(now, '18131', {
    '963': [4, 12, 25],
  }),
  '28101': stopSnapshot(now, '28101', {
    '41': [18, 36, 42],
  }),
};
