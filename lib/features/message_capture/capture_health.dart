import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/home_widget/home_widget_service.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/permissions/app_permissions.dart';
import '../../data/providers.dart';

enum CaptureHealthKind { ok, paused, permissionRevoked }

class CaptureHealth {
  const CaptureHealth(this.kind);

  final CaptureHealthKind kind;

  bool get showBanner => kind != CaptureHealthKind.ok;

  String get title => switch (kind) {
    CaptureHealthKind.ok => '',
    CaptureHealthKind.paused => 'Capture paused',
    CaptureHealthKind.permissionRevoked => 'SMS permission is off',
  };

  String get message => switch (kind) {
    CaptureHealthKind.ok => '',
    CaptureHealthKind.paused =>
      'SMS capture is paused. New bank messages will not be recorded.',
    CaptureHealthKind.permissionRevoked =>
      'Incoming SMS permission is off. Capture cannot hear new messages.',
  };

  /// Optional home-widget label. Empty when capture is healthy.
  String get widgetLabel => showBanner ? 'Capture paused' : '';
}

CaptureHealth captureHealthOf({
  required bool captureEnabled,
  required PermissionState sms,
}) {
  final revoked =
      sms == PermissionState.denied || sms == PermissionState.blocked;
  if (captureEnabled && revoked) {
    return const CaptureHealth(CaptureHealthKind.permissionRevoked);
  }
  if (!captureEnabled) {
    return const CaptureHealth(CaptureHealthKind.paused);
  }
  return const CaptureHealth(CaptureHealthKind.ok);
}

bool get captureHealthApplies =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

final captureHealthProvider = FutureProvider<CaptureHealth>((ref) async {
  if (!captureHealthApplies) {
    return const CaptureHealth(CaptureHealthKind.ok);
  }
  final settings = await ref.watch(settingsProvider.future);
  final statuses = await AppPermissions.statuses();
  return captureHealthOf(
    captureEnabled: settings.messageCaptureEnabled,
    sms: statuses[AppPermission.sms] ?? PermissionState.unavailable,
  );
});

/// Banner is the source of truth. The notification follows the existing
/// notifications switch so a user who turned alerts off is not pinged.
Future<void> syncDeviceCaptureHealth({
  required bool captureEnabled,
  required NotificationService notifications,
  required HomeWidgetService widgets,
}) async {
  if (!captureHealthApplies) return;
  final statuses = await AppPermissions.statuses();
  final health = captureHealthOf(
    captureEnabled: captureEnabled,
    sms: statuses[AppPermission.sms] ?? PermissionState.unavailable,
  );
  await notifications.syncCaptureHealth(
    show: health.showBanner,
    title: health.title,
    body: health.message,
  );
  await widgets.updateCaptureLabel(health.widgetLabel);
}
