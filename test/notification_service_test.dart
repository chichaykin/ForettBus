import 'package:flutter_test/flutter_test.dart';
import 'package:shuttle_bus/notification_backend.dart';
import 'package:shuttle_bus/notifications.dart';
import 'package:shuttle_bus/schedule.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBackend implements NotificationBackend {
  BusReminder? reminder;
  bool failInitializationOnce = false;
  bool failCancellation = false;
  int initializationCount = 0;

  @override
  Future<NotificationBackendState> initialize() async {
    initializationCount++;
    if (failInitializationOnce && initializationCount == 1) {
      throw StateError('temporary initialization error');
    }
    return const NotificationBackendState(
      readiness: NotificationReadiness.ready,
      subscribed: true,
    );
  }

  @override
  Future<NotificationBackendState> requestPermission() async =>
      const NotificationBackendState(
        readiness: NotificationReadiness.ready,
        subscribed: true,
      );

  @override
  Future<BusReminder> schedule(BusReminder value) async {
    reminder = BusReminder(
      id: 'server-reminder-id',
      busTime: value.busTime,
      direction: value.direction,
    );
    return reminder!;
  }

  @override
  Future<BusReminder?> pendingReminder() async => reminder;

  @override
  Future<void> cancelReminder({String? reminderId}) async {
    if (failCancellation) throw StateError('offline');
    if (reminderId == null || reminder?.id == reminderId) reminder = null;
  }

  @override
  Future<void> disable() async => reminder = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('initialization can be retried after a platform failure', () async {
    final backend = _FakeBackend()..failInitializationOnce = true;
    final service = NotificationService.withBackend(backend);

    await expectLater(service.init(), throwsStateError);
    await service.init();

    expect(backend.initializationCount, 2);
    expect(service.state.value.readiness, NotificationReadiness.ready);
  });

  test('schedule and cancel update the shared active reminder', () async {
    final backend = _FakeBackend();
    final service = NotificationService.withBackend(backend);
    final direction = Direction.forettToBeautyWorld;
    final departure = BusSchedule.getNextOperatingDayBus(
      BusSchedule.now(),
      direction,
    )!;

    expect(await service.scheduleBusReminder(departure, direction), isTrue);
    expect(service.activeReminder.value?.id, 'server-reminder-id');
    expect(await service.pendingBusReminder(), isNotNull);

    await service.cancelReminder();
    expect(service.activeReminder.value, isNull);
    expect(backend.reminder, isNull);
  });

  test('a restored timetable cancels a now-invalid server reminder', () async {
    final backend = _FakeBackend();
    final service = NotificationService.withBackend(backend);
    final departure = BusSchedule.getNextOperatingDayBus(
      BusSchedule.now(),
      Direction.forettToBeautyWorld,
    )!;
    backend.reminder = BusReminder(
      id: 'server-reminder-id',
      busTime: departure.add(const Duration(minutes: 1)),
      direction: Direction.forettToBeautyWorld,
    );

    expect(await service.pendingBusReminder(), isNull);
    expect(backend.reminder, isNull);
    expect(service.activeReminder.value, isNull);
  });

  test(
    'failed Web cancellation is retried for the specific reminder',
    () async {
      final backend = _FakeBackend()..failCancellation = true;
      final service = NotificationService.withBackend(backend);
      final departure = BusSchedule.getNextOperatingDayBus(
        BusSchedule.now(),
        Direction.forettToBeautyWorld,
      )!;
      await service.scheduleBusReminder(
        departure,
        Direction.forettToBeautyWorld,
      );

      await expectLater(service.cancelReminder(), throwsStateError);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString('pending_notification_cancel.v1'),
        'server-reminder-id',
      );

      backend.failCancellation = false;
      final restarted = NotificationService.withBackend(backend);
      await restarted.init();
      expect(preferences.getString('pending_notification_cancel.v1'), isNull);
    },
  );
}
