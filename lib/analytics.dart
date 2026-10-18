import 'analytics_backend_stub.dart'
    if (dart.library.js_interop) 'analytics_backend_web.dart'
    as backend;

/// Small web-only analytics boundary. Native builds never contact GA4.
abstract final class AnalyticsService {
  static bool get enabled => backend.analyticsEnabled();

  static void start() => backend.startAnalytics();

  static void setEnabled(bool enabled) => backend.setAnalyticsEnabled(enabled);

  static void track(String name, [Map<String, String> parameters = const {}]) =>
      backend.trackAnalytics(name, parameters);
}
