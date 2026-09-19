import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shuttle_bus/trip_cards.dart';
import 'package:shuttle_bus/trip_planning.dart';

void main() {
  test(
    'parses OneMap routeId, durations and stop identifiers in Singapore time',
    () async {
      final client = TripPlannerClient(
        baseUrl: 'https://example.test',
        appApiKey: 'test',
        client: MockClient((request) async {
          final body = jsonDecode(request.body);
          expect(body['date'], '09-20-2026');
          expect(body['time'], '00:30:00');
          return http.Response(
            jsonEncode({
              'itineraries': [
                {
                  'duration': 900,
                  'legs': [
                    {
                      'mode': 'WALK',
                      'duration': 594,
                      'from': {'name': 'Origin'},
                      'to': {'name': 'SCIENCE PK', 'stopId': 'FERRY:18131'},
                    },
                    {
                      'mode': 'BUS',
                      'duration': 276,
                      'route': 'TTS BUS 963',
                      'routeId': '963',
                      'from': {'name': 'SCIENCE PK', 'stopCode': '18131'},
                      'to': {'name': 'FORETT @ BT TIMAH', 'stopCode': '42221'},
                    },
                  ],
                },
                {
                  'duration': 60,
                  'legs': [
                    {
                      'mode': 'RAIL',
                      'route': 'CCL',
                      'from': {'name': 'A'},
                      'to': {'name': 'B'},
                    },
                  ],
                },
              ],
            }),
            200,
          );
        }),
      );
      final plans = await client.planTrips(
        startLatitude: 1.2,
        startLongitude: 103.8,
        endLatitude: 1.3,
        endLongitude: 103.8,
        departure: DateTime.utc(2026, 9, 19, 16, 30),
      );
      expect(plans, hasLength(1));
      expect(plans.single.legs.first.durationMinutes, 10);
      expect(plans.single.legs.first.to.code, '18131');
      expect(plans.single.legs.last.services, ['963']);
      expect(plans.single.legs.last.durationMinutes, 5);
      client.close();
    },
  );

  test(
    'migrates existing prefixed bus names without changing saved stop pairs',
    () {
      final leg = TripLeg.fromJson({
        'type': 'bus',
        'from': {'code': 'FERRY:18131', 'name': 'SCIENCE PK'},
        'to': {'code': '28101', 'name': 'OPP SMRT ULU PANDAN DEPOT'},
        'services': ['TTS BUS 963', 'SBST BUS 166', '963', 'Unknown'],
      });
      expect(leg.services, ['963', '166']);
      expect(leg.from.code, '18131');
      expect(leg.to.code, '28101');
    },
  );
}
