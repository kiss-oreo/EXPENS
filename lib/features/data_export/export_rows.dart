import 'package:drift/drift.dart';

import '../../data/database.dart';
import '../merchants/merchant_store.dart';
import 'export_format.dart';

/// Loads ledger rows in the accountant export shape. Transfers are included
/// so the file is complete; category summaries drop them separately.
Future<List<ExportRow>> loadExportRows(
  AppDatabase db, {
  ExportFilter filter = const ExportFilter(),
}) async {
  final txs = await (db.select(db.transactions)
        ..orderBy([(t) => OrderingTerm(expression: t.date)]))
      .get();
  final accounts = {
    for (final a in await db.select(db.accounts).get()) a.id: a,
  };
  final categories = {
    for (final c in await db.select(db.categories).get()) c.id: c,
  };
  final tagRows = await db.customSelect(
    '''
    SELECT tt.transaction_id, t.name
    FROM transaction_tags tt
    JOIN tags t ON t.id = tt.tag_id
    ORDER BY t.name
    ''',
  ).get();
  final tags = <int, List<String>>{};
  for (final row in tagRows) {
    tags
        .putIfAbsent(row.read<int>('transaction_id'), () => [])
        .add(row.read<String>('name'));
  }
  final extras = await MerchantStore(db).extrasById();

  final out = <ExportRow>[];
  for (final tx in txs) {
    final category = tx.categoryId == null ? null : categories[tx.categoryId];
    final parent = category?.parentId == null
        ? null
        : categories[category!.parentId];
    final extra = extras[tx.id];
    final row = ExportRow(
      date: tx.date,
      type: typeLabel(tx.type.name),
      amountPaise: tx.amount.paise,
      account: accounts[tx.accountId]?.name ?? '',
      category: parent?.name ?? category?.name ?? '',
      subcategory: parent == null ? '' : (category?.name ?? ''),
      merchant: tx.payee ?? '',
      paymentMethod: extra?.paymentMethod ?? '',
      referenceNo: extra?.bankReference ?? '',
      note: tx.note ?? '',
      tags: (tags[tx.id] ?? const []).join('; '),
      source: extra?.source ?? 'MANUAL',
    );
    if (filter.accepts(row)) out.add(row);
  }
  return out;
}
