import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:timezone/timezone.dart' as tz;

import 'schedule.dart';
import 'transport_config.dart';

enum BusArrivalsErrorType { configuration, unauthorized, network, server, data }

const supportedPublicBusServices = {'41', '77'};

class BusArrivalsException implements Exception {
  const BusArrivalsException(this.type, this.message, {this.statusCode});

  final BusArrivalsErrorType type;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'BusArrivalsException($type): $message';
}

class BusStopConfig {
  const BusStopConfig({required this.code, required this.name});

  final String code;
  final String name;

  static BusStopConfig forDirection(Direction direction) {
    return direction == Direction.forettToBeautyWorld
        ? const BusStopConfig(code: '42221', name: 'Forett @ Bt Timah')
        : const BusStopConfig(code: '42151', name: 'Beauty World Stn Exit C');
  }
}

class BusArrival {
  const BusArrival({required this.estimatedArrival, required this.monitored});

  final DateTime estimatedArrival;
  final bool monitored;

  bool get isScheduled => !monitored;
}

class BusRouteArrivals {
  const BusRouteArrivals({required this.serviceNumber, required this.arrivals});

  final String serviceNumber;
  final List<BusArrival> arrivals;
}

class BusArrivalsSnapshot {
  const BusArrivalsSnapshot({
    required this.direction,
    required this.stop,
    required this.fetchedAt,
    required this.routes,
    this.isFallback = false,
  });

  final Direction direction;
  final BusStopConfig stop;
  final DateTime fetchedAt;
  final List<BusRouteArrivals> routes;

  /// True when the snapshot came from the bundled timetable rather than LTA.
  final bool isFallback;

  factory BusArrivalsSnapshot.fromJson(Map<String, dynamic> json) {
    final directionName = json['direction'];
    final direction = Direction.values.where(
      (value) => value.name == directionName,
    );
    if (direction.length != 1) {
      throw const FormatException('Invalid arrivals direction');
    }

    final stopJson = json['stop'];
    if (stopJson is! Map<String, dynamic>) {
      throw const FormatException('Missing arrivals stop');
    }
    final code = stopJson['code'];
    final name = stopJson['name'];
    if (code is! String || name is! String || code.isEmpty || name.isEmpty) {
      throw const FormatException('Invalid arrivals stop');
    }

    final fetchedAtValue = json['fetchedAt'];
    final fetchedAt = fetchedAtValue is String
        ? DateTime.tryParse(fetchedAtValue)
        : null;
    if (fetchedAt == null) {
      throw const FormatException('Invalid arrivals timestamp');
    }

    final routesJson = json['routes'];
    if (routesJson is! List) {
      throw const FormatException('Missing arrivals routes');
    }

    final routes = <BusRouteArrivals>[];
    for (final routeJson in routesJson) {
      if (routeJson is! Map<String, dynamic>) continue;
      final serviceNumber = routeJson['serviceNo'];
      final arrivalsJson = routeJson['arrivals'];
      if (serviceNumber is! String ||
          !supportedPublicBusServices.contains(serviceNumber) ||
          arrivalsJson is! List) {
        continue;
      }

      final arrivals = <BusArrival>[];
      for (final arrivalJson in arrivalsJson) {
        if (arrivalJson is! Map<String, dynamic>) continue;
        final timestamp = arrivalJson['estimatedArrival'];
        final monitored = arrivalJson['monitored'];
        final estimatedArrival = timestamp is String
            ? DateTime.tryParse(timestamp)
            : null;
        if (estimatedArrival == null || monitored is! bool) continue;
        arrivals.add(
          BusArrival(estimatedArrival: estimatedArrival, monitored: monitored),
        );
      }
      arrivals.sort((a, b) => a.estimatedArrival.compareTo(b.estimatedArrival));
      routes.add(
        BusRouteArrivals(
          serviceNumber: serviceNumber,
          arrivals: List.unmodifiable(arrivals.take(3)),
        ),
      );
    }
    routes.sort(
      (a, b) =>
          int.parse(a.serviceNumber).compareTo(int.parse(b.serviceNumber)),
    );

    return BusArrivalsSnapshot(
      direction: direction.single,
      stop: BusStopConfig(code: code, name: name),
      fetchedAt: fetchedAt,
      routes: List.unmodifiable(routes),
    );
  }
}

/// A small, offline timetable used when the live Worker/LTA path is down.
///
/// The anchors and headway profiles are taken from the public Tower Transit
/// stop timetables (checked 18 September 2026).  This is deliberately marked
/// as scheduled in the UI: it is a planning estimate and does not account for
/// traffic, short turns, or a cancelled trip.
class StaticBusSchedule {
  static const _weekday = _StaticDaySchedule(
    firstForett41: 6 * 60 + 8,
    lastForett41: 24 * 60 + 6,
    firstBeauty41: 6 * 60 + 1,
    lastBeauty41: 24 * 60 + 15,
    firstForett77: 6 * 60 + 13,
    lastForett77: 23 * 60 + 13,
    firstBeauty77: 6 * 60 + 42,
    lastBeauty77: 24 * 60 + 14,
  );
  static const _saturday = _StaticDaySchedule(
    firstForett41: 6 * 60 + 6,
    lastForett41: 24 * 60 + 4,
    firstBeauty41: 6 * 60 + 1,
    lastBeauty41: 24 * 60 + 13,
    firstForett77: 6 * 60 + 12,
    lastForett77: 23 * 60 + 12,
    firstBeauty77: 7 * 60 + 15,
    lastBeauty77: 24 * 60 + 14,
  );
  static const _sunday = _StaticDaySchedule(
    firstForett41: 6 * 60 + 6,
    lastForett41: 24 * 60 + 3,
    firstBeauty41: 6 * 60 + 1,
    lastBeauty41: 24 * 60 + 11,
    firstForett77: 6 * 60 + 10,
    lastForett77: 23 * 60 + 10,
    firstBeauty77: 7 * 60 + 13,
    lastBeauty77: 24 * 60 + 10,
  );

  static BusArrivalsSnapshot forDirection({
    required Direction direction,
    required DateTime now,
  }) {
    final singaporeNow = tz.TZDateTime.from(now, BusSchedule.singaporeLocation);
    final departures = <String, List<DateTime>>{'41': [], '77': []};
    final currentDate = tz.TZDateTime(
      BusSchedule.singaporeLocation,
      singaporeNow.year,
      singaporeNow.month,
      singaporeNow.day,
    );
    // After-midnight departures belong to the previous service day. Include
    // both service days so the fallback remains useful around midnight.
    for (final serviceDate in [
      currentDate.subtract(const Duration(days: 1)),
      currentDate,
    ]) {
      final day = _scheduleFor(serviceDate);
      _appendDepartures(
        departures['41']!,
        serviceDate,
        direction == Direction.forettToBeautyWorld
            ? day.firstForett41
            : day.firstBeauty41,
        direction == Direction.forettToBeautyWorld
            ? day.lastForett41
            : day.lastBeauty41,
        serviceNumber: '41',
      );
      _appendDepartures(
        departures['77']!,
        serviceDate,
        direction == Direction.forettToBeautyWorld
            ? day.firstForett77
            : day.firstBeauty77,
        direction == Direction.forettToBeautyWorld
            ? day.lastForett77
            : day.lastBeauty77,
        serviceNumber: '77',
      );
    }

    final routes = <BusRouteArrivals>[];
    for (final serviceNumber in ['41', '77']) {
      final arrivals =
          departures[serviceNumber]!
              .where((departure) => !departure.isBefore(singaporeNow))
              .toList()
            ..sort();
      routes.add(
        BusRouteArrivals(
          serviceNumber: serviceNumber,
          arrivals: arrivals
              .take(3)
              .map(
                (departure) =>
                    BusArrival(estimatedArrival: departure, monitored: false),
              )
              .toList(growable: false),
        ),
      );
    }

    return BusArrivalsSnapshot(
      direction: direction,
      stop: BusStopConfig.forDirection(direction),
      fetchedAt: singaporeNow,
      routes: List.unmodifiable(routes),
      isFallback: true,
    );
  }

  static _StaticDaySchedule _scheduleFor(DateTime date) {
    if (date.weekday == DateTime.sunday) return _sunday;
    if (date.weekday == DateTime.saturday) return _saturday;
    return _weekday;
  }

  static void _appendDepartures(
    List<DateTime> output,
    DateTime serviceDate,
    int firstMinute,
    int lastMinute, {
    required String serviceNumber,
  }) {
    var minute = firstMinute;
    while (minute <= lastMinute) {
      final departureDate = serviceDate.add(
        Duration(days: minute ~/ (24 * 60)),
      );
      final departure = _atMinute(departureDate, minute % (24 * 60));
      output.add(departure);
      final headway = serviceNumber == '41'
          ? (minute >= 17 * 60 ? 14 : 15)
          : (minute >= 17 * 60 ? 14 : 13);
      minute += headway;
    }
    final lastDate = serviceDate.add(Duration(days: lastMinute ~/ (24 * 60)));
    final lastDeparture = _atMinute(lastDate, lastMinute % (24 * 60));
    if (output.isEmpty || output.last != lastDeparture) {
      output.add(lastDeparture);
    }
  }

  static DateTime _atMinute(DateTime date, int minute) {
    if (date is tz.TZDateTime) {
      return tz.TZDateTime(
        date.location,
        date.year,
        date.month,
        date.day,
        minute ~/ 60,
        minute % 60,
      );
    }
    return DateTime(date.year, date.month, date.day, minute ~/ 60, minute % 60);
  }
}

class _StaticDaySchedule {
  const _StaticDaySchedule({
    required this.firstForett41,
    required this.lastForett41,
    required this.firstBeauty41,
    required this.lastBeauty41,
    required this.firstForett77,
    required this.lastForett77,
    required this.firstBeauty77,
    required this.lastBeauty77,
  });

  final int firstForett41;
  final int lastForett41;
  final int firstBeauty41;
  final int lastBeauty41;
  final int firstForett77;
  final int lastForett77;
  final int firstBeauty77;
  final int lastBeauty77;
}

abstract interface class BusArrivalsRepository {
  bool get isConfigured;

  Future<BusArrivalsSnapshot> fetch(Direction direction);
}

/// Live arrivals for user-configured trip cards. This intentionally accepts a
/// stop code and a service allow-list, while the legacy direction API above
/// remains unchanged for the Forett shuttle companion card.
class StopArrivalsSnapshot {
  const StopArrivalsSnapshot({
    required this.stopCode,
    required this.fetchedAt,
    required this.routes,
  });
  final String stopCode;
  final DateTime fetchedAt;
  final List<BusRouteArrivals> routes;

  bool isStale(DateTime now) =>
      now.difference(fetchedAt) > const Duration(seconds: 60);
}

class HttpBusStopArrivalsRepository {
  HttpBusStopArrivalsRepository({
    String? baseUrl,
    String? appApiKey,
    http.Client? client,
  }) : _config = baseUrl == null && appApiKey == null
           ? TransportConfig.defaults()
           : TransportConfig.explicit(baseUrl ?? '', appApiKey ?? ''),
       _client = client ?? http.Client();

  final TransportConfig _config;
  String get baseUrl => _config.baseUrl;
  String get appApiKey => _config.appApiKey;
  final http.Client _client;
  final Map<String, Future<StopArrivalsSnapshot>> _requests = {};
  final Map<String, DateTime> _requestedAt = {};

  bool get isConfigured => _config.isConfigured;

  Future<StopArrivalsSnapshot> fetch(String stopCode) {
    // Share both in-flight and completed requests across cards and directions.
    // Failed requests are also throttled until the next polling interval.
    final last = _requestedAt[stopCode];
    if (last != null &&
        BusSchedule.now().difference(last) < const Duration(seconds: 20)) {
      return _requests[stopCode]!;
    }
    _requestedAt[stopCode] = BusSchedule.now();
    return _requests[stopCode] = _fetch(stopCode);
  }

  Future<StopArrivalsSnapshot> _fetch(String stopCode) async {
    if (!isConfigured || !RegExp(r'^\d{5}$').hasMatch(stopCode)) {
      throw const BusArrivalsException(
        BusArrivalsErrorType.configuration,
        'Invalid stop configuration',
      );
    }
    await _config.ensureWebSession(_client);
    final uri = _config.uri('/v1/arrivals', {'stopCode': stopCode});
    final response = await _client
        .get(uri, headers: _config.headers())
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw const BusArrivalsException(
        BusArrivalsErrorType.server,
        'Arrivals unavailable',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> ||
        decoded['routes'] is! List ||
        decoded['stop'] is! Map ||
        decoded['stop']['code'] != stopCode) {
      throw const BusArrivalsException(
        BusArrivalsErrorType.data,
        'Invalid arrivals response',
      );
    }
    final fetchedAt = DateTime.tryParse('${decoded['fetchedAt']}');
    if (fetchedAt == null) {
      throw const FormatException('Missing arrivals timestamp');
    }
    final routes = <BusRouteArrivals>[];
    for (final raw in decoded['routes'] as List) {
      if (raw is! Map ||
          raw['serviceNo'] is! String ||
          raw['arrivals'] is! List) {
        continue;
      }
      final arrivals = <BusArrival>[];
      for (final bus in raw['arrivals'] as List) {
        if (bus is! Map || bus['monitored'] is! bool) continue;
        final estimated = DateTime.tryParse('${bus['estimatedArrival']}');
        if (estimated != null) {
          arrivals.add(
            BusArrival(
              estimatedArrival: estimated,
              monitored: bus['monitored'] as bool,
            ),
          );
        }
      }
      arrivals.sort((a, b) => a.estimatedArrival.compareTo(b.estimatedArrival));
      routes.add(
        BusRouteArrivals(
          serviceNumber: raw['serviceNo'] as String,
          arrivals: List.unmodifiable(arrivals.take(3)),
        ),
      );
    }
    return StopArrivalsSnapshot(
      stopCode: stopCode,
      fetchedAt: fetchedAt,
      routes: List.unmodifiable(routes),
    );
  }

  void close() => _client.close();
}

class HttpBusArrivalsRepository implements BusArrivalsRepository {
  HttpBusArrivalsRepository({
    String? baseUrl,
    String? appApiKey,
    http.Client? client,
  }) : _config = baseUrl == null && appApiKey == null
           ? TransportConfig.defaults()
           : TransportConfig.explicit(baseUrl ?? '', appApiKey ?? ''),
       _client = client ?? http.Client();

  final TransportConfig _config;
  String get baseUrl => _config.baseUrl;
  String get appApiKey => _config.appApiKey;
  final http.Client _client;

  @override
  bool get isConfigured {
    return _config.isConfigured;
  }

  @override
  Future<BusArrivalsSnapshot> fetch(Direction direction) async {
    if (!isConfigured) {
      throw const BusArrivalsException(
        BusArrivalsErrorType.configuration,
        'Live arrivals are not configured',
      );
    }

    final uri = _config.uri('/v1/arrivals', {'direction': direction.name});

    http.Response response;
    try {
      await _config.ensureWebSession(_client);
      response = await _client
          .get(uri, headers: _config.headers())
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const BusArrivalsException(
        BusArrivalsErrorType.network,
        'The arrivals request timed out',
      );
    } on Object catch (error) {
      throw BusArrivalsException(
        BusArrivalsErrorType.network,
        'The arrivals request failed: $error',
      );
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw BusArrivalsException(
        BusArrivalsErrorType.unauthorized,
        'The arrivals API rejected this app version',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BusArrivalsException(
        BusArrivalsErrorType.server,
        'The arrivals service returned HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Response is not an object');
      }
      final snapshot = BusArrivalsSnapshot.fromJson(decoded);
      if (snapshot.direction != direction) {
        throw const FormatException(
          'Response direction does not match request',
        );
      }
      if (snapshot.stop.code != BusStopConfig.forDirection(direction).code) {
        throw const FormatException('Response stop does not match request');
      }
      return snapshot;
    } on FormatException catch (error) {
      throw BusArrivalsException(BusArrivalsErrorType.data, error.message);
    } on Object catch (error) {
      throw BusArrivalsException(
        BusArrivalsErrorType.data,
        'The arrivals response could not be read: $error',
      );
    }
  }

  void close() => _client.close();
}
