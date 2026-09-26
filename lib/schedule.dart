import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

enum Direction { forettToBeautyWorld, beautyWorldToForett }

class ScheduleBreak {
  const ScheduleBreak({required this.start, required this.end});

  final String start;
  final String end;

  Map<String, String> toJson() => {'start': start, 'end': end};

  factory ScheduleBreak.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Invalid break');
    final start = value['start'];
    final end = value['end'];
    if (start is! String || end is! String) {
      throw const FormatException('Invalid break times');
    }
    return ScheduleBreak(start: start, end: end);
  }

  @override
  bool operator ==(Object other) =>
      other is ScheduleBreak && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// The locally active timetable. All departures are Singapore local time.
class ShuttleSchedule {
  const ShuttleSchedule({
    required this.forettTimes,
    required this.beautyWorldTimes,
    required this.breaks,
    required this.holidayDates,
    required this.holidayStartYear,
    required this.holidayEndYear,
  });

  final List<String> forettTimes;
  final List<String> beautyWorldTimes;
  final List<ScheduleBreak> breaks;
  final Set<String> holidayDates;
  final int holidayStartYear;
  final int holidayEndYear;

  static ShuttleSchedule original() => ShuttleSchedule(
    forettTimes: const [
      '06:30',
      '06:50',
      '07:10',
      '07:30',
      '07:50',
      '08:10',
      '08:30',
      '08:50',
      '09:10',
      '10:00',
      '10:20',
      '10:40',
      '11:00',
      '11:20',
      '11:40',
      '12:00',
      '12:20',
      '12:40',
      '14:30',
      '14:50',
      '15:10',
      '15:30',
      '15:50',
      '16:10',
      '17:00',
      '17:20',
      '17:40',
      '18:00',
      '18:20',
      '18:40',
      '19:00',
      '19:20',
    ],
    beautyWorldTimes: const [
      '06:37',
      '06:57',
      '07:17',
      '07:37',
      '07:57',
      '08:17',
      '08:37',
      '08:57',
      '09:17',
      '10:07',
      '10:27',
      '10:47',
      '11:07',
      '11:27',
      '11:47',
      '12:07',
      '12:27',
      '12:47',
      '14:37',
      '14:57',
      '15:17',
      '15:37',
      '15:57',
      '16:17',
      '17:07',
      '17:27',
      '17:47',
      '18:07',
      '18:27',
      '18:47',
      '19:07',
      '19:27',
    ],
    breaks: const [
      ScheduleBreak(start: '09:30', end: '10:00'),
      ScheduleBreak(start: '13:00', end: '14:30'),
      ScheduleBreak(start: '16:30', end: '17:00'),
    ],
    holidayDates: _bundledHolidayDates,
    holidayStartYear: 2025,
    holidayEndYear: 2027,
  );

  ShuttleSchedule copyWith({
    List<String>? forettTimes,
    List<String>? beautyWorldTimes,
    List<ScheduleBreak>? breaks,
    Set<String>? holidayDates,
    int? holidayStartYear,
    int? holidayEndYear,
  }) => ShuttleSchedule(
    forettTimes: forettTimes ?? this.forettTimes,
    beautyWorldTimes: beautyWorldTimes ?? this.beautyWorldTimes,
    breaks: breaks ?? this.breaks,
    holidayDates: holidayDates ?? this.holidayDates,
    holidayStartYear: holidayStartYear ?? this.holidayStartYear,
    holidayEndYear: holidayEndYear ?? this.holidayEndYear,
  );

  List<String> timesFor(Direction direction) =>
      direction == Direction.forettToBeautyWorld
      ? forettTimes
      : beautyWorldTimes;

  bool hasHolidayCalendarFor(DateTime date) =>
      date.year >= holidayStartYear && date.year <= holidayEndYear;

  bool isHoliday(DateTime date) => holidayDates.contains(_dateKey(date));

  bool isOperatingDay(DateTime date) =>
      date.weekday != DateTime.sunday && !isHoliday(date);

  List<String> validate() {
    final errors = <String>[];
    _validateTimes('Forett', forettTimes, errors);
    _validateTimes('Beauty World', beautyWorldTimes, errors);
    for (final item in breaks) {
      if (!_isTime(item.start) ||
          !_isTime(item.end) ||
          item.start.compareTo(item.end) >= 0) {
        errors.add('Each break needs a valid start before its end.');
      }
    }
    return errors;
  }

  Map<String, Object> toJson() => {
    'version': 1,
    'forettTimes': forettTimes,
    'beautyWorldTimes': beautyWorldTimes,
    'breaks': breaks.map((item) => item.toJson()).toList(),
    'holidayDates': holidayDates.toList()..sort(),
    'holidayStartYear': holidayStartYear,
    'holidayEndYear': holidayEndYear,
  };

  factory ShuttleSchedule.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Invalid timetable');
    List<String> stringsFor(String key) {
      final values = value[key];
      if (values is! List || values.any((item) => item is! String)) {
        throw FormatException('Invalid $key');
      }
      return values.cast<String>();
    }

    final breaksValue = value['breaks'];
    if (breaksValue is! List) throw const FormatException('Invalid breaks');
    final holidayValues = stringsFor('holidayDates');
    final firstYear = value['holidayStartYear'];
    final lastYear = value['holidayEndYear'];
    if (firstYear is! int || lastYear is! int) {
      throw const FormatException('Invalid holiday coverage');
    }
    final schedule = ShuttleSchedule(
      forettTimes: stringsFor('forettTimes'),
      beautyWorldTimes: stringsFor('beautyWorldTimes'),
      breaks: breaksValue.map(ScheduleBreak.fromJson).toList(),
      holidayDates: holidayValues.toSet(),
      holidayStartYear: firstYear,
      holidayEndYear: lastYear,
    );
    if (schedule.validate().isNotEmpty) {
      throw const FormatException('Invalid timetable');
    }
    return schedule;
  }
}

void _validateTimes(String label, List<String> times, List<String> errors) {
  if (times.isEmpty) {
    errors.add('$label needs at least one departure.');
    return;
  }
  String? previous;
  for (final time in times) {
    if (!_isTime(time)) {
      errors.add('$label contains an invalid time: $time.');
      continue;
    }
    if (previous != null && previous.compareTo(time) >= 0) {
      errors.add('$label times must be in ascending order without duplicates.');
      return;
    }
    previous = time;
  }
}

bool _isTime(String value) =>
    RegExp(r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(value);

String _dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

class BusSchedule {
  static const _storageKey = 'shuttle_schedule.v1';
  static final tz.Location singaporeLocation = _loadSingaporeLocation();
  static final ValueNotifier<ShuttleSchedule> active = ValueNotifier(
    ShuttleSchedule.original(),
  );
  static SharedPreferences? _preferences;

  static Future<void> load({SharedPreferences? preferences}) async {
    _preferences = preferences ?? await SharedPreferences.getInstance();
    final raw = _preferences!.getString(_storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      active.value = ShuttleSchedule.fromJson(jsonDecode(raw));
    } on Object {
      active.value = ShuttleSchedule.original();
    }
  }

  static Future<void> save(ShuttleSchedule schedule) async {
    final errors = schedule.validate();
    if (errors.isNotEmpty) throw FormatException(errors.first);
    final preferences = _preferences;
    if (preferences != null) {
      final saved = await preferences.setString(
        _storageKey,
        jsonEncode(schedule.toJson()),
      );
      if (!saved) throw StateError('Could not save the timetable');
    }
    active.value = schedule;
  }

  static Future<void> restoreOriginal() => save(ShuttleSchedule.original());

  /// Updates only the holiday cache; a network failure leaves the existing
  /// timetable and cached calendar usable.
  static Future<void> refreshHolidayCalendar({http.Client? client}) async {
    final ownedClient = client == null;
    final requestClient = client ?? http.Client();
    try {
      final response = await requestClient.get(
        kIsWeb
            ? Uri.base.resolve('/api/holidays')
            : Uri.parse(
                'https://data.gov.sg/api/action/datastore_search?resource_id=d_8ef23381f9417e4d4254ee8b4dcdb176&limit=200',
              ),
      );
      if (response.statusCode != 200) return;
      final payload = jsonDecode(response.body);
      final result = payload is Map ? payload['result'] : null;
      final records = result is Map ? result['records'] : null;
      if (records is! List) return;
      final dates = <String>{};
      var firstYear = 9999;
      var lastYear = 0;
      for (final record in records) {
        if (record is! Map || record['date'] is! String) continue;
        final date = record['date'] as String;
        if (!RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$').hasMatch(date)) continue;
        dates.add(date);
        final year = int.parse(date.substring(0, 4));
        if (year < firstYear) firstYear = year;
        if (year > lastYear) lastYear = year;
      }
      if (dates.isEmpty) return;
      await save(
        active.value.copyWith(
          holidayDates: dates,
          holidayStartYear: firstYear,
          holidayEndYear: lastYear,
        ),
      );
    } on Object {
      // The bundled calendar remains available offline.
    } finally {
      if (ownedClient) requestClient.close();
    }
  }

  static tz.TZDateTime now() => tz.TZDateTime.now(singaporeLocation);

  static bool isOperatingDay(DateTime date) =>
      active.value.isOperatingDay(date);

  static bool hasHolidayCalendarFor(DateTime date) =>
      active.value.hasHolidayCalendarFor(date);

  static bool isConfirmedOperatingDay(DateTime date) =>
      hasHolidayCalendarFor(date) && isOperatingDay(date);

  static bool containsDeparture(DateTime date, Direction direction) =>
      getTimesForDirection(direction).contains(_timeKey(date));

  static DateTime? getNextBus(DateTime now, Direction direction) {
    if (!isOperatingDay(now)) return null;
    for (final time in getTimesForDirection(direction)) {
      final parts = time.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final DateTime busTime;
      if (now is tz.TZDateTime) {
        busTime = tz.TZDateTime(
          now.location,
          now.year,
          now.month,
          now.day,
          hour,
          minute,
        );
      } else if (now.isUtc) {
        busTime = DateTime.utc(now.year, now.month, now.day, hour, minute);
      } else {
        busTime = DateTime(now.year, now.month, now.day, hour, minute);
      }
      if (!busTime.isBefore(now)) return busTime;
    }
    return null;
  }

  static DateTime? getNextOperatingDayBus(DateTime now, Direction direction) {
    final singaporeNow = tz.TZDateTime.from(now, singaporeLocation);
    for (var daysAhead = 1; daysAhead <= 370; daysAhead++) {
      final candidate = singaporeNow.add(Duration(days: daysAhead));
      if (!isOperatingDay(candidate)) continue;
      final day = tz.TZDateTime(
        singaporeLocation,
        candidate.year,
        candidate.month,
        candidate.day,
      );
      return getNextBus(day, direction);
    }
    return null;
  }

  static List<String> getTimesForDirection(Direction direction) =>
      List.unmodifiable(active.value.timesFor(direction));

  static String _timeKey(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  static tz.Location _loadSingaporeLocation() {
    timezone_data.initializeTimeZones();
    return tz.getLocation('Asia/Singapore');
  }

  @visibleForTesting
  static void resetForTests() {
    _preferences = null;
    active.value = ShuttleSchedule.original();
  }
}

const Set<String> _bundledHolidayDates = {
  '2025-01-01',
  '2025-01-29',
  '2025-01-30',
  '2025-03-31',
  '2025-04-18',
  '2025-05-01',
  '2025-05-12',
  '2025-06-07',
  '2025-08-09',
  '2025-10-20',
  '2025-12-25',
  '2026-01-01',
  '2026-02-17',
  '2026-02-18',
  '2026-03-21',
  '2026-04-03',
  '2026-05-01',
  '2026-05-27',
  '2026-06-01',
  '2026-08-10',
  '2026-11-09',
  '2026-12-25',
  '2027-01-01',
  '2027-02-06',
  '2027-02-07',
  '2027-03-10',
  '2027-03-26',
  '2027-05-01',
  '2027-05-17',
  '2027-06-06',
  '2027-08-09',
  '2027-10-29',
  '2027-12-25',
};
