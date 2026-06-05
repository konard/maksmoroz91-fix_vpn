import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android Gradle Plugin version satisfies Flutter minimum', () {
    final settingsFile = File('android/settings.gradle.kts');
    final settings = settingsFile.readAsStringSync();
    final match = RegExp(
      r'id\("com\.android\.application"\)\s+version\s+"([^"]+)"',
    ).firstMatch(settings);

    expect(match, isNotNull);

    final declaredVersion = _Version.parse(match!.group(1)!);
    expect(
      declaredVersion.compareTo(const _Version(8, 6, 0)),
      greaterThanOrEqualTo(0),
      reason:
          'Flutter stable rejects Android Gradle Plugin versions below 8.6.0.',
    );
  });

  test('Android native AAR libraries are extracted to nativeLibraryDir', () {
    final buildFile = File('android/app/build.gradle.kts');
    final buildConfig = buildFile.readAsStringSync();
    final extractsJniLibs = RegExp(
      r'packaging\s*\{[\s\S]*jniLibs\s*\{[\s\S]*useLegacyPackaging\s*=\s*true',
    ).hasMatch(buildConfig);

    expect(
      extractsJniLibs,
      isTrue,
      reason:
          'Optional gomobile AARs such as libbox.aar include JNI libraries; '
          'device builds should extract them consistently for native loading.',
    );
  });

  test('Android VPN service uses app service class without shadowing framework', () {
    final manifestFile = File('android/app/src/main/AndroidManifest.xml');
    final manifest = manifestFile.readAsStringSync();
    final pluginFile = File(
      'android/app/src/main/kotlin/com/example/vpn_app/VpnPlugin.kt',
    );
    final plugin = pluginFile.readAsStringSync();
    final serviceFile = File(
      'android/app/src/main/kotlin/com/example/vpn_app/AppVpnService.kt',
    );
    final instanceFile = File(
      'android/app/src/main/kotlin/com/example/vpn_app/VpnServiceInstance.kt',
    );
    final shadowingServiceFile = File(
      'android/app/src/main/kotlin/com/example/vpn_app/VpnService.kt',
    );

    expect(serviceFile.existsSync(), isTrue);
    expect(instanceFile.existsSync(), isTrue);
    expect(shadowingServiceFile.existsSync(), isFalse);

    final service = serviceFile.readAsStringSync();
    expect(manifest, contains('android:name=".AppVpnService"'));
    expect(service, contains('class AppVpnService : VpnService()'));
    expect(service, contains('VpnServiceInstance.set(this)'));
    expect(service, contains('.setBlocking(true)'));
    expect(plugin, contains('Intent(context, AppVpnService::class.java)'));
    expect(plugin, contains('VpnServiceInstance.get()?.writePacket(packet)'));
  });

  test('Android registers native olcRTC Flutter channels', () {
    final mainActivityFile = File(
      'android/app/src/main/kotlin/com/example/vpn_app/MainActivity.kt',
    );
    final mainActivity = mainActivityFile.readAsStringSync();
    final pluginFile = File(
      'android/app/src/main/kotlin/com/example/vpn_app/OlcrtcPlugin.kt',
    );
    final buildFile = File('android/app/build.gradle.kts');
    final buildConfig = buildFile.readAsStringSync();

    expect(pluginFile.existsSync(), isTrue);

    final plugin = pluginFile.readAsStringSync();
    expect(mainActivity, contains('flutterEngine.plugins.add(OlcrtcPlugin())'));
    expect(
      plugin,
      contains('MethodChannel(binding.binaryMessenger, "olcrtc_channel")'),
    );
    expect(
      plugin,
      contains('EventChannel(binding.binaryMessenger, "olcrtc_logs")'),
    );
    expect(plugin, contains('"getDeviceId"'));
    expect(plugin, contains('"start"'));
    expect(plugin, contains('"stop"'));
    expect(plugin, contains('"isRunning"'));
    expect(plugin, contains('Settings.Secure.ANDROID_ID'));
    expect(plugin, contains('findClass("mobile.Mobile", "go.mobile.Mobile")'));
    expect(plugin, contains('olcrtc_missing'));
    expect(buildConfig, contains('implementation(fileTree('));
    expect(buildConfig, contains('"libs"'));
    expect(buildConfig, contains('"*.aar"'));
  });

  test('Android olcRTC bridge defaults Jitsi starts to datachannel', () {
    final pluginFile = File(
      'android/app/src/main/kotlin/com/example/vpn_app/OlcrtcPlugin.kt',
    );
    final plugin = pluginFile.readAsStringSync();

    expect(plugin, contains('private const val JITSI_CARRIER = "jitsi"'));
    expect(
      plugin,
      contains('private const val JITSI_DEFAULT_TRANSPORT = "datachannel"'),
    );
    expect(
      plugin,
      contains('explicitTransport ?: defaultTransportFor(carrier)'),
      reason:
          'The issue 17 logs show carrier=jitsi falling back to mobile\'s '
          'vp8channel default; upstream olcRTC documents jitsi+datachannel as '
          'the stable default path.',
    );
  });

  test('Dart tunnel starts olcRTC before Android VPN', () {
    final clientFile = File('lib/vpn/olcrtc_client.dart');
    final tunnelFile = File('lib/vpn/tunnel_interface.dart');
    final settingsFile = File('lib/vpn/tunnel_settings.dart');

    expect(clientFile.existsSync(), isTrue);

    final client = clientFile.readAsStringSync();
    final tunnel = tunnelFile.readAsStringSync();
    final settings = settingsFile.readAsStringSync();

    expect(client, contains("MethodChannel('olcrtc_channel')"));
    expect(client, contains("EventChannel('olcrtc_logs')"));
    expect(settings, contains('toOlcrtcArgs'));
    expect(settings, contains('class OlcrtcRoom'));
    expect(settings, contains('olcrtcKey'));
    expect(settings, contains("'waitReadyTimeoutMillis'"));
    expect(tunnel, contains('await _olcrtc.start(settings)'));
    expect(tunnel, contains("invokeMethod('start', settings.toPlatformArgs())"));
    expect(
      tunnel.indexOf('await _olcrtc.start(settings)'),
      lessThan(tunnel.indexOf("invokeMethod('start', settings.toPlatformArgs())")),
      reason:
          'The Android VPN/sing-box service must not start until olcRTC has '
          'created the SOCKS endpoint. Issue 21 logs showed VPN startup after '
          'olcRTC waitReady failed with a closed control stream.',
    );
  });

  test('Android VPN starts sing-box through libbox command server API', () {
    final serviceFile = File(
      'android/app/src/main/kotlin/com/example/vpn_app/AppVpnService.kt',
    );
    final runnerFile = File(
      'android/app/src/main/kotlin/com/example/vpn_app/SingBoxRunner.kt',
    );
    final staleRunnerFile = File(
      'android/app/src/main/kotlin/com/example/vpn_app/Tun2SocksRunner.kt',
    );

    expect(runnerFile.existsSync(), isTrue);
    expect(staleRunnerFile.existsSync(), isFalse);

    final service = serviceFile.readAsStringSync();
    final runner = runnerFile.readAsStringSync();

    expect(service, contains('private var singBoxRunner: SingBoxRunner?'));
    expect(service, contains('SingBoxRunner.Config('));
    expect(service, contains('singBoxRunner!!.start(vpnInterface!!'));
    expect(service, isNot(contains('Tun2SocksRunner')));

    expect(runner, contains('Class.forName('));
    expect(runner, contains('"io.nekohasekai.libbox.Libbox"'));
    expect(runner, contains('"io.nekohasekai.libbox.SetupOptions"'));
    expect(runner, contains('"io.nekohasekai.libbox.CommandServerHandler"'));
    expect(runner, contains('"io.nekohasekai.libbox.PlatformInterface"'));
    expect(runner, contains('"newCommandServer"'));
    expect(runner, contains('"startOrReloadService"'));
    expect(runner, contains('"closeService"'));
    expect(runner, contains('"openTun"'));
    expect(runner, contains('"type", "vless"'));
    expect(runner, contains('"reality"'));
    expect(runner, isNot(contains('import go.libbox')));
    expect(runner, isNot(contains('import io.nekohasekai.libbox')));
    expect(runner, isNot(contains('BoxService')));
  });

  test('sing-box VLESS outbound keeps UDP enabled', () {
    final runnerFile = File(
      'android/app/src/main/kotlin/com/example/vpn_app/SingBoxRunner.kt',
    );
    final runner = runnerFile.readAsStringSync();

    expect(
      runner,
      isNot(contains('.put("network", "tcp")')),
      reason:
          'Issue 23 logs show TCP traffic continuing while UDP attempts fail. '
          'sing-box enables both TCP and UDP for VLESS by default, so the app '
          'must not force the generated outbound to TCP-only.',
    );
  });

  test('sing-box replaces the tun2socks ProcessBuilder integration', () {
    final runnerFile = File(
      'android/app/src/main/kotlin/com/example/vpn_app/Tun2SocksRunner.kt',
    );

    expect(
      runnerFile.existsSync(),
      isFalse,
      reason:
          'Issue 19 replaces the tun2socks binary bridge with sing-box libbox.',
    );
  });
}

class _Version {
  const _Version(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  factory _Version.parse(String value) {
    final parts = value.split('.');
    if (parts.length != 3) {
      throw FormatException('Expected semantic version', value);
    }

    return _Version(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  int compareTo(_Version other) {
    final majorCompare = major.compareTo(other.major);
    if (majorCompare != 0) {
      return majorCompare;
    }

    final minorCompare = minor.compareTo(other.minor);
    if (minorCompare != 0) {
      return minorCompare;
    }

    return patch.compareTo(other.patch);
  }
}
