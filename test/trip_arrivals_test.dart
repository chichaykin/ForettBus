import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shuttle_bus/bus_arrivals.dart';
import 'package:shuttle_bus/schedule.dart';

void main() {
  test(
    'shares stop requests, preserves upstream age and includes all services',
    () async {
      var calls = 0;
      final now = BusSchedule.now();
      final fetched = now.subtract(const Duration(seconds: 65));
      final repo = HttpBusStopArrivalsRepository(
        baseUrl: 'https://example.test',
        appApiKey: 'test',
        client: MockClient((request) async {
          calls++;
          expect(request.url.queryParameters, {'stopCode': '18131'});
          expect(request.headers['authorization'], 'Bearer test');
          return http.Response(
            jsonEncode({
              'stop': {'code': '18131'},
              'fetchedAt': fetched.toIso8601String(),
              'routes': [
                {
                  'serviceNo': '963',
                  'arrivals': [
                    {
                      'estimatedArrival': now
                          .add(const Duration(minutes: 5))
                          .toIso8601String(),
                      'monitored': true,
                    },
                  ],
                },
                {'serviceNo': '188', 'arrivals': []},
              ],
            }),
            200,
          );
        }),
      );
      final snapshots = await Future.wait([
        repo.fetch('18131'),
        repo.fetch('18131'),
      ]);
      await repo.fetch('18131');
      expect(calls, 1);
      expect(snapshots.first.fetchedAt.isAtSameMomentAs(fetched), isTrue);
      expect(snapshots.first.isStale(now), isTrue);
      expect(snapshots.first.routes.map((r) => r.serviceNumber), [
        '963',
        '188',
      ]);
      repo.close();
    },
  );

  test(
    'a stop failure does not block other stops or cause rapid retries',
    () async {
      var calls = 0;
      final repo = HttpBusStopArrivalsRepository(
        baseUrl: 'https://example.test',
        appApiKey: 'test',
        client: MockClient((request) async {
          calls++;
          if (request.url.queryParameters['stopCode'] == '18131') {
            return http.Response('', 503);
          }
          return http.Response(
            jsonEncode({
              'stop': {'code': '28101'},
              'fetchedAt': BusSchedule.now().toIso8601String(),
              'routes': [],
            }),
            200,
          );
        }),
      );
      await expectLater(
        repo.fetch('18131'),
        throwsA(isA<BusArrivalsException>()),
      );
      await expectLater(
        repo.fetch('18131'),
        throwsA(isA<BusArrivalsException>()),
      );
      expect((await repo.fetch('28101')).stopCode, '28101');
      expect(calls, 2);
      repo.close();
    },
  );
}
