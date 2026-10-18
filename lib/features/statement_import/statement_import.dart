import 'package:drift/drift.dart';

import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/ledger_extensions.dart';
import '../../data/tables.dart';
import '../merchants/merchant_names.dart';
import '../merchants/merchant_store.dart';
import 'statement_parser.dart';

/// One parsed row plus whether the ledger already has that payment.
class StatementChoice {
  const StatementChoice({required this.row, required this.existingId});

  final StatementRow row;

  /// Set when this row should update an existing payment, never insert another.
  final int? existingId;

  bool get isDuplicate => existingId != null;
}

class StatementSaveResult {
  const StatementSaveResult({required this.inserted, required this.merged});

  final int inserted;
  final int merged;
}

/// Preview and save. Dedupe is UPI reference, then amount + date + payee.
/// A duplicate merges a richer payee or a missing reference into the existing
/// row. It never creates a second row. New rows are `source = IMPORT_PDF`.
class StatementImportService {
  StatementImportService(this.db);

  final AppDatabase db;

  Future<List<StatementChoice>> preview(List<StatementRow> rows) async {
    final out = <StatementChoice>[];
    for (final row in rows) {
      final existing = await _existingId(row);
      out.add(StatementChoice(row: row, existingId: existing));
    }
    return out;
  }

  Future<StatementSaveResult> save(List<StatementChoice> selected) async {
    var inserted = 0;
    var merged = 0;
    final store = MerchantStore(db);
    for (final choice in selected) {
      if (choice.existingId != null) {
        if (await _merge(choice.existingId!, choice.row)) merged++;
        continue;
      }
      await _insert(store, choice.row);
      inserted++;
    }
    return StatementSaveResult(inserted: inserted, merged: merged);
  }

  Future<int?> _existingId(StatementRow row) async {
    final reference = row.reference?.trim();
    if (reference != null && reference.length >= 6) {
      final hit = await db.customSelect(
        '''
        SELECT transaction_id FROM tx_extras
        WHERE bank_reference IS NOT NULL AND upper(bank_reference) = ?
        LIMIT 1
        ''',
        variables: [Variable.withString(reference.toUpperCase())],
      ).get();
      if (hit.isNotEmpty) return hit.first.read<int>('transaction_id');
    }
    final day = DateTime(row.date.year, row.date.month, row.date.day);
    final next = day.add(const Duration(days: 1));
    final type = row.direction == StatementDirection.debit
        ? TxType.expense
        : TxType.income;
    final sameDay = await (db.select(db.transactions)..where(
          (t) =>
              t.amount.equals(row.amountPaise) &
              t.type.equalsValue(type) &
              t.date.isBiggerOrEqualValue(day) &
              t.date.isSmallerThanValue(next),
        ))
        .get();
    for (final tx in sameDay) {
      if (_related(tx.payee ?? '', row.merchant)) return tx.id;
    }
    return null;
  }

  Future<void> _insert(MerchantStore store, StatementRow row) async {
    final accountId = await _accountId(row.accountLast4);
    final account = await (db.select(db.accounts)
          ..where((a) => a.id.equals(accountId)))
        .getSingle();
    int? categoryId;
    int? merchantId;
    if (row.merchant.trim().isNotEmpty) {
      categoryId = await store.categoryForMerchant(row.merchant);
      merchantId = await store.upsertFromRaw(
        row.merchant,
        categoryId: categoryId,
      );
    }
    final unassigned = account.name == unassignedAccountName;
    final id = await db.addTransaction(
      type: row.direction == StatementDirection.debit
          ? TxType.expense
          : TxType.income,
      amount: Money(row.amountPaise),
      accountId: accountId,
      categoryId: categoryId,
      date: row.date,
      payee: row.merchant,
      note: switch (row.app) {
        StatementApp.gpay => 'Google Pay',
        StatementApp.phonepe => 'PhonePe',
        null => 'Statement',
      },
    );
    await store.setTxExtra(
      transactionId: id,
      paymentMethod: 'UPI',
      bankReference: row.reference,
      source: 'IMPORT_PDF',
      needsReview: unassigned || categoryId == null,
      merchantId: merchantId,
    );
  }

  /// Returns true when an existing row was updated. Never inserts.
  Future<bool> _merge(int id, StatementRow row) async {
    final existing = await (db.select(db.transactions)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (existing == null) return false;
    final store = MerchantStore(db);
    var changed = false;
    if (existing.categoryId == null &&
        existing.type != TxType.transfer &&
        row.merchant.trim().isNotEmpty) {
      final categoryId = await store.categoryForMerchant(row.merchant);
      if (categoryId != null) {
        await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
          TransactionsCompanion(
            categoryId: Value(categoryId),
            updatedAt: Value(DateTime.now()),
          ),
        );
        await store.clearReview(id);
        changed = true;
      }
    }
    final richer = _richerPayee(existing.payee, row.merchant);
    if (richer != null) {
      await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(
          payee: Value(richer),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await store.upsertFromRaw(richer);
      changed = true;
    }
    final reference = row.reference?.trim();
    if (reference != null && reference.isNotEmpty) {
      final before = await db.customSelect(
        'SELECT bank_reference FROM tx_extras WHERE transaction_id = ?',
        variables: [Variable.withInt(id)],
      ).get();
      final current = before.isEmpty
          ? null
          : before.first.read<String?>('bank_reference');
      if (current == null || current.trim().isEmpty) {
        await db.customStatement(
          '''
          INSERT INTO tx_extras (transaction_id, bank_reference)
          VALUES (?, ?)
          ON CONFLICT(transaction_id) DO UPDATE SET
            bank_reference = COALESCE(tx_extras.bank_reference, excluded.bank_reference)
          ''',
          [id, reference],
        );
        changed = true;
      }
    }
    return changed;
  }

  Future<int> _accountId(String? last4) async {
    if (last4 != null) {
      final accounts = await db.select(db.accounts).get();
      for (final account in accounts) {
        if (!account.isArchived && account.last4 == last4) return account.id;
      }
    }
    final quick = await db.resolveQuickAddAccountId();
    if (quick != null) return quick;
    return MerchantStore(db).unassignedAccountId();
  }

  String? _richerPayee(String? existing, String incoming) {
    final next = incoming.trim();
    if (next.isEmpty) return null;
    final current = (existing ?? '').trim();
    if (current.isEmpty) return next;
    if (!_related(current, next)) return null;
    if (MerchantNames.canonical(next).length <=
        MerchantNames.canonical(current).length) {
      return null;
    }
    return next;
  }

  bool _related(String a, String b) {
    if (MerchantNames.sameMerchant(a, b)) return true;
    final left = MerchantNames.normalize(a);
    final right = MerchantNames.normalize(b);
    if (left.length < 4 || right.length < 4) return false;
    return left.contains(right) || right.contains(left);
  }
}
