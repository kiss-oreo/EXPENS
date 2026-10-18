import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpenc/core/permissions/app_permissions.dart';
import 'package:xpenc/data/database.dart';
import 'package:xpenc/data/ledger_extensions.dart';
import 'package:xpenc/features/message_capture/capture_health.dart';

void main() {
  test('fresh install is not a warning; pause and revoke are', () {
    final fresh = captureHealthOf(
      captureEnabled: false,
      everEnabled: false,
      sms: PermissionState.unavailable,
    );
    expect(fresh.kind, CaptureHealthKind.notSetUp);
    expect(fresh.title, 'Not set up');
    expect(fresh.showWarning, isFalse);
    expect(fresh.widgetLabel, isEmpty);

    final paused = captureHealthOf(
      captureEnabled: false,
      everEnabled: true,
      sms: PermissionState.granted,
    );
    expect(paused.kind, CaptureHealthKind.pausedByYou);
    expect(paused.title, 'Paused by you');
    expect(paused.showWarning, isTrue);
    expect(paused.widgetLabel, 'Paused by you');

    final revoked = captureHealthOf(
      captureEnabled: true,
      everEnabled: true,
      sms: PermissionState.denied,
    );
    expect(revoked.kind, CaptureHealthKind.permissionRevoked);
    expect(revoked.title, 'Permission revoked');
    expect(revoked.showWarning, isTrue);
    expect(revoked.widgetLabel, 'Permission revoked');

    final blocked = captureHealthOf(
      captureEnabled: true,
      everEnabled: true,
      sms: PermissionState.blocked,
    );
    expect(blocked.kind, CaptureHealthKind.permissionRevoked);

    final active = captureHealthOf(
      captureEnabled: true,
      everEnabled: true,
      sms: PermissionState.granted,
    );
    expect(active.kind, CaptureHealthKind.active);
    expect(active.showWarning, isFalse);
    expect(active.widgetLabel, isEmpty);

    final unavailable = captureHealthOf(
      captureEnabled: true,
      everEnabled: true,
      sms: PermissionState.unavailable,
    );
    expect(unavailable.kind, CaptureHealthKind.active);
    expect(unavailable.showWarning, isFalse);
  });

  test('enabling capture is remembered after it is paused', () async {
    final temp = Directory.systemTemp.createTempSync('expens_cap_');
    final db = AppDatabase(NativeDatabase(File('${temp.path}/ledger.sqlite')));
    addTearDown(() async {
      await db.close();
      temp.deleteSync(recursive: true);
    });

    expect(await captureEverEnabled(db), isFalse);
    expect(await metaValue(db, 'capture_ever_enabled'), isNull);

    await db.setMessageCaptureEnabled(false);
    expect(await metaValue(db, 'capture_ever_enabled'), isNull);

    await db.setMessageCaptureEnabled(true);
    await db.setMessageCaptureEnabled(false);
    expect(await metaValue(db, 'capture_ever_enabled'), '1');
    expect(await captureEverEnabled(db), isTrue);
  });

  test('the six-hour widget check does not read a message', () {
    expect(captureHealthCheckInterval, const Duration(hours: 6));
    final kotlin = File(
      'android/app/src/main/kotlin/com/kissoreo/expens/CaptureHealthCheck.kt',
    ).readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(kotlin, contains('6L * 60L * 60L * 1000L'));
    expect(kotlin, contains('Permission revoked'));
    expect(kotlin, contains('Paused by you'));
    expect(kotlin, contains('RECEIVE_SMS'));
    expect(kotlin.contains('READ_SMS'), isFalse);
    expect(kotlin.contains('content://sms'), isFalse);
    expect(kotlin.contains('SMS_RECEIVED'), isFalse);
    expect(manifest, contains('android:name=".CaptureHealthCheck"'));
    expect(manifest, contains('android:name=".CaptureHealthBoot"'));
    expect(manifest, contains('android.intent.action.BOOT_COMPLETED'));
  });
}
