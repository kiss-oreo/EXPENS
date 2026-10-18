import 'package:flutter_test/flutter_test.dart';
import 'package:xpenc/core/permissions/app_permissions.dart';
import 'package:xpenc/features/message_capture/capture_health.dart';

void main() {
  test('paused and revoked capture are visible, a healthy grant is not', () {
    final paused = captureHealthOf(
      captureEnabled: false,
      sms: PermissionState.granted,
    );
    expect(paused.showBanner, isTrue);
    expect(paused.title, 'Capture paused');
    expect(paused.widgetLabel, 'Capture paused');

    final revoked = captureHealthOf(
      captureEnabled: true,
      sms: PermissionState.denied,
    );
    expect(revoked.kind, CaptureHealthKind.permissionRevoked);
    expect(revoked.message, contains('permission'));

    final blocked = captureHealthOf(
      captureEnabled: true,
      sms: PermissionState.blocked,
    );
    expect(blocked.kind, CaptureHealthKind.permissionRevoked);

    final ok = captureHealthOf(
      captureEnabled: true,
      sms: PermissionState.granted,
    );
    expect(ok.showBanner, isFalse);
    expect(ok.widgetLabel, isEmpty);

    final unavailable = captureHealthOf(
      captureEnabled: true,
      sms: PermissionState.unavailable,
    );
    expect(unavailable.showBanner, isFalse);
  });
}
