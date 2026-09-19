import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuttle_bus/trip_cards.dart';

TripCard _card(String id) {
  const from = TransitStop(code: '42221', name: 'Forett');
  const transfer = TransitStop(code: '18049', name: 'Opp Science Pk');
  const office = TransitStop(code: '18131', name: 'Science Pk');
  return TripCard(
    id: id,
    title: 'Grab HQ',
    originName: 'Forett',
    destinationName: 'Grab HQ',
    toDestination: TripPlan(
      legs: [
        TripLeg(
          type: TripLegType.bus,
          from: from,
          to: transfer,
          services: ['41', '77'],
        ),
        TripLeg(
          type: TripLegType.bus,
          from: transfer,
          to: office,
          services: ['963'],
        ),
      ],
    ),
    toOrigin: TripPlan(
      legs: [
        TripLeg(
          type: TripLegType.bus,
          from: office,
          to: transfer,
          services: ['963'],
        ),
        TripLeg(
          type: TripLegType.bus,
          from: transfer,
          to: from,
          services: ['41', '77'],
        ),
      ],
    ),
  );
}

void main() {
  test('trip cards round trip plans serialize and restore', () {
    final restored = TripCard.fromJson(_card('grab').toJson());
    expect(restored.id, 'grab');
    expect(restored.toDestination.transferCount, 1);
    expect(restored.toOrigin.legs.first.services, ['963']);
  });

  test('controller persists order and direction independently', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final controller = TripCardsController(preferences: preferences);
    await controller.load();
    await controller.add(_card('grab'));
    await controller.add(_card('home'));
    await controller.selectDirection('grab', TripDirection.toOrigin);
    await controller.reorder(1, 0);

    final restored = TripCardsController(preferences: preferences);
    await restored.load();
    expect(restored.cards.map((card) => card.id), ['home', 'grab']);
    expect(restored.cards.last.selectedDirection, TripDirection.toOrigin);
  });
}
