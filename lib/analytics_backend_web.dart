@JS()
library;

import 'dart:convert';
import 'dart:js_interop';

@JS('forettAnalytics.enabled')
external JSBoolean _enabled();

@JS('forettAnalytics.start')
external void _start();

@JS('forettAnalytics.setEnabled')
external void _setEnabled(JSBoolean enabled);

@JS('forettAnalytics.track')
external void _track(JSString name, JSString parameters);

bool analyticsEnabled() => _enabled().toDart;

void startAnalytics() => _start();

void setAnalyticsEnabled(bool enabled) => _setEnabled(enabled.toJS);

void trackAnalytics(String name, Map<String, String> parameters) =>
    _track(name.toJS, jsonEncode(parameters).toJS);
