import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_app/vpn/tunnel_settings.dart';

void main() {
  const vlessUri =
      'vless://00000000-0000-0000-0000-000000000000@example.com:443'
      '?security=reality&sni=example.com&pbk=public-key&sid=abcd'
      '&flow=xtls-rprx-vision#server';

  test('normalizes Telemost room URL', () {
    final room = TelemostRoom.parse(
      'https://telemost.yandex.ru/j/79079217431?from=test',
    );

    expect(room.id, '79079217431');
    expect(room.url, 'https://telemost.yandex.ru/j/79079217431');
  });

  test('rejects non-Telemost room URL', () {
    expect(
      () => TelemostRoom.parse('https://example.com/j/79079217431'),
      throwsA(isA<FormatException>()),
    );
  });

  test('parses VLESS Reality endpoint', () {
    final endpoint = VlessRealityEndpoint.parse(vlessUri);

    expect(endpoint.userId, '00000000-0000-0000-0000-000000000000');
    expect(endpoint.host, 'example.com');
    expect(endpoint.port, 443);
    expect(endpoint.publicKey, 'public-key');
    expect(endpoint.serverName, 'example.com');
    expect(endpoint.shortId, 'abcd');
    expect(endpoint.flow, 'xtls-rprx-vision');
  });

  test('rejects VLESS endpoint without Reality security', () {
    expect(
      () => VlessRealityEndpoint.parse(
        'vless://00000000-0000-0000-0000-000000000000@example.com:443'
        '?security=tls&pbk=public-key',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('builds native platform arguments', () {
    final settings = TunnelSettings.parse(
      telemostRoom: '79079217431',
      vlessUri: vlessUri,
    );

    expect(
      settings.toPlatformArgs(),
      containsPair('telemostRoomId', '79079217431'),
    );
    expect(
      settings.toPlatformArgs(),
      containsPair(
        'telemostRoomUrl',
        'https://telemost.yandex.ru/j/79079217431',
      ),
    );
    expect(settings.toPlatformArgs(), containsPair('vlessHost', 'example.com'));
    expect(settings.toPlatformArgs(), containsPair('vlessPort', 443));
    expect(settings.toPlatformArgs(), containsPair('socksPort', 1080));
  });
}
