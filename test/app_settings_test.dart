import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuttle_bus/app_settings.dart';
import 'package:shuttle_bus/schedule.dart';

void main() {
  test('app settings restore theme and main direction', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    final settings = await AppSettings.load(preferences: preferences);
    expect(settings.darkModeEnabled, isFalse);
    expect(settings.direction, Direction.forettToBeautyWorld);

    await settings.setDarkModeEnabled(true);
    await settings.setDirection(Direction.beautyWorldToForett);

    final restored = await AppSettings.load(preferences: preferences);
    expect(restored.darkModeEnabled, isTrue);
    expect(restored.direction, Direction.beautyWorldToForett);
  });
}
