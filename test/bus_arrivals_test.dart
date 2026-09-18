import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:shuttle_bus/bus_arrivals.dart';
import 'package:shuttle_bus/schedule.dart';

void main() {
  test('maps each direction to its fixed boarding stop', () {
    expect(
      BusStopConfig.forDirection(Direction.forettToBeautyWorld).code,
      '42221',
    );
    expect(
      BusStopConfig.forDirection(Direction.beautyWorldToForett).code,
      '42151',
    );
  });

  test('does not enable the client for a non-HTTPS endpoint', () {
    final repository = HttpBusArrivalsRepository(
      baseUrl: 'http://example.test',
      appApiKey: 'app-secret',
      client: MockClient((_) async => http.Response('{}', 500)),
    );

    expect(repository.isConfigured, isFalse);
  });

  test('rejects endpoints that contain embedded query configuration', () {
    final repository = HttpBusArrivalsRepository(
      baseUrl: 'https://example.test?token=leaked',
      appApiKey: 'app-secret',
      client: MockClient((_) async => http.Response('{}', 500)),
    );

    expect(repository.isConfigured, isFalse);
  });

  test('sends the app bearer key and parses normalized arrivals', () async {
    final client = MockClient((request) async {
      expect(request.url.queryParameters['direction'], 'beautyWorldToForett');
      expect(request.headers['authorization'], 'Bearer app-secret');
      return http.Response(
        jsonEncode({
          'direction': 'beautyWorldToForett',
          'stop': {'code': '42151', 'name': 'Beauty World Stn Exit C'},
          'fetchedAt': '2026-09-18T10:00:00+08:00',
          'routes': [
            {
              'serviceNo': '41',
              'arrivals': [
                {
                  'estimatedArrival': '2026-09-18T10:05:00+08:00',
                  'monitored': true,
                },
              ],
            },
          ],
        }),
        200,
      );
    });

    final repository = HttpBusArrivalsRepository(
      baseUrl: 'https://example.test/',
      appApiKey: 'app-secret',
      client: client,
    );
    final snapshot = await repository.fetch(Direction.beautyWorldToForett);

    expect(snapshot.stop.code, '42151');
    expect(snapshot.routes.single.serviceNumber, '41');
    expect(snapshot.routes.single.arrivals.single.isScheduled, isFalse);
  });

  test('surfaces an unauthorized response without retrying', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response('{"error":"Unauthorized"}', 401);
    });
    final repository = HttpBusArrivalsRepository(
      baseUrl: 'https://example.test',
      appApiKey: 'app-secret',
      client: client,
    );

    await expectLater(
      () => repository.fetch(Direction.forettToBeautyWorld),
      throwsA(
        isA<BusArrivalsException>().having(
          (error) => error.type,
          'type',
          BusArrivalsErrorType.unauthorized,
        ),
      ),
    );
    expect(requests, 1);
  });

  test('builds a scheduled fallback for both public bus routes', () {
    final now = tz.TZDateTime(BusSchedule.singaporeLocation, 2026, 9, 18, 7);
    final snapshot = StaticBusSchedule.forDirection(
      direction: Direction.forettToBeautyWorld,
      now: now,
    );

    expect(snapshot.isFallback, isTrue);
    expect(snapshot.stop.code, '42221');
    expect(snapshot.routes.map((route) => route.serviceNumber), ['41', '77']);
    expect(
      snapshot.routes.every((route) => route.arrivals.length == 3),
      isTrue,
    );
    expect(
      snapshot.routes
          .expand((route) => route.arrivals)
          .every(
            (arrival) =>
                arrival.isScheduled && !arrival.estimatedArrival.isBefore(now),
          ),
      isTrue,
    );
  });

  test('normalizes fallback inputs to the Singapore timezone', () {
    final singaporeNow = tz.TZDateTime(
      BusSchedule.singaporeLocation,
      2026,
      9,
      18,
      7,
    );
    final fromSingapore = StaticBusSchedule.forDirection(
      direction: Direction.forettToBeautyWorld,
      now: singaporeNow,
    );
    final fromUtc = StaticBusSchedule.forDirection(
      direction: Direction.forettToBeautyWorld,
      now: DateTime.utc(2026, 9, 17, 23),
    );

    expect(
      fromUtc.routes
          .expand((route) => route.arrivals)
          .map((arrival) => arrival.estimatedArrival.millisecondsSinceEpoch),
      fromSingapore.routes
          .expand((route) => route.arrivals)
          .map((arrival) => arrival.estimatedArrival.millisecondsSinceEpoch),
    );
  });

  test('filters and orders untrusted arrival payload data', () {
    final snapshot = BusArrivalsSnapshot.fromJson({
      'direction': 'forettToBeautyWorld',
      'stop': {'code': '42221', 'name': 'Forett @ Bt Timah'},
      'fetchedAt': '2026-09-18T10:00:00+08:00',
      'routes': [
        {
          'serviceNo': '999',
          'arrivals': [
            {
              'estimatedArrival': '2026-09-18T10:01:00+08:00',
              'monitored': true,
            },
          ],
        },
        {
          'serviceNo': '77',
          'arrivals': [
            {
              'estimatedArrival': '2026-09-18T10:04:00+08:00',
              'monitored': false,
            },
          ],
        },
        {
          'serviceNo': '41',
          'arrivals': [
            {
              'estimatedArrival': '2026-09-18T10:05:00+08:00',
              'monitored': true,
            },
            {
              'estimatedArrival': '2026-09-18T10:02:00+08:00',
              'monitored': true,
            },
            {
              'estimatedArrival': '2026-09-18T10:03:00+08:00',
              'monitored': true,
            },
            {
              'estimatedArrival': '2026-09-18T10:01:00+08:00',
              'monitored': 'not-a-bool',
            },
            {
              'estimatedArrival': '2026-09-18T10:04:00+08:00',
              'monitored': true,
            },
          ],
        },
      ],
    });

    expect(snapshot.routes.map((route) => route.serviceNumber), ['41', '77']);
    expect(snapshot.routes.first.arrivals, hasLength(3));
    expect(
      snapshot.routes.first.arrivals.map(
        (arrival) => arrival.estimatedArrival.minute,
      ),
      [2, 3, 4],
    );
  });

  test('keeps after-midnight services and Sunday public buses', () {
    final saturdayLate = tz.TZDateTime(
      BusSchedule.singaporeLocation,
      2026,
      9,
      19,
      23,
      55,
    );
    final overnight = StaticBusSchedule.forDirection(
      direction: Direction.beautyWorldToForett,
      now: saturdayLate,
    );
    expect(
      overnight.routes.every(
        (route) => route.arrivals.first.estimatedArrival.day == 20,
      ),
      isTrue,
    );

    final sunday = StaticBusSchedule.forDirection(
      direction: Direction.beautyWorldToForett,
      now: tz.TZDateTime(BusSchedule.singaporeLocation, 2026, 9, 20, 7),
    );
    expect(sunday.routes.every((route) => route.arrivals.isNotEmpty), isTrue);
  });
}
