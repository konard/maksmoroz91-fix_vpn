import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'tunnel_settings.dart';

class OlcrtcClient {
  static const MethodChannel _channel = MethodChannel('olcrtc_channel');
  static const EventChannel _logChannel = EventChannel('olcrtc_logs');

  final StreamController<String> _logController =
      StreamController<String>.broadcast();
  StreamSubscription<dynamic>? _logSubscription;

  Stream<String> get logs => _logController.stream;

  Future<String> getDeviceId() async {
    return await _channel.invokeMethod<String>('getDeviceId') ??
        'device-unknown';
  }

  Future<void> start(TunnelSettings settings) async {
    await _attachLogs();
    try {
      final clientId = await getDeviceId();
      await _channel.invokeMethod(
        'start',
        settings.toOlcrtcArgs(clientId: clientId),
      );
    } catch (e) {
      debugPrint('olcRTC start error: $e');
      await _detachLogs();
      rethrow;
    }
  }

  Future<void> stop() async {
    await _detachLogs();
    await _channel.invokeMethod('stop');
  }

  Future<bool> isRunning() async {
    return await _channel.invokeMethod<bool>('isRunning') ?? false;
  }

  void dispose() {
    unawaited(_detachLogs());
    _logController.close();
  }

  Future<void> _attachLogs() async {
    if (_logSubscription != null) return;

    _logSubscription = _logChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is String) {
          _logController.add(event);
        }
      },
      onError: _logController.addError,
    );
  }

  Future<void> _detachLogs() async {
    await _logSubscription?.cancel();
    _logSubscription = null;
  }
}
