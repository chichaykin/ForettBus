import 'dart:convert';

import 'package:http/http.dart' as http;

import 'trip_cards.dart';
import 'schedule.dart';
import 'package:timezone/timezone.dart' as tz;

class TripPlanningException implements Exception {
  const TripPlanningException(this.message);

  final String message;
}

class PlaceSearchResult {
  const PlaceSearchResult({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final String address;
  final double latitude;
  final double longitude;
}

class TripPlannerClient {
  TripPlannerClient({String? baseUrl, String? appApiKey, http.Client? client})
    : baseUrl =
          (baseUrl ??
                  const String.fromEnvironment(
                    'BUS_API_BASE_URL',
                    defaultValue: '',
                  ))
              .trim()
              .replaceFirst(RegExp(r'/+$'), ''),
      appApiKey =
          (appApiKey ??
                  const String.fromEnvironment('APP_API_KEY', defaultValue: ''))
              .trim(),
      _client = client ?? http.Client();

  final String baseUrl;
  final String appApiKey;
  final http.Client _client;

  bool get isConfigured => baseUrl.isNotEmpty && appApiKey.isNotEmpty;

  Future<List<PlaceSearchResult>> searchPlaces(String query) async {
    if (!isConfigured) {
      throw const TripPlanningException('Live place search is not configured');
    }
    final response = await _get('/v1/stops/search', {'q': query});
    final decoded = jsonDecode(response.body);
    final results = decoded is Map<String, dynamic> ? decoded['results'] : null;
    if (results is! List) return const [];
    return results
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final latitude = double.tryParse(
            '${item['LATITUDE'] ?? item['latitude'] ?? ''}',
          );
          final longitude = double.tryParse(
            '${item['LONGITUDE'] ?? item['longitude'] ?? ''}',
          );
          final name = '${item['SEARCHVAL'] ?? item['name'] ?? ''}'.trim();
          final address = '${item['ADDRESS'] ?? item['address'] ?? name}'
              .trim();
          if (latitude == null || longitude == null || name.isEmpty) {
            return null;
          }
          return PlaceSearchResult(
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
          );
        })
        .whereType<PlaceSearchResult>()
        .toList(growable: false);
  }

  Future<List<TransitStop>> searchStops(String query) async {
    if (!isConfigured) {
      throw const TripPlanningException('Live stop search is not configured');
    }
    final response = await _get('/v1/stops', {'search': query});
    final decoded = jsonDecode(response.body);
    final stops = decoded is Map<String, dynamic> ? decoded['stops'] : null;
    if (stops is! List) return const [];
    return stops
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final code = '${item['code'] ?? ''}'.trim();
          final name = '${item['name'] ?? item['road'] ?? code}'.trim();
          if (code.isEmpty || name.isEmpty) return null;
          return TransitStop(code: normalizeStopCode(code), name: name);
        })
        .whereType<TransitStop>()
        .toList(growable: false);
  }

  Future<List<TripPlan>> planTrips({
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
    DateTime? departure,
  }) async {
    if (!isConfigured) {
      throw const TripPlanningException('Live trip planning is not configured');
    }
    final when = tz.TZDateTime.from(
      departure ?? BusSchedule.now(),
      BusSchedule.singaporeLocation,
    );
    final response = await _post('/v1/trips/plan', {
      'start': '$startLatitude,$startLongitude',
      'end': '$endLatitude,$endLongitude',
      'date':
          '${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}-${when.year}',
      'time':
          '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}:00',
    });
    final decoded = jsonDecode(response.body);
    final itineraries = decoded is Map<String, dynamic>
        ? decoded['itineraries']
        : null;
    if (itineraries is! List) return const [];
    return itineraries
        .whereType<Map<String, dynamic>>()
        .map(_parseItinerary)
        .whereType<TripPlan>()
        .toList(growable: false);
  }

  TripPlan? _parseItinerary(Map<String, dynamic> json) {
    final legs = json['legs'];
    if (legs is! List) return null;
    final parsed = <TripLeg>[];
    for (final raw in legs.whereType<Map<String, dynamic>>()) {
      final mode = '${raw['mode'] ?? raw['modeName'] ?? ''}'.toLowerCase();
      final from = _stopFrom(raw['from'] ?? raw['start'] ?? raw['fromStop']);
      final to = _stopFrom(raw['to'] ?? raw['end'] ?? raw['toStop']);
      if (from == null || to == null) {
        return null;
      }
      if (mode != 'walk' && mode != 'bus') return null;
      final services = <String>[];
      final route =
          raw['routeId'] ?? raw['serviceNo'] ?? raw['route'] ?? raw['service'];
      if (route is String && route.trim().isNotEmpty) {
        final service = normalizeBusService(route);
        if (service != null) services.add(service);
      } else if (route is Map<String, dynamic>) {
        final shortName = '${route['shortName'] ?? route['longName'] ?? ''}'
            .trim();
        final service = normalizeBusService(shortName);
        if (service != null) services.add(service);
      }
      if (mode == 'bus' &&
          (services.isEmpty ||
              !RegExp(r'^\d{5}$').hasMatch(from.code) ||
              !RegExp(r'^\d{5}$').hasMatch(to.code))) {
        return null;
      }
      parsed.add(
        TripLeg(
          type: mode.contains('walk') ? TripLegType.walk : TripLegType.bus,
          from: from,
          to: to,
          services: services,
          durationMinutes:
              raw['duration'] is num && (raw['duration'] as num) >= 0
              ? ((raw['duration'] as num) / 60).ceil()
              : null,
        ),
      );
    }
    if (parsed.isEmpty) return null;
    final duration = json['duration'] is num
        ? (json['duration'] as num).round() ~/ 60
        : null;
    return TripPlan(legs: List.unmodifiable(parsed), durationMinutes: duration);
  }

  TransitStop? _stopFrom(dynamic value) {
    if (value is! Map<String, dynamic>) return null;
    final code =
        '${value['stopCode'] ?? value['stopId'] ?? value['code'] ?? value['name'] ?? ''}'
            .trim();
    final name = '${value['name'] ?? value['stopName'] ?? code}'.trim();
    if (code.isEmpty || name.isEmpty) return null;
    return TransitStop(code: normalizeStopCode(code), name: name);
  }

  Future<http.Response> _get(String path, Map<String, String> query) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    try {
      final response = await _client
          .get(uri, headers: _headers())
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw TripPlanningException('Planning service unavailable');
      }
      return response;
    } on TripPlanningException {
      rethrow;
    } on Object {
      throw const TripPlanningException('Planning service unavailable');
    }
  }

  Future<http.Response> _post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final response = await _client
          .post(
            uri,
            headers: {..._headers(), 'content-type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const TripPlanningException('Trip planning unavailable');
      }
      return response;
    } on TripPlanningException {
      rethrow;
    } on Object {
      throw const TripPlanningException('Trip planning unavailable');
    }
  }

  Map<String, String> _headers() => {
    'accept': 'application/json',
    'authorization': 'Bearer $appApiKey',
  };

  void close() => _client.close();
}
