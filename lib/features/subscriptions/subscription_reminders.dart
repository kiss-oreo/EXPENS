import '../../core/notifications/notification_service.dart';
import '../../data/database.dart';
import '../../data/ledger_extensions.dart';
import '../../data/tables.dart';
import 'subscription_detect.dart';

Future<List<SubscriptionPayment>> loadSubscriptionPayments(
  AppDatabase db,
) async {
  final rows = await db.select(db.transactions).get();
  return [
    for (final row in rows)
      if (row.type == TxType.expense && (row.payee ?? '').trim().isNotEmpty)
        SubscriptionPayment(
          payee: row.payee!,
          amountPaise: row.amount.paise,
          date: row.date,
        ),
  ];
}

/// Posts due reminders. Does not insert, edit, or delete a transaction.
Future<void> deliverSubscriptionReminders({
  required AppDatabase db,
  required NotificationService notifications,
  DateTime? today,
}) async {
  final settings = await db.getSettings();
  if (!settings.notificationsEnabled) return;
  final now = today ?? DateTime.now();
  final guesses = detectSubscriptions(await loadSubscriptionPayments(db));
  final sentRows = await db.customSelect(
    "SELECT key FROM expens_meta WHERE key LIKE 'sub_reminded:%'",
  ).get();
  final sent = {for (final row in sentRows) row.read<String>('key')};
  final planned = planSubscriptionReminders(
    guesses,
    today: now,
    alreadySent: sent,
  );
  for (final reminder in planned) {
    final shown = await notifications.showSubscriptionReminder(
      id: reminder.id,
      title: reminder.title,
      body: reminder.body,
    );
    if (shown) await setMetaValue(db, reminder.key, '1');
  }
}
