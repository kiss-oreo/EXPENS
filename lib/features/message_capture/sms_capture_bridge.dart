import 'package:flutter/services.dart';

import '../../core/notifications/notification_service.dart';
import '../../data/database.dart';
import '../../data/ledger_extensions.dart';
import 'parser/sms/sms_models.dart';
import 'sms_ingest.dart';

/// Talks to the manifest [BroadcastReceiver]. The receiver only ever hands
/// over the SMS that just arrived. This bridge never queries the inbox.
class SmsCaptureBridge {
  SmsCaptureBridge._();

  static const channel = MethodChannel('expens/sms');
  static final _ingest = SmsIngestService();

  static Future<void> attach(
    AppDatabase db,
    NotificationService notifications,
  ) async {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onSms') {
        final args = call.arguments;
        if (args is Map) {
          await _handleMap(db, notifications, args);
        }
      }
      return null;
    });
    await drain(db, notifications);
  }

  static Future<void> drain(
    AppDatabase db,
    NotificationService notifications,
  ) async {
    try {
      final queued = await channel.invokeMethod<List<dynamic>>('drain');
      if (queued == null) return;
      for (final item in queued) {
        if (item is Map) await _handleMap(db, notifications, item);
      }
    } on MissingPluginException {
      // Desktop tests and iOS have no receiver. Capture simply does nothing.
    } on PlatformException {
      return;
    }
  }

  static Future<void> setEnabled(bool enabled) async {
    try {
      await channel.invokeMethod<void>('setEnabled', enabled);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static Future<void> setKeepRaw(bool keep) async {
    try {
      await channel.invokeMethod<void>('setKeepRaw', keep);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static Future<void> _handleMap(
    AppDatabase db,
    NotificationService notifications,
    Map<dynamic, dynamic> args,
  ) async {
    final sender = args['sender'] as String? ?? '';
    final body = args['body'] as String? ?? '';
    final at = args['receivedAt'] as int?;
    if (body.isEmpty) return;
    final settings = await db.getSettings();
    final result = await _ingest.ingest(
      db: db,
      sender: sender,
      body: body,
      receivedAt: at == null
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(at),
      keepRaw: await keepRawSms(db),
      captureEnabled: settings.messageCaptureEnabled,
    );
    final outcome = result.outcome;
    if (result.posted && outcome is SmsParsedMessage) {
      final parsed = outcome.value;
      await notifications.showCaptured(
        transactionId: result.transactionId!,
        body: captureNotificationBody(
          amountPaise: parsed.amountPaise,
          spent: parsed.direction == SmsDirection.debit,
          merchant: parsed.merchant,
        ),
      );
    }
  }
}
