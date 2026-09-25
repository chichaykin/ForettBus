@JS()
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:timezone/timezone.dart' as tz;

import 'notification_backend.dart';
import 'schedule.dart';

@JS('forettPush.isSupported')
external bool _isPushSupported();

@JS('forettPush.isInstallRequired')
external bool _isInstallRequired();

@JS('forettPush.permission')
external String _notificationPermission();

@JS('forettPush.requestPermission')
external JSPromise<JSString> _requestNotificationPermission();

@JS('forettPush.subscribe')
external JSPromise<JSString> _subscribe(String applicationServerKey);

@JS('forettPush.unsubscribe')
external JSPromise<JSBoolean> _unsubscribe();

NotificationBackend createBackend() => WebNotificationBackend();

class WebNotificationBackend implements NotificationBackend {
  WebNotificationBackend({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;
  String? _vapidPublicKey;
  bool _subscribed = false;

  Uri _uri(String path) => Uri.base.resolve(path);

  @override
  Future<NotificationBackendState> initialize() async {
    if (!_isPushSupported()) {
      return const NotificationBackendState(
        readiness: NotificationReadiness.unsupported,
      );
    }
    if (_isInstallRequired()) {
      return const NotificationBackendState(
        readiness: NotificationReadiness.installRequired,
      );
    }
    await _loadConfiguration();
    final permission = _notificationPermission();
    if (permission == 'denied') {
      return const NotificationBackendState(
        readiness: NotificationReadiness.permissionDenied,
      );
    }
    if (permission == 'granted') {
      await _ensureSession();
      await _syncSubscription();
      return NotificationBackendState(
        readiness: NotificationReadiness.ready,
        subscribed: _subscribed,
      );
    }
    return const NotificationBackendState();
  }

  @override
  Future<NotificationBackendState> requestPermission() async {
    if (!_isPushSupported()) {
      return const NotificationBackendState(
        readiness: NotificationReadiness.unsupported,
      );
    }
    if (_isInstallRequired()) {
      return const NotificationBackendState(
        readiness: NotificationReadiness.installRequired,
      );
    }

    // Start the browser prompt synchronously from the UI gesture. Safari can
    // reject prompts that follow an awaited network operation.
    final permissionRequest = _requestNotificationPermission().toDart;
    final permission = (await permissionRequest).toDart;
    if (permission != 'granted') {
      return const NotificationBackendState(
        readiness: NotificationReadiness.permissionDenied,
      );
    }
    await _loadConfiguration();
    await _ensureSession();
    await _syncSubscription();
    return NotificationBackendState(
      readiness: NotificationReadiness.ready,
      subscribed: _subscribed,
    );
  }

  Future<void> _loadConfiguration() async {
    if (_vapidPublicKey != null) return;
    final response = await _client.get(_uri('/api/push/config'));
    final body = _decodeObject(response);
    final key = body['vapidPublicKey'];
    if (response.statusCode != 200 || key is! String || key.isEmpty) {
      throw StateError('Web Push is unavailable');
    }
    _vapidPublicKey = key;
  }

  Future<void> _ensureSession() async {
    final response = await _client.post(_uri('/api/session'));
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError('Could not create the notification session');
    }
  }

  Future<void> _syncSubscription() async {
    final serialized = (await _subscribe(_vapidPublicKey!).toDart).toDart;
    final decoded = jsonDecode(serialized);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid browser push subscription');
    }
    final response = await _client.put(
      _uri('/api/push/subscription'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(decoded),
    );
    if (response.statusCode != 200) {
      throw StateError('Could not save the push subscription');
    }
    _subscribed = true;
  }

  @override
  Future<BusReminder> schedule(BusReminder reminder) async {
    if (_notificationPermission() != 'granted') {
      throw StateError('Notification permission is required');
    }
    await _loadConfiguration();
    await _ensureSession();
    if (!_subscribed) await _syncSubscription();
    final id = reminder.id ?? _randomId();
    late final http.Response response;
    try {
      response = await _client
          .put(
            _uri('/api/reminder'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'id': id,
              'departureAt': reminder.busTime.toUtc().toIso8601String(),
              'direction': reminder.direction.name,
              'scheduleRevision': _scheduleRevision(),
            }),
          )
          .timeout(const Duration(seconds: 12));
    } on Object {
      final current = await pendingReminder();
      if (current?.id == id) return current!;
      rethrow;
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError('Could not save the reminder');
    }
    return BusReminder(
      id: id,
      busTime: reminder.busTime,
      direction: reminder.direction,
    );
  }

  @override
  Future<BusReminder?> pendingReminder() async {
    final response = await _client.get(_uri('/api/reminder'));
    if (response.statusCode == 401 || response.statusCode == 404) return null;
    final body = _decodeObject(response);
    if (response.statusCode != 200 || body['reminder'] == null) return null;
    final raw = body['reminder'];
    if (raw is! Map<String, dynamic>) return null;
    final id = raw['id'];
    final departure = raw['departureAt'];
    final direction = raw['direction'];
    if (id is! String || departure is! String || direction is! String) {
      return null;
    }
    final parsed = DateTime.tryParse(departure);
    if (parsed == null) return null;
    return BusReminder(
      id: id,
      busTime: tz.TZDateTime.from(parsed, BusSchedule.singaporeLocation),
      direction: Direction.values.byName(direction),
    );
  }

  @override
  Future<void> cancelReminder({String? reminderId}) async {
    final suffix = reminderId == null
        ? ''
        : '?id=${Uri.encodeQueryComponent(reminderId)}';
    late final http.Response response;
    try {
      response = await _client
          .delete(_uri('/api/reminder$suffix'))
          .timeout(const Duration(seconds: 12));
    } on Object {
      final current = await pendingReminder();
      if (current == null || (reminderId != null && current.id != reminderId)) {
        return;
      }
      rethrow;
    }
    if (response.statusCode != 200 &&
        response.statusCode != 204 &&
        response.statusCode != 404) {
      throw StateError('Could not cancel the reminder');
    }
  }

  @override
  Future<void> disable() async {
    final response = await _client.delete(_uri('/api/push/subscription'));
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw StateError('Could not disable notifications');
    }
    await _unsubscribe().toDart;
    _subscribed = false;
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    try {
      final value = jsonDecode(response.body);
      return value is Map<String, dynamic> ? value : const {};
    } on Object {
      return const {};
    }
  }

  String _randomId() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String _scheduleRevision() {
    final canonical = jsonEncode(BusSchedule.active.value.toJson());
    // Stable non-security hash: the server uses this only for state
    // reconciliation, never for authentication.
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(canonical)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
