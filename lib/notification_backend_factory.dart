import 'notification_backend.dart';
import 'notification_backend_native.dart'
    if (dart.library.js_interop) 'notification_backend_web.dart';

NotificationBackend createNotificationBackend() => createBackend();
