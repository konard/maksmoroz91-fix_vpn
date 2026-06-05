import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_app/vpn/tunnel_settings.dart';

void main() {
  const olcrtcKey =
      '0000000000000000000000000000000000000000000000000000000000000000';
  const vlessUri =
      'vless://00000000-0000-0000-0000-000000000000@example.com:443'
      '?security=reality&sni=example.com&pbk=public-key&sid=abcd'
      '&flow=xtls-rprx-vision#server';

  test('normalizes Telemost room URL', () {
    final room = OlcrtcRoom.parse(
      'https://telemost.yandex.ru/j/79079217431?from=test',
    );

    expect(room.id, '79079217431');
    expect(room.url, 'https://telemost.yandex.ru/j/79079217431');
  });

  test('accepts Jitsi room URL for olcRTC', () {
    final room = OlcrtcRoom.parse('https://meet.example.com/myroom');

    expect(room.id, 'https://meet.example.com/myroom');
    expect(room.url, 'https://meet.example.com/myroom');
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
      olcrtcRoom: '79079217431',
      vlessUri: vlessUri,
      olcrtcKey: olcrtcKey,
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

  test('builds olcRTC platform arguments', () {
    final settings = TunnelSettings.parse(
      olcrtcRoom: 'https://telemost.yandex.ru/j/79079217431',
      vlessUri: vlessUri,
      olcrtcKey: olcrtcKey,
    );

    expect(
      settings.toOlcrtcArgs(clientId: 'device-test'),
      containsPair('carrier', 'telemost'),
    );
    expect(
      settings.toOlcrtcArgs(clientId: 'device-test'),
      containsPair('transport', 'datachannel'),
    );
    expect(
      settings.toOlcrtcArgs(clientId: 'device-test'),
      containsPair('roomId', 'https://telemost.yandex.ru/j/79079217431'),
    );
    expect(
      settings.toOlcrtcArgs(clientId: 'device-test'),
      containsPair('key', olcrtcKey),
    );
    expect(
      settings.toOlcrtcArgs(clientId: 'device-test'),
      containsPair('socksPort', 1080),
    );
  });

  test('rejects invalid olcRTC key', () {
    expect(
      () => TunnelSettings.parse(
        olcrtcRoom: '79079217431',
        vlessUri: vlessUri,
        olcrtcKey: 'abc',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
