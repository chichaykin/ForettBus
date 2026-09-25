import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'notification_backend.dart';
import 'notification_backend_factory.dart';
import 'schedule.dart';

export 'notification_backend.dart'
    show BusReminder, NotificationBackendState, NotificationReadiness;

class NotificationService {
  static const _pendingCancelKey = 'pending_notification_cancel.v1';
  static const _activeReminderKey = 'active_notification_reminder.v1';
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal() : _backend = createNotificationBackend();

  @visibleForTesting
  NotificationService.withBackend(NotificationBackend backend)
    : _backend = backend;

  final NotificationBackend _backend;
  Future<void>? _initFuture;
  int _operationRevision = 0;

  final ValueNotifier<BusReminder?> activeReminder = ValueNotifier(null);
  final ValueNotifier<NotificationBackendState> state = ValueNotifier(
    const NotificationBackendState(),
  );
  final ValueNotifier<bool> operationInProgress = ValueNotifier(false);

  Future<void> init() => _initFuture ??= _initializeWithReset();

  Future<void> _initializeWithReset() async {
    try {
      await _restoreLocalReminder();
      state.value = await _backend.initialize();
      await _retryPendingCancellation();
    } on Object {
      _initFuture = null;
      rethrow;
    }
  }

  Future<bool> requestPermission() async {
    final revision = ++_operationRevision;
    operationInProgress.value = true;
    try {
      // The Web backend invokes the browser prompt before awaiting network I/O
      // so Safari keeps the originating user gesture.
      final next = await _backend.requestPermission();
      if (revision == _operationRevision) state.value = next;
      return next.readiness == NotificationReadiness.ready;
    } on Object catch (error) {
      if (revision == _operationRevision) {
        state.value = NotificationBackendState(
          readiness: state.value.readiness,
          subscribed: state.value.subscribed,
          syncError: error.toString(),
        );
      }
      rethrow;
    } finally {
      if (revision == _operationRevision) operationInProgress.value = false;
    }
  }

  Future<bool> scheduleBusReminder(
    DateTime busTime,
    Direction direction,
  ) async {
    if (!BusSchedule.isConfirmedOperatingDay(busTime) ||
        !BusSchedule.containsDeparture(busTime, direction)) {
      return false;
    }
    if (!busTime
        .subtract(const Duration(minutes: 5))
        .isAfter(BusSchedule.now())) {
      return false;
    }
    await init();
    final revision = ++_operationRevision;
    operationInProgress.value = true;
    final reminder = BusReminder(busTime: busTime, direction: direction);
    try {
      final savedReminder = await _backend.schedule(reminder);
      if (revision == _operationRevision) {
        activeReminder.value = savedReminder;
        await _saveActiveReminder(savedReminder);
      }
      return true;
    } finally {
      if (revision == _operationRevision) operationInProgress.value = false;
    }
  }

  Future<BusReminder?> pendingBusReminder() async {
    await init();
    final reminder = await _backend.pendingReminder();
    if (reminder == null ||
        !reminder.busTime.isAfter(BusSchedule.now()) ||
        !BusSchedule.isConfirmedOperatingDay(reminder.busTime) ||
        !BusSchedule.containsDeparture(reminder.busTime, reminder.direction)) {
      activeReminder.value = null;
      await _clearActiveReminder();
      return null;
    }
    activeReminder.value = reminder;
    await _saveActiveReminder(reminder);
    return reminder;
  }

  void expireReminderIfNeeded(DateTime now) {
    final reminder = activeReminder.value;
    if (reminder != null && !now.isBefore(reminder.busTime)) {
      activeReminder.value = null;
    }
  }

  Future<void> cancelReminder() async {
    final revision = ++_operationRevision;
    operationInProgress.value = true;
    final reminderId = activeReminder.value?.id;
    try {
      await init();
      await _backend.cancelReminder(reminderId: reminderId);
      await _clearPendingCancellation();
      await _clearActiveReminder();
      if (revision == _operationRevision) activeReminder.value = null;
    } on Object {
      if (reminderId != null) {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(_pendingCancelKey, reminderId);
      }
      rethrow;
    } finally {
      if (revision == _operationRevision) operationInProgress.value = false;
    }
  }

  Future<void> disableNotifications() async {
    await init();
    await _backend.disable();
    await _clearActiveReminder();
    activeReminder.value = null;
    state.value = NotificationBackendState(readiness: state.value.readiness);
  }

  Future<void> cancelReminderIfInvalid() async {
    final reminder = activeReminder.value ?? await pendingBusReminder();
    if (reminder == null) return;
    if (!BusSchedule.isConfirmedOperatingDay(reminder.busTime) ||
        !BusSchedule.containsDeparture(reminder.busTime, reminder.direction)) {
      await cancelReminder();
    }
  }

  Future<void> _retryPendingCancellation() async {
    final preferences = await SharedPreferences.getInstance();
    final reminderId = preferences.getString(_pendingCancelKey);
    if (reminderId == null || reminderId.isEmpty) return;
    try {
      await _backend.cancelReminder(reminderId: reminderId);
      await preferences.remove(_pendingCancelKey);
      if (activeReminder.value?.id == reminderId) activeReminder.value = null;
    } on Object {
      // Keep the specific reminder ID. A later initialization retries it and
      // cannot accidentally cancel a newer reminder.
    }
  }

  Future<void> _clearPendingCancellation() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_pendingCancelKey);
  }

  Future<void> _saveActiveReminder(BusReminder reminder) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _activeReminderKey,
      jsonEncode({
        'id': reminder.id,
        'busTime': reminder.busTime.millisecondsSinceEpoch,
        'direction': reminder.direction.name,
      }),
    );
  }

  Future<void> _restoreLocalReminder() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_activeReminderKey);
    if (raw == null) return;
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          value['busTime'] is! int ||
          value['direction'] is! String) {
        throw const FormatException('Invalid reminder');
      }
      final reminder = BusReminder(
        id: value['id'] is String ? value['id'] as String : null,
        busTime: tz.TZDateTime.fromMillisecondsSinceEpoch(
          BusSchedule.singaporeLocation,
          value['busTime'] as int,
        ),
        direction: Direction.values.byName(value['direction'] as String),
      );
      if (!reminder.busTime.isAfter(BusSchedule.now()) ||
          !BusSchedule.isConfirmedOperatingDay(reminder.busTime) ||
          !BusSchedule.containsDeparture(
            reminder.busTime,
            reminder.direction,
          )) {
        await preferences.remove(_activeReminderKey);
        return;
      }
      activeReminder.value = reminder;
    } on Object {
      await preferences.remove(_activeReminderKey);
    }
  }

  Future<void> _clearActiveReminder() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_activeReminderKey);
  }
}
