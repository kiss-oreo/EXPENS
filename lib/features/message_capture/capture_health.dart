import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/home_widget/home_widget_service.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/permissions/app_permissions.dart';
import '../../data/database.dart';
import '../../data/ledger_extensions.dart';
import '../../data/providers.dart';

/// How often the native widget check runs. It only re-reads the incoming-SMS
/// permission. It does not read a message. See `CaptureHealthCheck.kt`.
const captureHealthCheckInterval = Duration(hours: 6);

enum CaptureHealthKind { notSetUp, active, pausedByYou, permissionRevoked }

class CaptureHealth {
  const CaptureHealth(this.kind);

  final CaptureHealthKind kind;

  /// A warning is only for a capture the user turned on and then stopped,
  /// or for a permission that was taken away. A fresh install is not a warning.
  bool get showWarning =>
      kind == CaptureHealthKind.pausedByYou ||
      kind == CaptureHealthKind.permissionRevoked;

  String get title => switch (kind) {
    CaptureHealthKind.notSetUp => 'Not set up',
    CaptureHealthKind.active => 'Active',
    CaptureHealthKind.pausedByYou => 'Paused by you',
    CaptureHealthKind.permissionRevoked => 'Permission revoked',
  };

  String get message => switch (kind) {
    CaptureHealthKind.notSetUp =>
      'Incoming SMS capture has not been turned on.',
    CaptureHealthKind.active => 'New bank messages can be recorded.',
    CaptureHealthKind.pausedByYou =>
      'SMS capture is paused. New bank messages will not be recorded.',
    CaptureHealthKind.permissionRevoked =>
      'Incoming SMS permission is off. Capture cannot hear new messages.',
  };

  /// Home-widget label. Empty unless there is a warning to show.
  String get widgetLabel => showWarning ? title : '';
}

CaptureHealth captureHealthOf({
  required bool captureEnabled,
  required bool everEnabled,
  required PermissionState sms,
}) {
  final revoked =
      sms == PermissionState.denied || sms == PermissionState.blocked;
  if (captureEnabled && revoked) {
    return const CaptureHealth(CaptureHealthKind.permissionRevoked);
  }
  if (captureEnabled) {
    return const CaptureHealth(CaptureHealthKind.active);
  }
  if (everEnabled) {
    return const CaptureHealth(CaptureHealthKind.pausedByYou);
  }
  return const CaptureHealth(CaptureHealthKind.notSetUp);
}

/// True once the user has turned capture on, or an older install already
/// scanned. A fresh database is false, so the home screen does not say paused.
Future<bool> captureEverEnabled(AppDatabase db) async {
  final settings = await db.getSettings();
  if (settings.messageCaptureEnabled || settings.lastMessageScanAt != null) {
    return true;
  }
  return await metaValue(db, 'capture_ever_enabled') == '1';
}

bool get captureHealthApplies =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

final captureHealthProvider = FutureProvider<CaptureHealth>((ref) async {
  if (!captureHealthApplies) {
    return const CaptureHealth(CaptureHealthKind.active);
  }
  final settings = await ref.watch(settingsProvider.future);
  final ever = await captureEverEnabled(ref.watch(dbProvider));
  final statuses = await AppPermissions.statuses();
  return captureHealthOf(
    captureEnabled: settings.messageCaptureEnabled,
    everEnabled: ever || settings.messageCaptureEnabled,
    sms: statuses[AppPermission.sms] ?? PermissionState.unavailable,
  );
});

/// Banner is the source of truth. The notification follows the existing
/// notifications switch so a user who turned alerts off is not pinged.
/// Widget prefs are written too, so the six-hour check can refresh the label
/// without opening the database or reading a message.
Future<void> syncDeviceCaptureHealth({
  required AppDatabase db,
  required NotificationService notifications,
  required HomeWidgetService widgets,
}) async {
  if (!captureHealthApplies) return;
  final settings = await db.getSettings();
  if (settings.messageCaptureEnabled) {
    await db.rememberCaptureEnabled();
  }
  final ever = await captureEverEnabled(db);
  final statuses = await AppPermissions.statuses();
  final health = captureHealthOf(
    captureEnabled: settings.messageCaptureEnabled,
    everEnabled: ever,
    sms: statuses[AppPermission.sms] ?? PermissionState.unavailable,
  );
  await notifications.syncCaptureHealth(
    show: health.showWarning,
    title: health.title,
    body: health.message,
  );
  await widgets.updateCaptureLabel(
    health.widgetLabel,
    captureEnabled: settings.messageCaptureEnabled,
    everEnabled: ever,
  );
}
