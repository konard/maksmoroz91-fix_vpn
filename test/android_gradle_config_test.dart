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

  test('tun2socks native executable is extracted to nativeLibraryDir', () {
    final buildFile = File('android/app/build.gradle.kts');
    final buildConfig = buildFile.readAsStringSync();
    final extractsJniLibs = RegExp(
      r'packaging\s*\{[\s\S]*jniLibs\s*\{[\s\S]*useLegacyPackaging\s*=\s*true',
    ).hasMatch(buildConfig);

    expect(
      extractsJniLibs,
      isTrue,
      reason:
          'Tun2SocksRunner starts libtun2socks.so through ProcessBuilder, so '
          'AGP must extract JNI libraries to applicationInfo.nativeLibraryDir.',
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

  test('tun2socks inherits TUN through stdin instead of a non-standard fd', () {
    final runnerFile = File(
      'android/app/src/main/kotlin/com/example/vpn_app/Tun2SocksRunner.kt',
    );
    final runner = runnerFile.readAsStringSync();

    expect(
      runner,
      contains('"--device", "fd://\${OsConstants.STDIN_FILENO}"'),
      reason:
          'Android ProcessBuilder closes non-standard descriptors in the child; '
          'tun2socks must receive the TUN fd through inherited stdin.',
    );
    expect(
      runner,
      contains('Os.dup2(tunForChild, OsConstants.STDIN_FILENO)'),
    );
    expect(
      runner,
      contains('redirectInput(ProcessBuilder.Redirect.INHERIT)'),
    );
    expect(
      runner,
      contains('Build.VERSION.SDK_INT < Build.VERSION_CODES.O'),
      reason: 'ProcessBuilder.Redirect is available on Android API 26+.',
    );
    expect(
      runner,
      isNot(contains('"--device", "fd://\$dupFdInt"')),
      reason:
          'Passing a duplicated descriptor number above stderr reproduces the '
          'bad file descriptor crash from issue 11.',
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
