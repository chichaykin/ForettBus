import 'dart:convert';

import 'schedule.dart';

class OcrLine {
  const OcrLine({required this.text, required this.centerX});

  final String text;
  final double centerX;
}

class ImportedSchedule {
  const ImportedSchedule({
    required this.forettTimes,
    required this.beautyWorldTimes,
    required this.breaks,
    required this.notices,
  });

  final List<String> forettTimes;
  final List<String> beautyWorldTimes;
  final List<ScheduleBreak> breaks;
  final List<String> notices;

  ShuttleSchedule withHolidayCalendar(ShuttleSchedule existing) =>
      ShuttleSchedule(
        forettTimes: forettTimes,
        beautyWorldTimes: beautyWorldTimes,
        breaks: breaks,
        holidayDates: existing.holidayDates,
        holidayStartYear: existing.holidayStartYear,
        holidayEndYear: existing.holidayEndYear,
      );
}

class ScheduleImportException implements Exception {
  const ScheduleImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ScheduleImporter {
  static final _timePattern = RegExp(
    r'(?<![0-9])([01]?[0-9]|2[0-3])[:.]([0-5][0-9])(?![0-9])',
  );
  static final _compactBreakPattern = RegExp(
    r'(?<![0-9])([01]?[0-9]|2[0-3])([0-5][0-9]) *[-–—] *([01]?[0-9]|2[0-3])([0-5][0-9])(?![0-9])',
  );

  static ImportedSchedule fromCsv(String source) {
    final lines = const LineSplitter()
        .convert(source)
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      throw const ScheduleImportException('The CSV file is empty.');
    }
    final header = _csvRow(
      lines.first,
    ).map((item) => item.trim().toLowerCase()).toList();
    final forettIndex = header.indexOf('forett');
    final beautyIndex = header.indexOf('beauty_world');
    if (forettIndex == -1 || beautyIndex == -1) {
      throw const ScheduleImportException(
        'CSV needs forett and beauty_world columns.',
      );
    }
    final breakStartIndex = header.indexOf('break_start');
    final breakEndIndex = header.indexOf('break_end');
    if ((breakStartIndex == -1) != (breakEndIndex == -1)) {
      throw const ScheduleImportException(
        'CSV needs both break_start and break_end columns.',
      );
    }

    final forett = <String>[];
    final beauty = <String>[];
    final breaks = <ScheduleBreak>[];
    for (var rowIndex = 1; rowIndex < lines.length; rowIndex++) {
      final row = _csvRow(lines[rowIndex]);
      String valueAt(int index) => index < row.length ? row[index].trim() : '';
      final forettTime = _normalizeTime(valueAt(forettIndex));
      final beautyTime = _normalizeTime(valueAt(beautyIndex));
      if (forettTime.isEmpty && beautyTime.isEmpty) continue;
      if (forettTime.isEmpty || beautyTime.isEmpty) {
        throw ScheduleImportException(
          'Row ${rowIndex + 1} needs both departure times.',
        );
      }
      forett.add(forettTime);
      beauty.add(beautyTime);
      if (breakStartIndex != -1) {
        final start = _normalizeTime(valueAt(breakStartIndex));
        final end = _normalizeTime(valueAt(breakEndIndex));
        if (start.isEmpty && end.isEmpty) continue;
        if (start.isEmpty || end.isEmpty) {
          throw ScheduleImportException(
            'Row ${rowIndex + 1} has an incomplete break.',
          );
        }
        final item = ScheduleBreak(start: start, end: end);
        if (!breaks.contains(item)) breaks.add(item);
      }
    }
    final notices = <String>[];
    if (breakStartIndex == -1) {
      notices.add(
        'This CSV has no breaks. Review the empty break list before saving.',
      );
    }
    final result = ImportedSchedule(
      forettTimes: forett,
      beautyWorldTimes: beauty,
      breaks: breaks,
      notices: notices,
    );
    _validateImported(result);
    return result;
  }

  /// Parses the two-column printed timetable shown at Forett. OCR coordinates
  /// are used to keep the left and right columns separate.
  static ImportedSchedule fromOcrLines(List<OcrLine> source) {
    if (source.isEmpty) {
      throw const ScheduleImportException('No text was found in this photo.');
    }
    final allText = source.map((item) => item.text).join(' ').toLowerCase();
    if (!allText.contains('monday') || !allText.contains('saturday')) {
      throw const ScheduleImportException(
        'The photo must say that the service runs Monday to Saturday. Review a clearer timetable photo.',
      );
    }
    if (!allText.contains('forett') || !allText.contains('beauty')) {
      throw const ScheduleImportException(
        'Could not find the Forett and Beauty World column headings.',
      );
    }
    if (allText.contains('including sunday') &&
        !allText.contains('excluding sunday')) {
      throw const ScheduleImportException(
        'This photo describes a different service-week rule. It was not imported.',
      );
    }

    final timeLines = <OcrLine>[];
    final breaks = <ScheduleBreak>[];
    for (final line in source) {
      final lower = line.text.toLowerCase();
      if (lower.contains('break')) {
        final item = _breakFromText(line.text);
        if (item != null && !breaks.contains(item)) {
          breaks.add(item);
        }
        continue;
      }
      if (_timePattern.hasMatch(line.text)) timeLines.add(line);
    }
    if (timeLines.length < 2) {
      throw const ScheduleImportException(
        'Too few departure times were read from the photo.',
      );
    }
    final positions = timeLines.map((item) => item.centerX).toList()..sort();
    final divider = positions[positions.length ~/ 2];
    final forett = <String>[];
    final beauty = <String>[];
    for (final line in timeLines) {
      final times = _timesIn(line.text);
      if (times.length == 2) {
        forett.add(times.first);
        beauty.add(times.last);
      } else if (times.length == 1) {
        (line.centerX < divider ? forett : beauty).add(times.single);
      }
    }
    forett.sort();
    beauty.sort();
    final notices = <String>[
      'Check every result against the photo before saving. OCR can misread digits.',
    ];
    if (forett.length != beauty.length) {
      notices.add(
        'The two columns have different numbers of departures. Add or remove rows before saving.',
      );
    }
    if (breaks.isEmpty) {
      notices.add(
        'No driver breaks were recognized. Add them if the photo lists breaks.',
      );
    }
    final result = ImportedSchedule(
      forettTimes: forett,
      beautyWorldTimes: beauty,
      breaks: breaks..sort((a, b) => a.start.compareTo(b.start)),
      notices: notices,
    );
    _validateImported(result);
    return result;
  }

  static String exportCsv(ShuttleSchedule schedule) {
    final lines = <String>['forett,beauty_world,break_start,break_end'];
    final count = [
      schedule.forettTimes.length,
      schedule.beautyWorldTimes.length,
      schedule.breaks.length,
    ].reduce((a, b) => a > b ? a : b);
    for (var index = 0; index < count; index++) {
      final breakItem = index < schedule.breaks.length
          ? schedule.breaks[index]
          : null;
      lines.add(
        [
          index < schedule.forettTimes.length
              ? schedule.forettTimes[index]
              : '',
          index < schedule.beautyWorldTimes.length
              ? schedule.beautyWorldTimes[index]
              : '',
          breakItem?.start ?? '',
          breakItem?.end ?? '',
        ].join(','),
      );
    }
    return '${lines.join('\\n')}\\n';
  }

  static void _validateImported(ImportedSchedule value) {
    final errors = value
        .withHolidayCalendar(ShuttleSchedule.original())
        .validate();
    if (errors.isNotEmpty) throw ScheduleImportException(errors.first);
  }

  static ScheduleBreak? _breakFromText(String text) {
    final compact = _compactBreakPattern.firstMatch(text);
    if (compact != null) {
      return ScheduleBreak(
        start: '${compact.group(1)!.padLeft(2, '0')}:${compact.group(2)!}',
        end: '${compact.group(3)!.padLeft(2, '0')}:${compact.group(4)!}',
      );
    }
    final times = _timesIn(text);
    return times.length >= 2
        ? ScheduleBreak(start: times[0], end: times[1])
        : null;
  }

  static List<String> _timesIn(String value) => _timePattern
      .allMatches(value)
      .map((match) => '${match.group(1)!.padLeft(2, '0')}:${match.group(2)!}')
      .toList();

  static String _normalizeTime(String value) {
    if (value.isEmpty) return '';
    final matches = _timesIn(value);
    if (matches.length != 1) return value;
    return matches.single;
  }

  static List<String> _csvRow(String line) {
    final values = <String>[];
    var current = StringBuffer();
    var quoted = false;
    for (var index = 0; index < line.length; index++) {
      final char = line[index];
      if (char == '"') {
        if (quoted && index + 1 < line.length && line[index + 1] == '"') {
          current.write('"');
          index++;
        } else {
          quoted = !quoted;
        }
      } else if (char == ',' && !quoted) {
        values.add(current.toString());
        current = StringBuffer();
      } else {
        current.write(char);
      }
    }
    values.add(current.toString());
    return values;
  }
}
