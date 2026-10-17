import 'package:drift/drift.dart';

import '../../data/database.dart';
import '../../data/ledger_extensions.dart';
import 'merchant_names.dart';

class MerchantRecord {
  const MerchantRecord({
    required this.id,
    required this.name,
    required this.emoji,
    required this.defaultCategoryId,
    required this.aliases,
    this.ruleCategoryId,
  });

  final int id;
  final String name;
  final String? emoji;
  final int? defaultCategoryId;
  final List<String> aliases;
  final int? ruleCategoryId;
}

class CategorisationRuleRecord {
  const CategorisationRuleRecord({
    required this.id,
    required this.merchantId,
    required this.merchantName,
    required this.categoryId,
    required this.enabled,
  });

  final int id;
  final int merchantId;
  final String merchantName;
  final int categoryId;
  final bool enabled;
}

class IgnoredPaymentRecord {
  const IgnoredPaymentRecord({
    required this.id,
    required this.dedupeKey,
    required this.reason,
    required this.receivedAt,
    required this.restored,
    this.amountPaise,
    this.direction,
    this.accountHint,
    this.merchant,
    this.reference,
    this.sender,
    this.summary,
  });

  final int id;
  final String dedupeKey;
  final String reason;
  final DateTime receivedAt;
  final bool restored;
  final int? amountPaise;
  final String? direction;
  final String? accountHint;
  final String? merchant;
  final String? reference;
  final String? sender;
  final String? summary;
}

class TxExtra {
  const TxExtra({
    required this.transactionId,
    required this.source,
    required this.needsReview,
    this.paymentMethod,
    this.bankReference,
    this.merchantId,
  });

  final int transactionId;
  final String source;
  final bool needsReview;
  final String? paymentMethod;
  final String? bankReference;
  final int? merchantId;
}

/// Merchant directory, aliases, and category rules. Sits beside XPENC's
/// free-text payee column so existing transactions keep working.
class MerchantStore {
  MerchantStore(this.db);

  final AppDatabase db;

  Future<List<MerchantRecord>> list() async {
    final rows = await db.customSelect(
      '''
      SELECT m.id, m.name, m.emoji, m.default_category_id, r.category_id AS rule_category
      FROM merchants m
      LEFT JOIN categorisation_rules r ON r.merchant_id = m.id AND r.enabled = 1
      ORDER BY m.name COLLATE NOCASE
      ''',
    ).get();
    final aliases = await db.customSelect(
      'SELECT merchant_id, alias FROM merchant_aliases ORDER BY alias',
    ).get();
    final byMerchant = <int, List<String>>{};
    for (final row in aliases) {
      byMerchant
          .putIfAbsent(row.read<int>('merchant_id'), () => [])
          .add(row.read<String>('alias'));
    }
    return [
      for (final row in rows)
        MerchantRecord(
          id: row.read<int>('id'),
          name: row.read<String>('name'),
          emoji: row.read<String?>('emoji'),
          defaultCategoryId: row.read<int?>('default_category_id'),
          aliases: byMerchant[row.read<int>('id')] ?? const [],
          ruleCategoryId: row.read<int?>('rule_category'),
        ),
    ];
  }

  Future<List<CategorisationRuleRecord>> rules() async {
    final rows = await db.customSelect(
      '''
      SELECT r.id, r.merchant_id, m.name, r.category_id, r.enabled
      FROM categorisation_rules r
      JOIN merchants m ON m.id = r.merchant_id
      ORDER BY m.name COLLATE NOCASE
      ''',
    ).get();
    return [
      for (final row in rows)
        CategorisationRuleRecord(
          id: row.read<int>('id'),
          merchantId: row.read<int>('merchant_id'),
          merchantName: row.read<String>('name'),
          categoryId: row.read<int>('category_id'),
          enabled: row.read<int>('enabled') != 0,
        ),
    ];
  }

  /// Finds or creates the canonical merchant and records [raw] as an alias.
  Future<int> upsertFromRaw(String raw, {int? categoryId, String? emoji}) async {
    final name = MerchantNames.canonical(raw);
    final key = MerchantNames.normalize(raw);
    if (key.isEmpty) {
      throw ArgumentError('Merchant name is empty.');
    }
    final existing = await db.customSelect(
      '''
      SELECT m.id FROM merchants m
      LEFT JOIN merchant_aliases a ON a.merchant_id = m.id
      WHERE m.normalized_name = ? OR a.normalized_alias = ?
      LIMIT 1
      ''',
      variables: [Variable.withString(key), Variable.withString(key)],
    ).get();
    final int id;
    if (existing.isEmpty) {
      id = await db.customInsert(
        '''
        INSERT INTO merchants (name, normalized_name, default_category_id, emoji, created_at)
        VALUES (?, ?, ?, ?, ?)
        ''',
        variables: [
          Variable.withString(name),
          Variable.withString(key),
          Variable<int>(categoryId),
          Variable<String>(emoji),
          Variable.withInt(DateTime.now().millisecondsSinceEpoch),
        ],
      );
    } else {
      id = existing.first.read<int>('id');
      if (categoryId != null) {
        await db.customUpdate(
          '''
          UPDATE merchants SET default_category_id = ?
          WHERE id = ? AND default_category_id IS NULL
          ''',
          variables: [Variable.withInt(categoryId), Variable.withInt(id)],
        );
      }
      if (emoji != null && emoji.isNotEmpty) {
        await db.customUpdate(
          'UPDATE merchants SET emoji = ? WHERE id = ? AND (emoji IS NULL OR emoji = \'\')',
          variables: [Variable.withString(emoji), Variable.withInt(id)],
        );
      }
    }
    await db.customStatement(
      '''
      INSERT OR IGNORE INTO merchant_aliases (merchant_id, alias, normalized_alias)
      VALUES (?, ?, ?)
      ''',
      [id, raw.trim(), key],
    );
    if (categoryId != null) {
      await saveRule(merchantId: id, categoryId: categoryId);
    }
    return id;
  }

  Future<void> saveRule({
    required int merchantId,
    required int categoryId,
    bool enabled = true,
  }) async {
    await db.customStatement(
      '''
      INSERT INTO categorisation_rules (merchant_id, category_id, enabled)
      VALUES (?, ?, ?)
      ON CONFLICT(merchant_id) DO UPDATE SET
        category_id = excluded.category_id,
        enabled = excluded.enabled
      ''',
      [merchantId, categoryId, enabled ? 1 : 0],
    );
    final name = await db.customSelect(
      'SELECT name FROM merchants WHERE id = ?',
      variables: [Variable.withInt(merchantId)],
    ).getSingleOrNull();
    if (name != null) {
      await db.upsertMerchantRule(
        pattern: name.read<String>('name'),
        categoryId: categoryId,
      );
    }
  }

  Future<void> setRuleEnabled(int ruleId, bool enabled) async {
    await db.customUpdate(
      'UPDATE categorisation_rules SET enabled = ? WHERE id = ?',
      variables: [
        Variable.withInt(enabled ? 1 : 0),
        Variable.withInt(ruleId),
      ],
    );
  }

  Future<void> setDefaultCategory(int merchantId, int categoryId) async {
    await db.customUpdate(
      'UPDATE merchants SET default_category_id = ? WHERE id = ?',
      variables: [Variable.withInt(categoryId), Variable.withInt(merchantId)],
    );
    await saveRule(merchantId: merchantId, categoryId: categoryId);
  }

  /// Sets one income/expense row's category. [applyToAll] also rewrites every
  /// other row from that merchant and saves the rule. Transfers are left alone.
  Future<void> setTransactionCategory({
    required int transactionId,
    required int categoryId,
    String? payee,
    bool applyToAll = false,
  }) async {
    await db.customUpdate(
      '''
      UPDATE transactions
      SET category_id = ?, updated_at = ?
      WHERE id = ? AND type IN ('expense', 'income')
      ''',
      variables: [
        Variable.withInt(categoryId),
        Variable.withDateTime(DateTime.now()),
        Variable.withInt(transactionId),
      ],
      updates: {db.transactions},
    );
    if (applyToAll && payee != null && payee.trim().isNotEmpty) {
      await applyCategoryToAll(payee: payee, categoryId: categoryId);
    }
    await clearReview(transactionId);
  }

  Future<void> clearReview(int transactionId) async {
    await db.customUpdate(
      'UPDATE tx_extras SET needs_review = 0 WHERE transaction_id = ?',
      variables: [Variable.withInt(transactionId)],
    );
  }

  Future<void> deleteRule(int ruleId) async {
    await db.customUpdate(
      'DELETE FROM categorisation_rules WHERE id = ?',
      variables: [Variable.withInt(ruleId)],
    );
  }

  Future<int?> categoryForMerchant(String raw) async {
    final key = MerchantNames.normalize(raw);
    if (key.isEmpty) return null;
    final rows = await db.customSelect(
      '''
      SELECT r.category_id
      FROM merchants m
      JOIN categorisation_rules r ON r.merchant_id = m.id AND r.enabled = 1
      LEFT JOIN merchant_aliases a ON a.merchant_id = m.id
      WHERE m.normalized_name = ? OR a.normalized_alias = ?
      LIMIT 1
      ''',
      variables: [Variable.withString(key), Variable.withString(key)],
    ).get();
    if (rows.isEmpty) return null;
    return rows.first.read<int>('category_id');
  }

  /// Rewrites every income/expense that names this merchant (or any alias)
  /// and saves the mapping as a rule.
  Future<int> applyCategoryToAll({
    required String payee,
    required int categoryId,
  }) async {
    final merchantId = await upsertFromRaw(payee, categoryId: categoryId);
    final names = await _namesFor(merchantId);
    var updated = 0;
    for (final name in names) {
      updated += await db.customUpdate(
        '''
        UPDATE transactions
        SET category_id = ?, updated_at = ?
        WHERE payee = ? AND type IN ('expense', 'income')
        ''',
        variables: [
          Variable.withInt(categoryId),
          Variable.withDateTime(DateTime.now()),
          Variable.withString(name),
        ],
        updates: {db.transactions},
      );
    }
    await saveRule(merchantId: merchantId, categoryId: categoryId);
    return updated;
  }

  Future<List<String>> _namesFor(int merchantId) async {
    final rows = await db.customSelect(
      '''
      SELECT name AS label FROM merchants WHERE id = ?
      UNION
      SELECT alias AS label FROM merchant_aliases WHERE merchant_id = ?
      ''',
      variables: [Variable.withInt(merchantId), Variable.withInt(merchantId)],
    ).get();
    return [for (final row in rows) row.read<String>('label')];
  }

  /// Keeps [keepId] and folds [dropId] into it: aliases, rules, payee text.
  Future<void> merge({required int keepId, required int dropId}) async {
    if (keepId == dropId) return;
    final drop = await db.customSelect(
      'SELECT name FROM merchants WHERE id = ?',
      variables: [Variable.withInt(dropId)],
    ).getSingleOrNull();
    final keep = await db.customSelect(
      'SELECT name FROM merchants WHERE id = ?',
      variables: [Variable.withInt(keepId)],
    ).getSingleOrNull();
    if (drop == null || keep == null) {
      throw ArgumentError('Merchant not found.');
    }
    final keepName = keep.read<String>('name');
    final dropNames = await _namesFor(dropId);
    await db.transaction(() async {
      for (final name in dropNames) {
        await db.customUpdate(
          '''
          UPDATE transactions SET payee = ?, updated_at = ?
          WHERE payee = ?
          ''',
          variables: [
            Variable.withString(keepName),
            Variable.withDateTime(DateTime.now()),
            Variable.withString(name),
          ],
          updates: {db.transactions},
        );
      }
      await db.customStatement(
        '''
        INSERT OR IGNORE INTO merchant_aliases (merchant_id, alias, normalized_alias)
        SELECT ?, alias, normalized_alias FROM merchant_aliases WHERE merchant_id = ?
        ''',
        [keepId, dropId],
      );
      await db.customStatement(
        '''
        INSERT OR IGNORE INTO merchant_aliases (merchant_id, alias, normalized_alias)
        VALUES (?, ?, ?)
        ''',
        [keepId, drop.read<String>('name'), MerchantNames.normalize(drop.read<String>('name'))],
      );
      await db.customStatement(
        'DELETE FROM merchant_aliases WHERE merchant_id = ?',
        [dropId],
      );
      await db.customStatement(
        '''
        INSERT OR IGNORE INTO categorisation_rules (merchant_id, category_id, enabled)
        SELECT ?, category_id, enabled FROM categorisation_rules WHERE merchant_id = ?
        ''',
        [keepId, dropId],
      );
      await db.customStatement(
        'DELETE FROM categorisation_rules WHERE merchant_id = ?',
        [dropId],
      );
      await db.customStatement(
        'UPDATE tx_extras SET merchant_id = ? WHERE merchant_id = ?',
        [keepId, dropId],
      );
      await db.customStatement('DELETE FROM merchants WHERE id = ?', [dropId]);
    });
  }

  Future<void> setEmoji(int merchantId, String? emoji) async {
    await db.customUpdate(
      'UPDATE merchants SET emoji = ? WHERE id = ?',
      variables: [Variable<String>(emoji), Variable.withInt(merchantId)],
    );
  }

  Future<void> addAlias(int merchantId, String alias) async {
    final key = MerchantNames.normalize(alias);
    if (key.isEmpty) throw ArgumentError('Alias is empty.');
    await db.customStatement(
      '''
      INSERT OR IGNORE INTO merchant_aliases (merchant_id, alias, normalized_alias)
      VALUES (?, ?, ?)
      ''',
      [merchantId, alias.trim(), key],
    );
  }

  Future<void> setTxExtra({
    required int transactionId,
    String? paymentMethod,
    String? bankReference,
    String source = 'MANUAL',
    bool needsReview = false,
    int? merchantId,
    String? rawSms,
  }) async {
    await db.customStatement(
      '''
      INSERT INTO tx_extras (
        transaction_id, payment_method, bank_reference, source,
        needs_review, merchant_id, raw_sms
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(transaction_id) DO UPDATE SET
        payment_method = excluded.payment_method,
        bank_reference = excluded.bank_reference,
        source = excluded.source,
        needs_review = excluded.needs_review,
        merchant_id = excluded.merchant_id,
        raw_sms = COALESCE(excluded.raw_sms, tx_extras.raw_sms)
      ''',
      [
        transactionId,
        paymentMethod,
        bankReference,
        source,
        needsReview ? 1 : 0,
        merchantId,
        rawSms,
      ],
    );
  }

  Future<TxExtra?> extraFor(int transactionId) async {
    final row = await db.customSelect(
      'SELECT * FROM tx_extras WHERE transaction_id = ?',
      variables: [Variable.withInt(transactionId)],
    ).getSingleOrNull();
    if (row == null) return null;
    return TxExtra(
      transactionId: transactionId,
      source: row.read<String>('source'),
      needsReview: row.read<int>('needs_review') != 0,
      paymentMethod: row.read<String?>('payment_method'),
      bankReference: row.read<String?>('bank_reference'),
      merchantId: row.read<int?>('merchant_id'),
    );
  }

  Future<Map<int, TxExtra>> extrasById() async {
    final rows = await db.customSelect('SELECT * FROM tx_extras').get();
    return {
      for (final row in rows)
        row.read<int>('transaction_id'): TxExtra(
          transactionId: row.read<int>('transaction_id'),
          source: row.read<String>('source'),
          needsReview: row.read<int>('needs_review') != 0,
          paymentMethod: row.read<String?>('payment_method'),
          bankReference: row.read<String?>('bank_reference'),
          merchantId: row.read<int?>('merchant_id'),
        ),
    };
  }

  Future<int?> unassignedAccountId() async {
    final row = await db.customSelect(
      'SELECT id FROM accounts WHERE name = ? LIMIT 1',
      variables: [Variable.withString(unassignedAccountName)],
    ).getSingleOrNull();
    return row?.read<int>('id');
  }

  Future<bool> dedupeSeen(String key) async {
    final rows = await db.customSelect(
      'SELECT 1 FROM capture_dedupe WHERE dedupe_key = ?',
      variables: [Variable.withString(key)],
    ).get();
    return rows.isNotEmpty;
  }

  Future<void> rememberDedupe({
    required String key,
    required String kind,
    int? transactionId,
    int? ignoredId,
  }) async {
    await db.customStatement(
      '''
      INSERT OR IGNORE INTO capture_dedupe
        (dedupe_key, kind, transaction_id, ignored_id, created_at)
      VALUES (?, ?, ?, ?, ?)
      ''',
      [
        key,
        kind,
        transactionId,
        ignoredId,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  Future<int> rememberIgnored({
    required String dedupeKey,
    required String reason,
    required DateTime receivedAt,
    int? amountPaise,
    String? direction,
    String? accountHint,
    String? merchant,
    String? reference,
    String? sender,
    String? summary,
    String? rawBody,
  }) async {
    await db.customStatement(
      '''
      INSERT OR IGNORE INTO ignored_payments (
        dedupe_key, amount_paise, direction, account_hint, merchant,
        reference, sender, received_at, reason, summary, raw_body, restored
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
      ''',
      [
        dedupeKey,
        amountPaise,
        direction,
        accountHint,
        merchant,
        reference,
        sender,
        receivedAt.millisecondsSinceEpoch,
        reason,
        summary,
        rawBody,
      ],
    );
    final row = await db.customSelect(
      'SELECT id FROM ignored_payments WHERE dedupe_key = ?',
      variables: [Variable.withString(dedupeKey)],
    ).getSingle();
    return row.read<int>('id');
  }

  Future<List<IgnoredPaymentRecord>> ignored({bool includeRestored = false}) async {
    final rows = await db.customSelect(
      '''
      SELECT * FROM ignored_payments
      WHERE restored = 0 OR ? = 1
      ORDER BY received_at DESC
      ''',
      variables: [Variable.withInt(includeRestored ? 1 : 0)],
    ).get();
    return [
      for (final row in rows)
        IgnoredPaymentRecord(
          id: row.read<int>('id'),
          dedupeKey: row.read<String>('dedupe_key'),
          reason: row.read<String>('reason'),
          receivedAt: DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('received_at'),
          ),
          restored: row.read<int>('restored') != 0,
          amountPaise: row.read<int?>('amount_paise'),
          direction: row.read<String?>('direction'),
          accountHint: row.read<String?>('account_hint'),
          merchant: row.read<String?>('merchant'),
          reference: row.read<String?>('reference'),
          sender: row.read<String?>('sender'),
          summary: row.read<String?>('summary'),
        ),
    ];
  }

  Future<void> markIgnoredRestored(int id) async {
    await db.customUpdate(
      'UPDATE ignored_payments SET restored = 1 WHERE id = ?',
      variables: [Variable.withInt(id)],
    );
  }
}
