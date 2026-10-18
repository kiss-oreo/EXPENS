import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/ledger_extensions.dart';
import '../../data/tables.dart';
import '../merchants/merchant_store.dart';

/// Amount, then merchant, then save. Category rules and aliases run first.
/// An uncategorised or unassigned row is flagged for review. Never throws
/// on a bad amount — it returns an error string instead.
Future<String?> saveQuickAdd({
  required AppDatabase db,
  required String amountText,
  required String merchant,
  DateTime? date,
}) async {
  final paise = paiseFromExactDecimal(amountText);
  if (paise == null || paise <= 0) return 'Enter an amount.';
  final accountId = await db.resolveQuickAddAccountId();
  if (accountId == null) return 'Add an account before saving.';
  final account = await (db.select(db.accounts)
        ..where((a) => a.id.equals(accountId)))
      .getSingle();
  final store = MerchantStore(db);
  final name = merchant.trim();
  int? categoryId;
  int? merchantId;
  if (name.isNotEmpty) {
    categoryId = await store.categoryForMerchant(name);
    merchantId = await store.upsertFromRaw(name, categoryId: categoryId);
  }
  final id = await db.addTransaction(
    type: TxType.expense,
    amount: Money(paise),
    accountId: accountId,
    categoryId: categoryId,
    date: date ?? DateTime.now(),
    payee: name.isEmpty ? null : name,
  );
  await store.setTxExtra(
    transactionId: id,
    source: 'MANUAL',
    needsReview: categoryId == null || account.name == unassignedAccountName,
    merchantId: merchantId,
  );
  return null;
}

/// `250.50` → 25050. Integer arithmetic only. Null when the text is not an amount.
int? paiseFromExactDecimal(String input) {
  final cleaned = input.replaceAll(',', '').replaceAll(RegExp(r'[^0-9.]'), '');
  if (cleaned.isEmpty || !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(cleaned)) {
    return null;
  }
  final parts = cleaned.split('.');
  final rupees = int.tryParse(parts[0]);
  if (rupees == null) return null;
  var frac = 0;
  if (parts.length == 2) {
    final f = parts[1];
    frac = f.length == 1 ? int.parse(f) * 10 : int.parse(f);
  }
  return rupees * 100 + frac;
}
