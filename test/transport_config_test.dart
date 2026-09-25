import 'package:flutter_test/flutter_test.dart';
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
