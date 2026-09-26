import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'schedule.dart';

/// Settings that belong to the app shell rather than to a trip card.
///
/// The payload is versioned so new settings can be added without making old
/// installations unreadable.
class AppSettings {
  AppSettings.defaults()
    : _preferences = null,
      darkModeEnabled = false,
      direction = Direction.forettToBeautyWorld;

  AppSettings._({
    required this._preferences,
    required this.darkModeEnabled,
    required this.direction,
  });

  static const _storageKey = 'app_settings.v1';

  final SharedPreferences? _preferences;
  bool darkModeEnabled;
  Direction direction;

  static Future<AppSettings> load({SharedPreferences? preferences}) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    var darkModeEnabled = false;
    var direction = Direction.forettToBeautyWorld;

    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          if (decoded['darkModeEnabled'] is bool) {
            darkModeEnabled = decoded['darkModeEnabled'] as bool;
          }
          final directionName = decoded['direction'];
          final parsedDirection = Direction.values.where(
            (value) => value.name == directionName,
          );
          if (parsedDirection.length == 1) {
            direction = parsedDirection.single;
          }
        }
      } on Object {
        // Ignore corrupt settings and use safe defaults.
      }
    }

    return AppSettings._(
      preferences: prefs,
      darkModeEnabled: darkModeEnabled,
      direction: direction,
    );
  }

  Future<void> setDarkModeEnabled(bool enabled) async {
    if (darkModeEnabled == enabled) return;
    darkModeEnabled = enabled;
    await _persist();
  }

  Future<void> setDirection(Direction value) async {
    if (direction == value) return;
    direction = value;
    await _persist();
  }

  Future<void> restoreFromBackup({
    required bool darkModeEnabled,
    required Direction direction,
  }) async {
    final preferences = _preferences;
    if (preferences != null) {
      final saved = await preferences.setString(
        _storageKey,
        jsonEncode({
          'version': 1,
          'darkModeEnabled': darkModeEnabled,
          'direction': direction.name,
        }),
      );
      if (!saved) throw StateError('Could not save app settings');
    }
    this.darkModeEnabled = darkModeEnabled;
    this.direction = direction;
  }

  Future<void> _persist() async {
    try {
      await _preferences?.setString(
        _storageKey,
        jsonEncode({
          'version': 1,
          'darkModeEnabled': darkModeEnabled,
          'direction': direction.name,
        }),
      );
    } on Object {
      // Keep the current in-memory setting if persistence is unavailable.
    }
  }
}
