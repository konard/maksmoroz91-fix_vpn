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
