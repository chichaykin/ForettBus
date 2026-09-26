import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shuttle_bus/app_data_backup.dart';
import 'package:shuttle_bus/schedule.dart';
import 'package:shuttle_bus/trip_cards.dart';

TripCard _card(String id) {
  const start = TransitStop(code: '42221', name: 'Forett');
  const end = TransitStop(code: '18131', name: 'Science Park');
  final plan = TripPlan(
    legs: [
      TripLeg(type: TripLegType.bus, from: start, to: end, services: ['963']),
    ],
  );
  return TripCard(
    id: id,
    title: 'Office',
    originName: 'Forett',
    destinationName: 'Science Park',
    toDestination: plan,
    toOrigin: plan,
  );
}

void main() {
  test(
    'backup round trips local settings, schedule and ordered route cards',
    () {
      final contents = AppDataBackup.encode(
        darkModeEnabled: true,
        direction: Direction.beautyWorldToForett,
        schedule: ShuttleSchedule.original(),
        tripCards: [_card('office'), _card('home')],
      );

      final restored = AppDataBackup.decode(contents);

      expect(restored.darkModeEnabled, isTrue);
      expect(restored.direction, Direction.beautyWorldToForett);
      expect(restored.schedule.toJson(), ShuttleSchedule.original().toJson());
      expect(restored.tripCards.map((card) => card.id), ['office', 'home']);
      expect(restored.tripCards.first.toDestination.legs.single.services, [
        '963',
      ]);
    },
  );

  test('backup rejects unsupported versions and duplicate route IDs', () {
    final backup = AppDataBackup.encode(
      darkModeEnabled: false,
      direction: Direction.forettToBeautyWorld,
      schedule: ShuttleSchedule.original(),
      tripCards: [_card('office')],
    );
    final source = jsonDecode(backup) as Map<String, dynamic>;
    final card = Map<String, dynamic>.from(
      (source['tripCards'] as List).single as Map,
    );
    final duplicate = Map<String, dynamic>.from(source)
      ..['tripCards'] = [card, card];
    final unsupported = Map<String, dynamic>.from(source)..['version'] = 99;

    expect(
      () => AppDataBackup.decode(jsonEncode(unsupported)),
      throwsFormatException,
    );
    expect(
      () => AppDataBackup.decode(jsonEncode(duplicate)),
      throwsFormatException,
    );
  });
}
