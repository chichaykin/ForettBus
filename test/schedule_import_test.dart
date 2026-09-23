import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuttle_bus/schedule.dart';
import 'package:shuttle_bus/schedule_import.dart';

void main() {
  tearDown(BusSchedule.resetForTests);

  test('imports the documented CSV shape and preserves its breaks', () {
    final imported = ScheduleImporter.fromCsv('''
forett,beauty_world,break_start,break_end
06:30,06:37,09:30,10:00
06:50,06:57,13:00,14:30
''');

    expect(imported.forettTimes, ['06:30', '06:50']);
    expect(imported.beautyWorldTimes, ['06:37', '06:57']);
    expect(imported.breaks, const [
      ScheduleBreak(start: '09:30', end: '10:00'),
      ScheduleBreak(start: '13:00', end: '14:30'),
    ]);
  });

  test('reports CSV files without break columns for review', () {
    final imported = ScheduleImporter.fromCsv('''
forett,beauty_world
06:30,06:37
''');

    expect(imported.breaks, isEmpty);
    expect(imported.notices.single, contains('no breaks'));
  });

  test('rejects invalid or unordered imported departures', () {
    expect(
      () => ScheduleImporter.fromCsv('''
forett,beauty_world
06:50,06:57
06:30,06:37
'''),
      throwsA(isA<ScheduleImportException>()),
    );
  });

  test('parses a two-column OCR timetable and its driver breaks', () {
    final imported = ScheduleImporter.fromOcrLines(const [
      OcrLine(text: 'FORETT @ BUKIT TIMAH SHUTTLE', centerX: 500),
      OcrLine(
        text: 'Monday to Saturday (Excluding Sunday and PH)',
        centerX: 500,
      ),
      OcrLine(text: 'Forett', centerX: 200),
      OcrLine(text: 'Beauty World', centerX: 800),
      OcrLine(text: '6:30  6:37', centerX: 500),
      OcrLine(text: '6:50  6:57', centerX: 500),
      OcrLine(text: 'Driver break from 0930 – 1000 hrs', centerX: 500),
    ]);

    expect(imported.forettTimes, ['06:30', '06:50']);
    expect(imported.beautyWorldTimes, ['06:37', '06:57']);
    expect(imported.breaks, const [
      ScheduleBreak(start: '09:30', end: '10:00'),
    ]);
  });

  test('requires the known Monday to Saturday photo format', () {
    expect(
      () => ScheduleImporter.fromOcrLines(const [
        OcrLine(text: 'Forett', centerX: 100),
        OcrLine(text: 'Beauty World', centerX: 900),
      ]),
      throwsA(isA<ScheduleImportException>()),
    );
  });

  test('persists a saved local timetable before the next app frame', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await BusSchedule.load(preferences: preferences);
    final modified = ShuttleSchedule.original().copyWith(
      forettTimes: const ['06:45'],
      beautyWorldTimes: const ['06:52'],
      breaks: const [],
    );

    await BusSchedule.save(modified);
    BusSchedule.resetForTests();
    await BusSchedule.load(preferences: preferences);

    expect(BusSchedule.getTimesForDirection(Direction.forettToBeautyWorld), [
      '06:45',
    ]);
    expect(BusSchedule.getTimesForDirection(Direction.beautyWorldToForett), [
      '06:52',
    ]);
  });

  test('does not operate on a bundled Singapore public holiday', () {
    expect(BusSchedule.isOperatingDay(DateTime(2026, 12, 25)), isFalse);
    expect(BusSchedule.hasHolidayCalendarFor(DateTime(2028, 1, 1)), isFalse);
  });
}
