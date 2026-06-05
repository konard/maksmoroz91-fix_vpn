import 'package:flutter/foundation.dart';

import 'tunnel_settings.dart';

abstract interface class PacketTransport {
  Future<void> connect(TunnelSettings settings);
  Future<void> sendPacket(Uint8List packet);
  Future<void> close();
}

class DebugPacketTransport implements PacketTransport {
  bool _connected = false;

  @override
  Future<void> connect(TunnelSettings settings) async {
    _connected = true;
    debugPrint(
      'Bridge configured: ${settings.olcrtcCarrier}/${settings.olcrtcRoom.url} -> '
      '${settings.vlessEndpoint.host}:${settings.vlessEndpoint.port}',
    );
  }

  @override
  Future<void> sendPacket(Uint8List packet) async {
    if (!_connected) return;

    debugPrint('Packet from TUN: ${packet.length} bytes');
    if (packet.length >= 20) {
      debugPrint('   First 20 bytes: ${packet.sublist(0, 20)}');
    }
  }

  @override
  Future<void> close() async {
    _connected = false;
  }
}
