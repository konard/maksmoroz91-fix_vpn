import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_app/vpn/packet_handler.dart';
import 'package:vpn_app/vpn/packet_transport.dart';
import 'package:vpn_app/vpn/tunnel_interface.dart';
import 'package:vpn_app/vpn/tunnel_settings.dart';

void main() {
  const olcrtcKey =
      '0000000000000000000000000000000000000000000000000000000000000000';
  const vlessUri =
      'vless://00000000-0000-0000-0000-000000000000@example.com:443'
      '?security=reality&sni=example.com&pbk=public-key';

  TunnelSettings settings() {
    return TunnelSettings.parse(
      olcrtcRoom: 'https://telemost.yandex.ru/j/79079217431',
      vlessUri: vlessUri,
      olcrtcKey: olcrtcKey,
    );
  }

  test('forwards packets to configured transport once', () async {
    final packets = StreamController<Uint8List>();
    final transport = _RecordingPacketTransport();
    final handler = PacketHandler(
      TunnelInterface(),
      transport: transport,
      packets: packets.stream,
    );

    await handler.start(settings());
    await handler.start(settings());
    packets.add(Uint8List.fromList(<int>[1, 2, 3]));
    await pumpEventQueue();

    expect(transport.connectCount, 1);
    expect(transport.packets, hasLength(1));
    expect(transport.packets.single, <int>[1, 2, 3]);

    await handler.stop();
    await packets.close();
  });
}

class _RecordingPacketTransport implements PacketTransport {
  int connectCount = 0;
  final List<Uint8List> packets = <Uint8List>[];

  @override
  Future<void> connect(TunnelSettings settings) async {
    connectCount += 1;
  }

  @override
  Future<void> sendPacket(Uint8List packet) async {
    packets.add(packet);
  }

  @override
  Future<void> close() async {}
}
