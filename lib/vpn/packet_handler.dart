import 'package:flutter/foundation.dart';
import 'tunnel_interface.dart';

class PacketHandler {
  final TunnelInterface tunnel;

  PacketHandler(this.tunnel);

  void start() {
    tunnel.onPacket.listen((packet) {
      // Packet received from the TUN interface.
      debugPrint('Packet from TUN: ${packet.length} bytes');
      if (packet.length >= 20) {
        debugPrint('   First 20 bytes: ${packet.sublist(0, 20)}');
      }
      // WebRTC forwarding logic would go here.
    });
  }

  Future<void> sendToTun(Uint8List packet) async {
    await tunnel.writePacket(packet);
  }
}
