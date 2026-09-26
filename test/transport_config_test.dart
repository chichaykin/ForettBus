import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shuttle_bus/transport_config.dart';

void main() {
  test('native transport uses Bearer authorization', () {
    final config = TransportConfig.explicit(
      'https://transport.example',
      'client-key',
    );

    expect(config.isConfigured, isTrue);
    expect(config.headers()['authorization'], 'Bearer client-key');
    expect(
      config.uri('/v1/arrivals', {
        'direction': 'forettToBeautyWorld',
      }).toString(),
      'https://transport.example/v1/arrivals?direction=forettToBeautyWorld',
    );
  });

  test('Web transport stays on origin and omits the mobile key', () {
    final config = TransportConfig.sameOrigin(
      Uri.parse('https://app.example/'),
    );

    expect(config.isConfigured, isTrue);
    expect(config.headers(), {'accept': 'application/json'});
    expect(
      config.uri('/v1/stops').toString(),
      'https://app.example/api/v1/stops',
    );
  });

  test(
    'Web session is established once before same-origin API calls',
    () async {
      final host = 'session-${DateTime.now().microsecondsSinceEpoch}.example';
      final config = TransportConfig.sameOrigin(Uri.parse('https://$host/'));
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response('', 201);
      });

      await config.ensureWebSession(client);
      await config.ensureWebSession(client);

      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
      expect(requests.single.url.toString(), 'https://$host/api/session');
    },
  );

  test('plain HTTP is accepted only for local development', () {
    expect(
      TransportConfig.explicit('http://localhost:8787', 'key').isConfigured,
      isTrue,
    );
    expect(
      TransportConfig.explicit('http://example.test', 'key').isConfigured,
      isFalse,
    );
  });
}
