import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'schedule.dart';

class BusReminder {
  const BusReminder({required this.busTime, required this.direction});

  final DateTime busTime;
  final Direction direction;
}

class NotificationService {
  static const int _busReminderId = 0;
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initFuture;
  final ValueNotifier<BusReminder?> activeReminder = ValueNotifier(null);

  Future<void> init() {
    return _initFuture ??= _initializeWithReset();
  }

  Future<void> _initializeWithReset() async {
    try {
      await _initialize();
    } catch (_) {
      _initFuture = null;
      rethrow;
    }
  }

  Future<void> _initialize() async {
    tz.setLocalLocation(BusSchedule.singaporeLocation);

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        );
    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    await _plugin.initialize(settings: initializationSettings);
  }

  Future<bool> requestPermission() async {
    await init();
    final iosResult = await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    final androidImplementation = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidImplementation != null) {
      final notificationsGranted =
          await androidImplementation.requestNotificationsPermission() ?? true;
      if (!notificationsGranted) return false;

      return await androidImplementation.requestExactAlarmsPermission() ?? true;
    }

    return iosResult ?? true;
  }

  Future<bool> scheduleBusReminder(
    DateTime busTime,
    Direction direction,
  ) async {
    await init();
    if (!BusSchedule.isConfirmedOperatingDay(busTime) ||
        !BusSchedule.containsDeparture(busTime, direction)) {
      return false;
    }
    final scheduledTime = busTime.subtract(const Duration(minutes: 5));
    if (!scheduledTime.isAfter(BusSchedule.now())) return false;

    final dirStr = direction == Direction.forettToBeautyWorld
        ? 'Forett'
        : "Beauty World MRT";

    await _plugin.zonedSchedule(
      id: _busReminderId,
      title: 'Bus arriving soon!',
      body: 'The shuttle from $dirStr will depart in 5 minutes.',
      payload: jsonEncode({
        'busTime': busTime.millisecondsSinceEpoch,
        'direction': direction.name,
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
    activeReminder.value = BusReminder(busTime: busTime, direction: direction);
    return true;
  }

  Future<BusReminder?> pendingBusReminder() async {
    await init();
    final requests = await _plugin.pendingNotificationRequests();

    for (final request in requests) {
      if (request.id != _busReminderId || request.payload == null) continue;

      try {
        final payload = jsonDecode(request.payload!);
        if (payload is! Map<String, dynamic>) {
          activeReminder.value = null;
          return null;
        }

        final milliseconds = payload['busTime'];
        final directionName = payload['direction'];
        if (milliseconds is! int || directionName is! String) {
          activeReminder.value = null;
          return null;
        }

        final busTime = tz.TZDateTime.fromMillisecondsSinceEpoch(
          BusSchedule.singaporeLocation,
          milliseconds,
        );
        if (!busTime.isAfter(BusSchedule.now()) ||
            !BusSchedule.isConfirmedOperatingDay(busTime) ||
            !BusSchedule.containsDeparture(
              busTime,
              Direction.values.byName(directionName),
            )) {
          activeReminder.value = null;
          return null;
        }

        final reminder = BusReminder(
          busTime: busTime,
          direction: Direction.values.byName(directionName),
        );
        activeReminder.value = reminder;
        return reminder;
      } catch (_) {
        activeReminder.value = null;
        return null;
      }
    }

    activeReminder.value = null;
    return null;
  }

  void expireReminderIfNeeded(DateTime now) {
    final reminder = activeReminder.value;
    if (reminder != null && !now.isBefore(reminder.busTime)) {
      activeReminder.value = null;
    }
  }

  Future<void> cancelReminder() async {
    await init();
    await _plugin.cancel(id: _busReminderId);
    activeReminder.value = null;
  }

  /// Removes an already scheduled reminder when an imported timetable no
  /// longer contains its departure or marks its day unavailable.
  Future<void> cancelReminderIfInvalid() async {
    final reminder = activeReminder.value ?? await pendingBusReminder();
    if (reminder == null) {
      await init();
      await _plugin.cancel(id: _busReminderId);
      return;
    }
    if (!BusSchedule.isConfirmedOperatingDay(reminder.busTime) ||
        !BusSchedule.containsDeparture(reminder.busTime, reminder.direction)) {
      await cancelReminder();
  }
}
