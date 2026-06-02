// Basic widget test for the WebRTC VPN client.
//
// The original template test checked a counter that this app does not have, so
// it failed on every run. This test verifies the actual initial UI instead.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vpn_app/main.dart';

void main() {
  testWidgets('Home screen renders disconnected state', (WidgetTester tester) async {
    // Build the app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // The VPN starts disconnected, so the status and the Connect button show.
    expect(find.text('Status: DISCONNECTED'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Connect'), findsOneWidget);

    expect(find.text('Telemost room URL'), findsOneWidget);
    expect(find.text('VLESS Reality URI'), findsOneWidget);

    // The title bar is present.
    expect(find.text('WebRTC VPN Client'), findsOneWidget);
  });
}
