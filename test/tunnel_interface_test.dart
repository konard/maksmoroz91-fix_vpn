import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_app/vpn/olcrtc_client.dart';
import 'package:vpn_app/vpn/tunnel_interface.dart';
import 'package:vpn_app/vpn/tunnel_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('vpn_channel'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('vpn_events'), null);
  });

  test('starts olcRTC before Android VPN service', () async {
    final calls = <String>[];
    final olcrtc = _FakeOlcrtcClient(calls);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('vpn_channel'),
            (MethodCall call) async {
      calls.add('vpn.${call.method}');
      return true;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('vpn_events'),
            (MethodCall call) async => null);

    final tunnel = TunnelInterface(olcrtc: olcrtc);

    expect(await tunnel.start(settings()), isTrue);
    expect(calls, <String>['olcrtc.start', 'vpn.start']);

    await tunnel.stop();
  });

  test('does not start Android VPN when olcRTC start fails', () async {
    final calls = <String>[];
    final olcrtc = _FakeOlcrtcClient(
      calls,
      startError: PlatformException(
        code: 'olcrtc_error',
        message: 'handshake: open control stream: io: read/write on closed pipe',
      ),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('vpn_channel'),
            (MethodCall call) async {
      calls.add('vpn.${call.method}');
      return true;
    });

    final tunnel = TunnelInterface(olcrtc: olcrtc);

    expect(await tunnel.start(settings()), isFalse);
    expect(calls, <String>['olcrtc.start', 'olcrtc.stop']);
  });
}

class _FakeOlcrtcClient implements OlcrtcClient {
  _FakeOlcrtcClient(this.calls, {this.startError});

  final List<String> calls;
  final Object? startError;
  final StreamController<String> _logs = StreamController<String>.broadcast();

  @override
  Stream<String> get logs => _logs.stream;

  @override
  Future<String> getDeviceId() async => 'device-test';

  @override
  Future<bool> isRunning() async => startError == null;

  @override
  Future<void> start(TunnelSettings settings) async {
    calls.add('olcrtc.start');
    final error = startError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> stop() async {
    calls.add('olcrtc.stop');
  }

  @override
  void dispose() {
    unawaited(_logs.close());
  }
}
