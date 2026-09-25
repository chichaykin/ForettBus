import 'schedule.dart';

class BusReminder {
  const BusReminder({required this.busTime, required this.direction, this.id});

  final DateTime busTime;
  final Direction direction;
  final String? id;
}

enum NotificationReadiness {
  unknown,
  unsupported,
  installRequired,
  permissionDenied,
  ready,
}

class NotificationBackendState {
  const NotificationBackendState({
    this.readiness = NotificationReadiness.unknown,
    this.subscribed = false,
    this.syncError,
  });

  final NotificationReadiness readiness;
  final bool subscribed;
  final String? syncError;
}

abstract class NotificationBackend {
  Future<NotificationBackendState> initialize();
  Future<NotificationBackendState> requestPermission();
  Future<BusReminder> schedule(BusReminder reminder);
  Future<BusReminder?> pendingReminder();
  Future<void> cancelReminder({String? reminderId});
  Future<void> disable();
}
