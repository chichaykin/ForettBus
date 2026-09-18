import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:shuttle_bus/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Shuttle Bus App Integration Tests', () {
    testWidgets('App starts and shows Home screen', (tester) async {
      await app.main();
      await tester.pumpAndSettle();

      // Check if Home tab is selected and displays correctly
      expect(find.textContaining('Forett to'), findsWidgets);
      // The "Remind me" button only appears if there is an upcoming bus today.
      // At night (after 19:20) or on Sundays, it might show "Service Ended" or "No Bus Today".
      final hasButton = find.byType(ElevatedButton).evaluate().isNotEmpty;
      if (!hasButton) {
        expect(
          find.text('Service ended').evaluate().isNotEmpty ||
              find.text('No shuttle today').evaluate().isNotEmpty,
          isTrue,
        );
      }
    });

    testWidgets('Can navigate to Schedule screen and switch directions', (
      tester,
    ) async {
      await app.main();
      await tester.pumpAndSettle();

      // Tap on the Schedule tab in BottomNavigationBar
      await tester.tap(find.text('Schedule').last);
      await tester.pumpAndSettle();

      // Verify we are on Schedule screen
      expect(find.text('Full Schedule'), findsOneWidget);

      // Verify default direction is 'To Beauty World'
      expect(find.text('06:30'), findsWidgets);

      // Switch to 'To Forett'
      await tester.tap(find.text('To Forett'));
      await tester.pumpAndSettle();

      // Verify schedule updated to Beauty World to Forett times
      expect(find.text('06:37'), findsWidgets);
    });

    testWidgets('Can navigate to Profile screen', (tester) async {
      await app.main();
      await tester.pumpAndSettle();

      // Tap on the Profile tab
      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle();

      // Verify we are on Profile screen
      expect(find.text('Resident'), findsOneWidget);
      expect(find.text('Management Office'), findsOneWidget);
    });
  });
}
