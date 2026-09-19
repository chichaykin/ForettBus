import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// OneMap supplies labels such as "TTS BUS 963"; LTA accepts "963".
String? normalizeBusService(String value) {
  final trimmed = value.trim();
  final labelled = RegExp(
    r'^(?:[A-Za-z]+\s+)?BUS\s+(.+)$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  final service = (labelled?.group(1) ?? trimmed).trim();
  return RegExp(r'^\d{1,4}[A-Za-z]?$').hasMatch(service) ? service : null;
}

String normalizeStopCode(String value) =>
    value.trim().replaceFirst(RegExp(r'^[A-Za-z]+:(?=\d{5}$)'), '');

String displayPlaceName(String value) {
  if (value != value.toUpperCase()) return value;
  const acronyms = {'MRT', 'SMRT', 'HQ', 'NUS', 'NTU', 'ITE'};
  return value
      .split(' ')
      .map(
        (word) => word.isEmpty || acronyms.contains(word)
            ? word
            : '${word[0]}${word.substring(1).toLowerCase()}',
      )
      .join(' ');
}

enum TripDirection { toDestination, toOrigin }

enum TripLegType { walk, bus }

class TransitStop {
  const TransitStop({required this.code, required this.name});

  final String code;
  final String name;

  Map<String, dynamic> toJson() => {'code': code, 'name': name};

  factory TransitStop.fromJson(Map<String, dynamic> json) {
    final code = json['code'];
    final name = json['name'];
    if (code is! String ||
        name is! String ||
        code.trim().isEmpty ||
        name.trim().isEmpty) {
      throw const FormatException('Invalid transit stop');
    }
    return TransitStop(code: normalizeStopCode(code), name: name.trim());
  }
}

class TripLeg {
  const TripLeg({
    required this.type,
    required this.from,
    required this.to,
    this.services = const <String>[],
    this.durationMinutes,
  });

  final TripLegType type;
  final TransitStop from;
  final TransitStop to;
  final List<String> services;
  final int? durationMinutes;

  bool get isBus => type == TripLegType.bus;

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'from': from.toJson(),
    'to': to.toJson(),
    'services': services,
    'durationMinutes': durationMinutes,
  };

  factory TripLeg.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'];
    final type = TripLegType.values.where((value) => value.name == typeName);
    final from = json['from'];
    final to = json['to'];
    final services = json['services'];
    if (type.length != 1 ||
        from is! Map<String, dynamic> ||
        to is! Map<String, dynamic>) {
      throw const FormatException('Invalid trip leg');
    }
    final parsedServices = services is List
        ? services
              .whereType<String>()
              .map(normalizeBusService)
              .whereType<String>()
              .toSet()
              .toList()
        : <String>[];
    final duration = json['durationMinutes'];
    return TripLeg(
      type: type.single,
      from: TransitStop.fromJson(from),
      to: TransitStop.fromJson(to),
      services: List.unmodifiable(parsedServices),
      durationMinutes: duration is int && duration >= 0 ? duration : null,
    );
  }
}

class TripPlan {
  const TripPlan({required this.legs, this.durationMinutes});

  final List<TripLeg> legs;
  final int? durationMinutes;

  int get transferCount => legs.where((leg) => leg.isBus).isNotEmpty
      ? legs.where((leg) => leg.isBus).length - 1
      : 0;

  Map<String, dynamic> toJson() => {
    'legs': legs.map((leg) => leg.toJson()).toList(),
    'durationMinutes': durationMinutes,
  };

  factory TripPlan.fromJson(Map<String, dynamic> json) {
    final legs = json['legs'];
    if (legs is! List) throw const FormatException('Invalid trip plan');
    final parsed = legs
        .whereType<Map<String, dynamic>>()
        .map(TripLeg.fromJson)
        .toList(growable: false);
    if (parsed.isEmpty) throw const FormatException('Trip plan has no legs');
    final duration = json['durationMinutes'];
    return TripPlan(
      legs: List.unmodifiable(parsed),
      durationMinutes: duration is int && duration >= 0 ? duration : null,
    );
  }
}

class TripCard {
  const TripCard({
    required this.id,
    required this.title,
    required this.originName,
    required this.destinationName,
    required this.toDestination,
    required this.toOrigin,
    this.selectedDirection = TripDirection.toDestination,
  });

  final String id;
  final String title;
  final String originName;
  final String destinationName;
  final TripPlan toDestination;
  final TripPlan toOrigin;
  final TripDirection selectedDirection;

  TripPlan get selectedPlan => selectedDirection == TripDirection.toDestination
      ? toDestination
      : toOrigin;

  // The card name is the user's short location label; keep the address in settings.
  String get destinationLabel => displayPlaceName(title);
  String get originLabel => displayPlaceName(originName);

  String get selectedLabel => selectedDirection == TripDirection.toDestination
      ? 'To $destinationLabel'
      : 'To $originLabel';

  TripCard copyWith({
    String? id,
    String? title,
    String? originName,
    String? destinationName,
    TripPlan? toDestination,
    TripPlan? toOrigin,
    TripDirection? selectedDirection,
  }) {
    return TripCard(
      id: id ?? this.id,
      title: title ?? this.title,
      originName: originName ?? this.originName,
      destinationName: destinationName ?? this.destinationName,
      toDestination: toDestination ?? this.toDestination,
      toOrigin: toOrigin ?? this.toOrigin,
      selectedDirection: selectedDirection ?? this.selectedDirection,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'originName': originName,
    'destinationName': destinationName,
    'toDestination': toDestination.toJson(),
    'toOrigin': toOrigin.toJson(),
    'selectedDirection': selectedDirection.name,
  };

  factory TripCard.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final originName = json['originName'];
    final destinationName = json['destinationName'];
    final toDestination = json['toDestination'];
    final toOrigin = json['toOrigin'];
    final selected = json['selectedDirection'];
    final directions = TripDirection.values.where(
      (value) => value.name == selected,
    );
    if ([
          id,
          title,
          originName,
          destinationName,
        ].any((value) => value is! String) ||
        toDestination is! Map<String, dynamic> ||
        toOrigin is! Map<String, dynamic> ||
        directions.length != 1) {
      throw const FormatException('Invalid trip card');
    }
    return TripCard(
      id: id,
      title: title,
      originName: originName,
      destinationName: destinationName,
      toDestination: TripPlan.fromJson(toDestination),
      toOrigin: TripPlan.fromJson(toOrigin),
      selectedDirection: directions.single,
    );
  }
}

class TripCardsController extends ChangeNotifier {
  TripCardsController({this._preferences});

  static const _storageKey = 'trip_cards.v1';
  SharedPreferences? _preferences;
  final List<TripCard> _cards = [];
  bool _isLoaded = false;

  List<TripCard> get cards => List.unmodifiable(_cards);
  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    if (_isLoaded) return;
    try {
      _preferences ??= await SharedPreferences.getInstance();
      final raw = _preferences!.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _cards
            ..clear()
            ..addAll(
              decoded.whereType<Map<String, dynamic>>().map((item) {
                try {
                  return TripCard.fromJson(item);
                } on Object {
                  return null;
                }
              }).whereType<TripCard>(),
            );
        }
      }
    } on Object {
      // Corrupt or unavailable preferences must not prevent the app from starting.
    }
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> add(TripCard card) async {
    _cards.add(card);
    await _persist();
    notifyListeners();
  }

  Future<void> update(TripCard card) async {
    final index = _cards.indexWhere((item) => item.id == card.id);
    if (index < 0) return;
    _cards[index] = card;
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _cards.removeWhere((card) => card.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _cards.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0 || newIndex >= _cards.length) return;
    final card = _cards.removeAt(oldIndex);
    _cards.insert(newIndex, card);
    await _persist();
    notifyListeners();
  }

  Future<void> selectDirection(String id, TripDirection direction) async {
    final card = _cards.where((item) => item.id == id).firstOrNull;
    if (card == null || card.selectedDirection == direction) return;
    await update(card.copyWith(selectedDirection: direction));
  }

  Future<void> _persist() async {
    try {
      _preferences ??= await SharedPreferences.getInstance();
      await _preferences!.setString(
        _storageKey,
        jsonEncode(_cards.map((card) => card.toJson()).toList()),
      );
    } on Object {
      // Keep the in-memory model available if persistence is unavailable.
    }
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
