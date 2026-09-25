import 'package:flutter/foundation.dart';

class TransportConfig {
  TransportConfig._({
    required this.baseUrl,
    required this.appApiKey,
    required this.sameOrigin,
  });

  factory TransportConfig.defaults() {
    if (kIsWeb) {
      return TransportConfig._(
        baseUrl: Uri.base
            .resolve('/api')
            .toString()
            .replaceFirst(RegExp(r'/+$'), ''),
        appApiKey: '',
        sameOrigin: true,
      );
    }
    return TransportConfig._(
      baseUrl: const String.fromEnvironment(
        'BUS_API_BASE_URL',
        defaultValue: '',
      ).trim().replaceFirst(RegExp(r'/+$'), ''),
      appApiKey: const String.fromEnvironment(
        'APP_API_KEY',
        defaultValue: '',
      ).trim(),
      sameOrigin: false,
    );
  }

  factory TransportConfig.explicit(String baseUrl, String appApiKey) =>
      TransportConfig._(
        baseUrl: baseUrl.trim().replaceFirst(RegExp(r'/+$'), ''),
        appApiKey: appApiKey.trim(),
        sameOrigin: false,
      );

  @visibleForTesting
  factory TransportConfig.sameOrigin(Uri origin) => TransportConfig._(
    baseUrl: origin.resolve('/api').toString().replaceFirst(RegExp(r'/+$'), ''),
    appApiKey: '',
    sameOrigin: true,
  );

  final String baseUrl;
  final String appApiKey;
  final bool sameOrigin;

  bool get isConfigured {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return false;
    }
    final secure = uri.scheme == 'https';
    final localDevelopment =
        uri.scheme == 'http' &&
        (uri.host == 'localhost' || uri.host == '127.0.0.1');
    return (secure || localDevelopment) && (sameOrigin || appApiKey.isNotEmpty);
  }

  Uri uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl);
    final fullPath =
        '${base.path.replaceFirst(RegExp(r'/+$'), '')}/${path.replaceFirst(RegExp(r'^/+'), '')}';
    return base.replace(path: fullPath, queryParameters: query);
  }

  Map<String, String> headers() => {
    'accept': 'application/json',
    if (!sameOrigin) 'authorization': 'Bearer $appApiKey',
  };
}
