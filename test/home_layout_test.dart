import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuttle_bus/trip_cards.dart';
import 'package:shuttle_bus/widgets/trip_card_view.dart';

import 'support/home_layout_fixture.dart';
import 'support/trip_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TripCardsController controller;
  late PreviewTripArrivals repository;

  setUpAll(() async {
    final font = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    await font.load();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    controller = TripCardsController(
      preferences: await SharedPreferences.getInstance(),
    );
    await controller.load();
    repository = PreviewTripArrivals();
  });

  tearDown(() {
    controller.dispose();
    repository.close();
  });

  Future<void> pumpHome(
    WidgetTester tester, {
    double width = 448,
    double height = 998,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 32, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 32, bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await tester.pumpWidget(
      HomeLayoutPreview(
        controller: controller,
        tripRepository: repository,
        textScale: scale,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  ScrollPosition position(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('home-scroll')),
          matching: find.byType(Scrollable),
        ),
      )
      .position;

  testWidgets('two cards fill Home; three fit above the navigation', (
    tester,
  ) async {
    await pumpHome(tester);
    final largeHeight = tester
        .getSize(find.byKey(const Key('shuttle-card')))
        .height;
    expect(position(tester).maxScrollExtent, 0);
    expect(
      tester.getBottomLeft(find.text('Public buses')).dy,
      lessThan(tester.getTopLeft(find.byType(NavigationBar)).dy),
    );

    await controller.add(testTripCard);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.getSize(find.byKey(const Key('shuttle-card'))).height,
      lessThan(largeHeight),
    );
    expect(position(tester).maxScrollExtent, 0);
    expect(
      tester.getBottomLeft(find.text('Route details')).dy,
      lessThan(tester.getTopLeft(find.byType(NavigationBar)).dy),
    );
    expect(find.text('Departs at 09:10'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Route details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(position(tester).maxScrollExtent, greaterThan(0));
    await tester.ensureVisible(find.text('Change to bus 41'));
    expect(find.text('Change to bus 41'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('stack expands trips and preserves their independent direction', (
    tester,
  ) async {
    await controller.add(testTripCard);
    await controller.add(testTripCard.copyWith(id: 'office', title: 'Office'));
    await pumpHome(tester);
    expect(
      tester
          .widget<TripCardView>(find.byKey(const ValueKey('office')))
          .collapsed,
      isTrue,
    );
    await tester.ensureVisible(find.byTooltip('Show Office trip'));
    await tester.tap(find.byTooltip('Show Office trip'));
    await tester.pump();
    final officeCard = find.byKey(const ValueKey('office'));
    expect(tester.widget<TripCardView>(officeCard).collapsed, isFalse);
    final toOffice = find.descendant(
      of: officeCard,
      matching: find.text('To Office'),
    );
    await tester.ensureVisible(toOffice);
    await tester.tap(toOffice);
    await tester.pump();
    expect(
      controller.cards.last.selectedDirection,
      TripDirection.toDestination,
    );
    expect(controller.cards.first.selectedDirection, TripDirection.toOrigin);
    await controller.remove('office');
    await tester.pump();
    expect(find.text('Grab HQ'), findsOneWidget);
    expect(find.byTooltip('Hide Grab HQ trip'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('three cards fit the shorter Pixel CI viewport', (tester) async {
    await controller.add(testTripCard);
    await pumpHome(tester, width: 412, height: 892);
    expect(position(tester).maxScrollExtent, 0);
    expect(
      tester.getBottomLeft(find.text('Route details')).dy,
      lessThan(tester.getTopLeft(find.byType(NavigationBar)).dy),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Home listens to a replacement trip controller', (tester) async {
    await pumpHome(tester);
    final replacement = TripCardsController(
      preferences: await SharedPreferences.getInstance(),
    );
    await replacement.load();
    await tester.pumpWidget(
      HomeLayoutPreview(controller: replacement, tripRepository: repository),
    );
    await tester.pump();
    await replacement.add(testTripCard);
    await tester.pump();
    expect(find.text('Grab HQ'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    replacement.dispose();
  });

  testWidgets('narrow Home with large text scrolls without clipping actions', (
    tester,
  ) async {
    await controller.add(testTripCard);
    await pumpHome(tester, width: 320, scale: 1.5);
    expect(position(tester).maxScrollExtent, greaterThan(0));
    await tester.ensureVisible(find.text('Route details'));
    await tester.tap(find.text('Route details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(find.text('Change to bus 41'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
