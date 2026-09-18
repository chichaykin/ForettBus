import 'package:flutter_test/flutter_test.dart';
import 'package:shuttle_bus/schedule.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  group('BusSchedule', () {
    test('operates from Monday through Saturday', () {
      expect(BusSchedule.isOperatingDay(DateTime(2026, 9, 12)), isTrue);
      expect(BusSchedule.isOperatingDay(DateTime(2026, 9, 13)), isFalse);
      expect(BusSchedule.isOperatingDay(DateTime(2026, 9, 14)), isTrue);
    });

    test('returns the first departure before service starts', () {
      final nextBus = BusSchedule.getNextBus(
        DateTime(2026, 9, 14, 6),
        Direction.forettToBeautyWorld,
      );

      expect(nextBus, DateTime(2026, 9, 14, 6, 30));
    });

    test('includes a departure at its exact scheduled instant', () {
      final nextBus = BusSchedule.getNextBus(
        DateTime(2026, 9, 14, 6, 30),
        Direction.forettToBeautyWorld,
      );

      expect(nextBus, DateTime(2026, 9, 14, 6, 30));
    });

    test('advances once a departure instant has passed', () {
      final nextBus = BusSchedule.getNextBus(
        DateTime(2026, 9, 14, 6, 30, 1),
        Direction.forettToBeautyWorld,
      );

      expect(nextBus, DateTime(2026, 9, 14, 6, 50));
    });

    test('skips the long midday driver break', () {
      final nextBus = BusSchedule.getNextBus(
        DateTime(2026, 9, 14, 12, 40, 1),
        Direction.forettToBeautyWorld,
      );

      expect(nextBus, DateTime(2026, 9, 14, 14, 30));
    });

    test('uses the correct timetable for the return direction', () {
      final nextBus = BusSchedule.getNextBus(
        DateTime(2026, 9, 14, 6),
        Direction.beautyWorldToForett,
      );

      expect(nextBus, DateTime(2026, 9, 14, 6, 37));
    });

    test('returns null on Sunday and after the final departure', () {
      expect(
        BusSchedule.getNextBus(
          DateTime(2026, 9, 13, 10),
          Direction.forettToBeautyWorld,
        ),
        isNull,
      );
      expect(
        BusSchedule.getNextBus(
          DateTime(2026, 9, 14, 19, 20, 1),
          Direction.forettToBeautyWorld,
        ),
        isNull,
      );
    });

    test('finds the first shuttle on the next operating day', () {
      final afterSaturdayService = tz.TZDateTime(
        BusSchedule.singaporeLocation,
        2026,
        9,
        12,
        23,
      );
      final nextAfterSaturday = BusSchedule.getNextOperatingDayBus(
        afterSaturdayService,
        Direction.forettToBeautyWorld,
      );
      expect(nextAfterSaturday, isA<tz.TZDateTime>());
      expect(nextAfterSaturday?.weekday, DateTime.monday);
      expect(nextAfterSaturday?.hour, 6);
      expect(nextAfterSaturday?.minute, 30);

      final sunday = tz.TZDateTime(
        BusSchedule.singaporeLocation,
        2026,
        9,
        13,
        10,
      );
      final nextAfterSunday = BusSchedule.getNextOperatingDayBus(
        sunday,
        Direction.beautyWorldToForett,
      );
      expect(nextAfterSunday?.weekday, DateTime.monday);
      expect(nextAfterSunday?.hour, 6);
      expect(nextAfterSunday?.minute, 37);
    });

    test('preserves UTC and named time zones', () {
      final utcNextBus = BusSchedule.getNextBus(
        DateTime.utc(2026, 9, 14, 6),
        Direction.forettToBeautyWorld,
      );
      final singaporeNow = tz.TZDateTime(
        BusSchedule.singaporeLocation,
        2026,
        9,
        14,
        6,
      );
      final singaporeNextBus = BusSchedule.getNextBus(
        singaporeNow,
        Direction.forettToBeautyWorld,
      );

      expect(utcNextBus, DateTime.utc(2026, 9, 14, 6, 30));
      expect(utcNextBus?.isUtc, isTrue);
      expect(singaporeNextBus, isA<tz.TZDateTime>());
      expect(singaporeNextBus?.timeZoneOffset, const Duration(hours: 8));
      expect(singaporeNextBus?.hour, 6);
      expect(singaporeNextBus?.minute, 30);
    });
  });
}
