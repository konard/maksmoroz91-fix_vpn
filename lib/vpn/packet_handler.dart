import 'dart:async';
import 'dart:typed_data';

import 'packet_transport.dart';
import 'tunnel_interface.dart';
import 'tunnel_settings.dart';

class PacketHandler {
  PacketHandler(
    this.tunnel, {
    PacketTransport? transport,
    Stream<Uint8List>? packets,
  })  : _transport = transport ?? DebugPacketTransport(),
        _packets = packets ?? tunnel.onPacket;

  final TunnelInterface tunnel;
  final PacketTransport _transport;
  final Stream<Uint8List> _packets;
  StreamSubscription<Uint8List>? _subscription;

  Future<void> start(TunnelSettings settings) async {
    if (_subscription != null) return;

    await _transport.connect(settings);
    _subscription = _packets.listen((packet) {
      unawaited(_transport.sendPacket(packet));
    });
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _transport.close();
  }

  Future<void> sendToTun(Uint8List packet) async {
    await tunnel.writePacket(packet);
  }
}
