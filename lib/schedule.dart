import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

enum Direction { forettToBeautyWorld, beautyWorldToForett }

class BusSchedule {
  static final tz.Location singaporeLocation = _loadSingaporeLocation();

  static const List<String> _forettTimes = [
    "06:30",
    "06:50",
    "07:10",
    "07:30",
    "07:50",
    "08:10",
    "08:30",
    "08:50",
    "09:10",
    "10:00",
    "10:20",
    "10:40",
    "11:00",
    "11:20",
    "11:40",
    "12:00",
    "12:20",
    "12:40",
    "14:30",
    "14:50",
    "15:10",
    "15:30",
    "15:50",
    "16:10",
    "17:00",
    "17:20",
    "17:40",
    "18:00",
    "18:20",
    "18:40",
    "19:00",
    "19:20",
  ];

  static const List<String> _beautyWorldTimes = [
    "06:37",
    "06:57",
    "07:17",
    "07:37",
    "07:57",
    "08:17",
    "08:37",
    "08:57",
    "09:17",
    "10:07",
    "10:27",
    "10:47",
    "11:07",
    "11:27",
    "11:47",
    "12:07",
    "12:27",
    "12:47",
    "14:37",
    "14:57",
    "15:17",
    "15:37",
    "15:57",
    "16:17",
    "17:07",
    "17:27",
    "17:47",
    "18:07",
    "18:27",
    "18:47",
    "19:07",
    "19:27",
  ];

  static bool isOperatingDay(DateTime date) {
    return date.weekday != DateTime.sunday;
  }

  static tz.TZDateTime now() => tz.TZDateTime.now(singaporeLocation);

  static DateTime? getNextBus(DateTime now, Direction direction) {
    if (!isOperatingDay(now)) return null;

    final times = getTimesForDirection(direction);

    for (final timeStr in times) {
      final parts = timeStr.split(':');
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

      if (!busTime.isBefore(now)) {
        return busTime;
      }
    }

    return null;
  }

  /// Returns the first shuttle on the next operating day after [now].
  static DateTime? getNextOperatingDayBus(DateTime now, Direction direction) {
    final singaporeNow = tz.TZDateTime.from(now, singaporeLocation);
    for (var daysAhead = 1; daysAhead <= 7; daysAhead++) {
      final candidate = singaporeNow.add(Duration(days: daysAhead));
      if (!isOperatingDay(candidate)) continue;

      final serviceDay = tz.TZDateTime(
        singaporeLocation,
        candidate.year,
        candidate.month,
        candidate.day,
      );
      return getNextBus(serviceDay, direction);
    }
    return null;
  }

  static List<String> getTimesForDirection(Direction direction) {
    return direction == Direction.forettToBeautyWorld
        ? _forettTimes
        : _beautyWorldTimes;
  }

  static tz.Location _loadSingaporeLocation() {
    timezone_data.initializeTimeZones();
    return tz.getLocation('Asia/Singapore');
  }
}
