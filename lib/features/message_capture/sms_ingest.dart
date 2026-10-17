import 'package:drift/drift.dart';

import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/ledger_extensions.dart';
import '../../data/tables.dart';
import '../merchants/merchant_store.dart';
import 'parser/sms/sms_capture_parser.dart';
import 'parser/sms/sms_dedupe.dart';
import 'parser/sms/sms_models.dart';

class SmsIngestResult {
  const SmsIngestResult({
    required this.outcome,
    this.transactionId,
    this.duplicate = false,
    this.needsReview = false,
  });

  final SmsParseOutcome outcome;
  final int? transactionId;
  final bool duplicate;
  final bool needsReview;

  bool get posted => transactionId != null && !duplicate;
}

/// Turns one just-arrived SMS into a ledger row, or records it as ignored
/// so a wrong drop can be restored. Never reads an inbox.
class SmsIngestService {
  SmsIngestService({this.parser = const SmsCaptureParser()});

  final SmsCaptureParser parser;

  Future<SmsIngestResult> ingest({
    required AppDatabase db,
    required String sender,
    required String body,
    required DateTime receivedAt,
    bool keepRaw = false,
    bool captureEnabled = true,
  }) async {
    if (!captureEnabled) {
      return SmsIngestResult(
        outcome: const SmsIgnored(SmsIgnoreReason.disabledBank),
      );
    }
    final store = MerchantStore(db);
    final enabled = await _enabledHeaders(db);
    final outcome = parser.parse(
      body: body,
      sender: sender,
      receivedAt: receivedAt,
      enabledHeaders: enabled,
    );

    if (outcome is! SmsParsedMessage) {
      final reason = outcome is SmsIgnored
          ? outcome.reason
          : SmsIgnoreReason.malformed;
      final key = 'drop:${sender.toUpperCase()}|${receivedAt.millisecondsSinceEpoch}|${body.hashCode}';
      if (!await store.dedupeSeen(key)) {
        final id = await store.rememberIgnored(
          dedupeKey: key,
          reason: reason.name,
          receivedAt: receivedAt,
          sender: sender,
          summary: keepRaw ? _summary(body) : null,
          rawBody: keepRaw ? body : null,
        );
        await store.rememberDedupe(key: key, kind: 'ignored', ignoredId: id);
      }
      return SmsIngestResult(outcome: outcome);
    }

    final parsed = outcome.value;
    final key = SmsDedupe.key(
      reference: parsed.reference,
      amountPaise: parsed.amountPaise,
      accountLast4: parsed.accountLast4,
      receivedAt: parsed.timestamp,
      payee: parsed.merchant,
    );
    if (await store.dedupeSeen(key)) {
      return SmsIngestResult(outcome: outcome, duplicate: true);
    }

    final matched = parsed.accountLast4 == null
        ? null
        : await db.accountByLast4(parsed.accountLast4!);
    final unassigned = matched == null;
    final accountId = matched?.id ?? await store.unassignedAccountId();
    if (accountId == null) {
      return SmsIngestResult(outcome: outcome);
    }

    int? categoryId;
    int? merchantId;
    if (parsed.merchant != null) {
      categoryId = await store.categoryForMerchant(parsed.merchant!);
      merchantId = await store.upsertFromRaw(
        parsed.merchant!,
        categoryId: categoryId,
      );
    }
    final needsReview = unassigned || categoryId == null;
    final type = parsed.direction == SmsDirection.debit
        ? TxType.expense
        : TxType.income;

    final id = await db.addTransaction(
      type: type,
      amount: Money(parsed.amountPaise),
      accountId: accountId,
      categoryId: categoryId,
      date: parsed.timestamp,
      payee: parsed.merchant,
      note: parsed.bankName,
    );
    await store.setTxExtra(
      transactionId: id,
      paymentMethod: parsed.paymentMethod,
      bankReference: parsed.reference,
      source: 'SMS',
      needsReview: needsReview,
      merchantId: merchantId,
      rawSms: keepRaw ? body : null,
    );
    await store.rememberDedupe(
      key: key,
      kind: 'posted',
      transactionId: id,
    );
    return SmsIngestResult(
      outcome: outcome,
      transactionId: id,
      needsReview: needsReview,
    );
  }

  /// Rebuilds a transaction from a stored ignore, without the raw SMS.
  Future<int?> restoreIgnored(AppDatabase db, int ignoredId) async {
    final row = await db.customSelect(
      'SELECT * FROM ignored_payments WHERE id = ?',
      variables: [Variable.withInt(ignoredId)],
    ).getSingleOrNull();
    if (row == null || row.read<int>('restored') != 0) return null;
    final amount = row.read<int?>('amount_paise');
    if (amount == null || amount <= 0) return null;
    final store = MerchantStore(db);
    final hint = row.read<String?>('account_hint');
    final matched = hint == null ? null : await db.accountByLast4(hint);
    final accountId = matched?.id ?? await store.unassignedAccountId();
    if (accountId == null) return null;
    final direction = row.read<String?>('direction');
    final type = direction == 'credit' ? TxType.income : TxType.expense;
    final merchant = row.read<String?>('merchant');
    final id = await db.addTransaction(
      type: type,
      amount: Money(amount),
      accountId: accountId,
      date: DateTime.fromMillisecondsSinceEpoch(row.read<int>('received_at')),
      payee: merchant,
      note: 'Restored from ignored payments',
    );
    await store.setTxExtra(
      transactionId: id,
      bankReference: row.read<String?>('reference'),
      source: 'SMS',
      needsReview: true,
    );
    await store.markIgnoredRestored(ignoredId);
    return id;
  }

  Future<Set<String>> _enabledHeaders(AppDatabase db) async {
    final rules = await db.watchSenderRules().first;
    return {
      for (final rule in rules)
        if (rule.enabled) rule.senderPattern.toUpperCase(),
    };
  }

  static String _summary(String body) {
    final flat = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= 140) return flat;
    return '${flat.substring(0, 137)}...';
  }
}
