import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// SMS capture is a manifest BroadcastReceiver for the message that just
/// arrived. READ_SMS and inbox queries stay forbidden — Play Protect and the
/// privacy spec both reject them. RECEIVE_SMS is the one permission this
/// feature is allowed to request, and only after the explanation screen.
void main() {
  test('the manifest requests RECEIVE_SMS and never READ_SMS', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest.contains('android.permission.READ_SMS'), isFalse);
    expect(manifest.contains('android.permission.RECEIVE_SMS'), isTrue);
    expect(manifest.contains('android.provider.Telephony.SMS_RECEIVED'), isTrue);
    expect(manifest.contains('content://sms'), isFalse);
  });

  test('MainActivity carries no SMS inbox code', () {
    final kotlin = File(
      'android/app/src/main/kotlin/com/kissoreo/expens/MainActivity.kt',
    ).readAsStringSync();

    expect(kotlin.contains('Telephony'), isFalse);
    expect(kotlin.contains('Manifest.permission'), isFalse);
    expect(kotlin.contains('READ_SMS'), isFalse);
  });

  test('the receiver never queries the inbox', () {
    final kotlin = Directory('android/app/src/main/kotlin')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.kt'))
        .map((f) => f.readAsStringSync())
        .join('\n');
    expect(kotlin.contains('READ_SMS'), isFalse);
    expect(kotlin.contains('content://sms'), isFalse);
    expect(kotlin.contains('SMS_RECEIVED'), isTrue);
  });

  test('Kotlin package matches its directory and the Gradle namespace', () {
    final kotlin = File(
      'android/app/src/main/kotlin/com/kissoreo/expens/MainActivity.kt',
    ).readAsStringSync();
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(kotlin, contains('package com.kissoreo.expens'));
    expect(gradle, contains('namespace = "com.kissoreo.expens"'));
    expect(gradle, contains('applicationId = "com.kissoreo.expens"'));
  });
}
