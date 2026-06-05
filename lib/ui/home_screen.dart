import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../vpn/packet_handler.dart';
import '../vpn/tunnel_interface.dart';
import '../vpn/tunnel_settings.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late TunnelInterface _tunnel;
  late PacketHandler _packetHandler;
  final TextEditingController _olcrtcRoomController = TextEditingController(
    text: 'https://telemost.yandex.ru/j/79079217431',
  );
  final TextEditingController _olcrtcCarrierController = TextEditingController(
    text: 'telemost',
  );
  final TextEditingController _olcrtcTransportController =
      TextEditingController(text: 'datachannel');
  final TextEditingController _olcrtcKeyController = TextEditingController();
  final TextEditingController _vlessUriController = TextEditingController();
  bool _isVpnRunning = false;
  String? _settingsError;

  @override
  void initState() {
    super.initState();
    _tunnel = TunnelInterface();
    _packetHandler = PacketHandler(_tunnel);
  }

  Future<void> _toggleVpn() async {
    if (_isVpnRunning) {
      await _packetHandler.stop();
      await _tunnel.stop();
      setState(() => _isVpnRunning = false);
    } else {
      final settings = _readSettings();
      if (settings == null) return;

      bool granted = await _requestVpnPermission();
      if (!mounted) return;
      if (!granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('VPN permission denied')),
        );
        return;
      }
      bool success = await _tunnel.start(settings);
      if (!mounted) return;
      if (success) {
        await _packetHandler.start(settings);
        if (!mounted) return;
        setState(() => _isVpnRunning = true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start VPN')),
        );
      }
    }
  }

  TunnelSettings? _readSettings() {
    try {
      final settings = TunnelSettings.parse(
        olcrtcRoom: _olcrtcRoomController.text,
        vlessUri: _vlessUriController.text,
        olcrtcKey: _olcrtcKeyController.text,
        olcrtcCarrier: _olcrtcCarrierController.text,
        olcrtcTransport: _olcrtcTransportController.text,
      );
      setState(() => _settingsError = null);
      return settings;
    } on FormatException catch (e) {
      setState(() => _settingsError = e.message);
      return null;
    }
  }

  Future<bool> _requestVpnPermission() async {
    // `MethodChannel` has a const constructor, but `final` is used here to keep
    // the code robust against editor/lint confusion and future refactors.
    final platform = MethodChannel('vpn_prepare');
    try {
      final bool granted = await platform.invokeMethod('prepare');
      return granted;
    } catch (e) {
      debugPrint('Prepare error: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _olcrtcRoomController.dispose();
    _olcrtcCarrierController.dispose();
    _olcrtcTransportController.dispose();
    _olcrtcKeyController.dispose();
    _vlessUriController.dispose();
    unawaited(_packetHandler.stop());
    _tunnel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebRTC VPN Client')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Status: ${_isVpnRunning ? "CONNECTED" : "DISCONNECTED"}'),
                const SizedBox(height: 20),
                TextField(
                  controller: _olcrtcRoomController,
                  enabled: !_isVpnRunning,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'olcRTC room URL / ID',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _olcrtcCarrierController,
                        enabled: !_isVpnRunning,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Carrier',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _olcrtcTransportController,
                        enabled: !_isVpnRunning,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Transport',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _olcrtcKeyController,
                  enabled: !_isVpnRunning,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'olcRTC key (64 hex)',
                  ),
                  keyboardType: TextInputType.visiblePassword,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _vlessUriController,
                  enabled: !_isVpnRunning,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'VLESS Reality URI',
                  ),
                  keyboardType: TextInputType.url,
                ),
                if (_settingsError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _settingsError!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _toggleVpn,
                  child: Text(_isVpnRunning ? 'Disconnect' : 'Connect'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
