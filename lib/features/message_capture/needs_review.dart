import '../../data/database.dart';
import '../../data/ledger_extensions.dart';
import '../../data/tables.dart';

class ReviewItem {
  const ReviewItem({
    required this.id,
    required this.payee,
    required this.amountPaise,
    required this.date,
    required this.reasons,
  });

  final int id;
  final String? payee;
  final int amountPaise;
  final DateTime date;
  final List<String> reasons;

  String get reasonLabel => reasons.join(' · ');
}

/// Unassigned or uncategorised SMS payments, plus any row already flagged
/// `needs_review`. Transfers are not included.
Future<List<ReviewItem>> loadNeedsReview(AppDatabase db) async {
  final txs = await (db.select(db.transactions)..where(
        (t) =>
            t.type.equalsValue(TxType.expense) |
            t.type.equalsValue(TxType.income),
      )).get();
  final accounts = await db.select(db.accounts).get();
  final accountName = {for (final a in accounts) a.id: a.name};
  final extras = await db.customSelect(
    'SELECT transaction_id, needs_review, source FROM tx_extras',
  ).get();
  final extraById = <int, ({bool review, String? source})>{};
  for (final row in extras) {
    extraById[row.read<int>('transaction_id')] = (
      review: row.read<int>('needs_review') != 0,
      source: row.read<String?>('source'),
    );
  }
  final out = <ReviewItem>[];
  for (final tx in txs) {
    final extra = extraById[tx.id];
    final reasons = <String>[];
    if (accountName[tx.accountId] == unassignedAccountName) {
      reasons.add('Unassigned account');
    }
    if (extra?.review == true) reasons.add('Marked for review');
    if (extra?.source == 'SMS' && tx.categoryId == null) {
      reasons.add('No category');
    }
    if (reasons.isEmpty) continue;
    out.add(
      ReviewItem(
        id: tx.id,
        payee: tx.payee,
        amountPaise: tx.amount.paise,
        date: tx.date,
        reasons: reasons,
      ),
    );
  }
  out.sort((a, b) => b.date.compareTo(a.date));
  return out;
}
