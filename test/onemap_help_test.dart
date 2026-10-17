import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuttle_bus/main.dart';

void main() {
  testWidgets('profile explains server-only OneMap access and links to setup', (
    tester,
  ) async {
    await tester.pumpWidget(const ShuttleBusApp());
    await tester.pump();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('OneMap access'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('OneMap access'));
    await tester.pumpAndSettle();

    expect(find.textContaining('tokens last 3 days'), findsOneWidget);
    expect(find.textContaining('OneMap email and password'), findsOneWidget);
    expect(find.textContaining('token secret'), findsOneWidget);
    expect(find.text('OneMap token guide'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Deployment instructions'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Open Cloudflare'), findsOneWidget);
    expect(find.text('Deployment instructions'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
