import 'dart:convert';

import 'schedule.dart';
import 'trip_cards.dart';

class AppDataBackup {
  const AppDataBackup({
    required this.darkModeEnabled,
    required this.direction,
    required this.schedule,
    required this.tripCards,
  });

  static const format = 'forett-shuttle-backup';
  static const currentVersion = 1;
  static const maxBytes = 2 * 1024 * 1024;
  static const maxTripCards = 500;

  final bool darkModeEnabled;
  final Direction direction;
  final ShuttleSchedule schedule;
  final List<TripCard> tripCards;

  static String encode({
    required bool darkModeEnabled,
    required Direction direction,
    required ShuttleSchedule schedule,
    required List<TripCard> tripCards,
  }) => jsonEncode({
    'format': format,
    'version': currentVersion,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'settings': {
      'darkModeEnabled': darkModeEnabled,
      'direction': direction.name,
    },
    'schedule': schedule.toJson(),
    'tripCards': tripCards.map((card) => card.toJson()).toList(),
  });

  static AppDataBackup decode(String contents) {
    if (utf8.encode(contents).length > maxBytes) {
      throw const FormatException('Backup file is too large');
    }
    final decoded = jsonDecode(contents);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != format ||
        decoded['version'] != currentVersion) {
      throw const FormatException('Unsupported backup file');
    }
    final settings = decoded['settings'];
    final rawSchedule = decoded['schedule'];
    final rawCards = decoded['tripCards'];
    if (settings is! Map<String, dynamic> ||
        settings['darkModeEnabled'] is! bool ||
        rawSchedule is! Map<String, dynamic> ||
        rawCards is! List ||
        rawCards.length > maxTripCards) {
      throw const FormatException('Invalid backup contents');
    }
    final directionName = settings['direction'];
    final directions = Direction.values.where(
      (value) => value.name == directionName,
    );
    if (directions.length != 1) {
      throw const FormatException('Invalid saved direction');
    }
    final cards = <TripCard>[];
    final ids = <String>{};
    for (final rawCard in rawCards) {
      if (rawCard is! Map<String, dynamic>) {
        throw const FormatException('Invalid saved route card');
      }
      final card = TripCard.fromJson(rawCard);
      if (!ids.add(card.id)) {
        throw const FormatException('Duplicate saved route card');
      }
      cards.add(card);
    }

    return AppDataBackup(
      darkModeEnabled: settings['darkModeEnabled'] as bool,
      direction: directions.single,
      schedule: ShuttleSchedule.fromJson(rawSchedule),
      tripCards: List.unmodifiable(cards),
    );
  }
}
