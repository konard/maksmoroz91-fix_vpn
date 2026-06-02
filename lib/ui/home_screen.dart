import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../vpn/tunnel_interface.dart';
import '../vpn/packet_handler.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late TunnelInterface _tunnel;
  late PacketHandler _packetHandler;
  bool _isVpnRunning = false;

  @override
  void initState() {
    super.initState();
    _tunnel = TunnelInterface();
    _packetHandler = PacketHandler(_tunnel);
  }

  Future<void> _toggleVpn() async {
    if (_isVpnRunning) {
      await _tunnel.stop();
      setState(() => _isVpnRunning = false);
    } else {
      bool granted = await _requestVpnPermission();
      if (!mounted) return;
      if (!granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('VPN permission denied')),
        );
        return;
      }
      bool success = await _tunnel.start();
      if (!mounted) return;
      if (success) {
        _packetHandler.start();
        setState(() => _isVpnRunning = true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start VPN')),
        );
      }
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebRTC VPN Client')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Status: ${_isVpnRunning ? "CONNECTED" : "DISCONNECTED"}'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _toggleVpn,
              child: Text(_isVpnRunning ? 'Disconnect' : 'Connect'),
            ),
          ],
        ),
      ),
    );
  }
}
