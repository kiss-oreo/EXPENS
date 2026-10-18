import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an empty keystore secret does not write key.properties', () {
    final yml = File('.github/workflows/release.yml').readAsStringSync();
    expect(yml, contains('ANDROID_KEYSTORE_BASE64'));
    expect(yml, contains('ANDROID_KEYSTORE_PASSWORD'));
    expect(yml, contains('ANDROID_KEY_PASSWORD'));
    expect(yml, contains('ANDROID_KEY_ALIAS'));
    expect(yml, contains('rm -f android/key.properties'));
    expect(yml, contains('xpenc-release.jks'));
    // The empty-secret branch exits before any property file is written.
    final empty = yml.indexOf('No release keystore configured');
    final write = yml.indexOf("printf 'storePassword=%s\\n'");
    expect(empty, greaterThan(0));
    expect(write, greaterThan(empty));
    final ignore = File('android/.gitignore').readAsStringSync();
    expect(ignore, contains('key.properties'));
    expect(ignore, contains('**/*.jks'));
  });
}
