import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'notification_backend.dart';
import 'schedule.dart';

const int _busReminderId = 0;

NotificationBackend createBackend() => NativeNotificationBackend();

class NativeNotificationBackend implements NotificationBackend {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  @override
  Future<NotificationBackendState> initialize() async {
    tz.setLocalLocation(BusSchedule.singaporeLocation);
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings: settings);
    return const NotificationBackendState(
      readiness: NotificationReadiness.ready,
    );
  }

  @override
  Future<NotificationBackendState> requestPermission() async {
    final iosResult = await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      final notifications =
          await android.requestNotificationsPermission() ?? true;
      if (!notifications) {
        return const NotificationBackendState(
          readiness: NotificationReadiness.permissionDenied,
        );
      }
      final exact = await android.requestExactAlarmsPermission() ?? true;
      return NotificationBackendState(
        readiness: exact
            ? NotificationReadiness.ready
            : NotificationReadiness.permissionDenied,
        subscribed: exact,
      );
    }
    return NotificationBackendState(
      readiness: iosResult == false
          ? NotificationReadiness.permissionDenied
          : NotificationReadiness.ready,
      subscribed: iosResult != false,
    );
  }

  @override
  Future<BusReminder> schedule(BusReminder reminder) async {
    final scheduledTime = reminder.busTime.subtract(const Duration(minutes: 5));
    final departure = reminder.direction == Direction.forettToBeautyWorld
        ? 'Forett'
        : 'Beauty World MRT';
    await _plugin.zonedSchedule(
      id: _busReminderId,
      title: 'Bus arriving soon!',
      body: 'The shuttle from $departure will depart in 5 minutes.',
      payload: jsonEncode({
        'busTime': reminder.busTime.millisecondsSinceEpoch,
        'direction': reminder.direction.name,
      }),
      scheduledDate: tz.TZDateTime.from(scheduledTime, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'bus_reminder_channel',
          'Bus Reminders',
          channelDescription: 'Reminders for shuttle bus departures',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
    return reminder;
  }

  @override
  Future<BusReminder?> pendingReminder() async {
    final requests = await _plugin.pendingNotificationRequests();
    for (final request in requests) {
      if (request.id != _busReminderId || request.payload == null) continue;
      try {
        final payload = jsonDecode(request.payload!);
        if (payload is! Map<String, dynamic>) return null;
        final milliseconds = payload['busTime'];
        final directionName = payload['direction'];
        if (milliseconds is! int || directionName is! String) return null;
        return BusReminder(
          busTime: tz.TZDateTime.fromMillisecondsSinceEpoch(
            BusSchedule.singaporeLocation,
            milliseconds,
          ),
          direction: Direction.values.byName(directionName),
        );
      } on Object {
        return null;
      }
    }
    return null;
  }

  @override
  Future<void> cancelReminder({String? reminderId}) =>
      _plugin.cancel(id: _busReminderId);

  @override
  Future<void> disable() => cancelReminder();
}
