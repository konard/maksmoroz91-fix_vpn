import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'olcrtc_client.dart';
import 'tunnel_settings.dart';

class TunnelInterface {
  static const MethodChannel _methodChannel = MethodChannel('vpn_channel');
  static const EventChannel _eventChannel = EventChannel('vpn_events');

  TunnelInterface({OlcrtcClient? olcrtc}) : _olcrtc = olcrtc ?? OlcrtcClient();

  final OlcrtcClient _olcrtc;
  final StreamController<Uint8List> _packetController =
      StreamController.broadcast();
  Stream<Uint8List> get onPacket => _packetController.stream;
  Stream<String> get logs => _olcrtc.logs;
  StreamSubscription? _eventSubscription;

  Future<bool> start(TunnelSettings settings) async {
    var vpnStartRequested = false;
    try {
      await _olcrtc.start(settings);
      vpnStartRequested = true;
      await _methodChannel.invokeMethod('start', settings.toPlatformArgs());
      _eventSubscription =
          _eventChannel.receiveBroadcastStream().listen((event) {
        if (event is Uint8List) {
          _packetController.add(event);
        } else if (event is List<int>) {
          _packetController.add(Uint8List.fromList(event));
        }
      });
      return true;
    } catch (e) {
      debugPrint('Tunnel start error: $e');
      await _eventSubscription?.cancel();
      _eventSubscription = null;
      if (vpnStartRequested) {
        await _stopVpnAfterFailedStart();
      }
      await _stopOlcrtcAfterFailedStart();
      return false;
    }
  }

  Future<void> stop() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    try {
      await _methodChannel.invokeMethod('stop');
    } finally {
      await _olcrtc.stop();
    }
  }

  Future<void> writePacket(Uint8List packet) async {
    await _methodChannel.invokeMethod('write', {'packet': packet});
  }

  void dispose() {
    _eventSubscription?.cancel();
    _olcrtc.dispose();
    _packetController.close();
  }

  Future<void> _stopVpnAfterFailedStart() async {
    try {
      await _methodChannel.invokeMethod('stop');
    } catch (e) {
      debugPrint('VPN cleanup after failed start error: $e');
    }
  }

  Future<void> _stopOlcrtcAfterFailedStart() async {
    try {
      await _olcrtc.stop();
    } catch (e) {
      debugPrint('olcRTC cleanup after failed start error: $e');
    }
  }
}
