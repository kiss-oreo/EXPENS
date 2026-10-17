import 'package:drift/drift.dart';

/// Side tables Expens adds on top of the XPENC Drift schema.
///
/// They are created with raw SQL rather than a Drift table class so a schema
/// change does not require regenerating `database.g.dart`. Every statement
/// is idempotent. User rows in the XPENC tables are never dropped.
///
/// Money columns are integer paise. Timestamps are unix milliseconds.

const unassignedAccountName = 'Unassigned';

const _senderSeeds = <(String, String)>[
  ('HDFCBK', 'HDFC Bank'),
  ('HDFCBN', 'HDFC Bank'),
  ('SBIINB', 'State Bank of India'),
  ('SBIUPI', 'State Bank of India'),
  ('SBIPSG', 'State Bank of India'),
  ('ICICIB', 'ICICI Bank'),
  ('ICICIT', 'ICICI Bank'),
  ('AXISBK', 'Axis Bank'),
  ('KOTAKB', 'Kotak Mahindra Bank'),
  ('PNBSMS', 'Punjab National Bank'),
  ('PNBBNK', 'Punjab National Bank'),
  ('BOBTXN', 'Bank of Baroda'),
  ('BOBSMS', 'Bank of Baroda'),
  ('CANBNK', 'Canara Bank'),
  ('CNRBNK', 'Canara Bank'),
  ('UNIONB', 'Union Bank of India'),
  ('IDFCFB', 'IDFC FIRST Bank'),
  ('IDFCBK', 'IDFC FIRST Bank'),
  ('YESBNK', 'Yes Bank'),
  ('IPPBNK', 'India Post Payments Bank'),
  ('IPPB', 'India Post Payments Bank'),
];

Future<void> ensureLedgerExtensions(GeneratedDatabase db) async {
  await db.customStatement('''
    CREATE TABLE IF NOT EXISTS merchants (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      normalized_name TEXT NOT NULL UNIQUE,
      default_category_id INTEGER,
      emoji TEXT,
      created_at INTEGER NOT NULL
    )
  ''');
  await db.customStatement('''
    CREATE TABLE IF NOT EXISTS merchant_aliases (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      merchant_id INTEGER NOT NULL,
      alias TEXT NOT NULL,
      normalized_alias TEXT NOT NULL UNIQUE
    )
  ''');
  await db.customStatement('''
    CREATE TABLE IF NOT EXISTS categorisation_rules (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      merchant_id INTEGER NOT NULL UNIQUE,
      category_id INTEGER NOT NULL,
      enabled INTEGER NOT NULL DEFAULT 1
    )
  ''');
  await db.customStatement('''
    CREATE TABLE IF NOT EXISTS tx_extras (
      transaction_id INTEGER PRIMARY KEY,
      payment_method TEXT,
      bank_reference TEXT,
      source TEXT NOT NULL DEFAULT 'MANUAL',
      needs_review INTEGER NOT NULL DEFAULT 0,
      merchant_id INTEGER,
      raw_sms TEXT
    )
  ''');
  await db.customStatement('''
    CREATE TABLE IF NOT EXISTS ignored_payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      dedupe_key TEXT NOT NULL UNIQUE,
      amount_paise INTEGER,
      direction TEXT,
      account_hint TEXT,
      merchant TEXT,
      reference TEXT,
      sender TEXT,
      received_at INTEGER NOT NULL,
      reason TEXT NOT NULL,
      summary TEXT,
      raw_body TEXT,
      restored INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.customStatement('''
    CREATE TABLE IF NOT EXISTS capture_dedupe (
      dedupe_key TEXT PRIMARY KEY,
      kind TEXT NOT NULL,
      transaction_id INTEGER,
      ignored_id INTEGER,
      created_at INTEGER NOT NULL
    )
  ''');
  await db.customStatement('''
    CREATE TABLE IF NOT EXISTS expens_meta (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''');

  await _seedSenderHeaders(db);
}

/// Holding account for an SMS that names no known account. Created only when
/// a message needs it, so a fresh ledger stays the single Cash account tests
/// and a new install expect.
Future<void> ensureUnassignedAccount(GeneratedDatabase db) async {
  await db.customStatement(
    '''
    INSERT INTO accounts (
      name, type, color_value, icon_key, opening_balance, current_balance,
      is_archived, sort_order, include_in_net_worth
    )
    SELECT ?, 'cash', ?, 'other', 0, 0, 0, 999, 1
    WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE name = ?)
    ''',
    [unassignedAccountName, 0xFF64748B, unassignedAccountName],
  );
}

Future<void> _seedSenderHeaders(GeneratedDatabase db) async {
  for (final (pattern, bank) in _senderSeeds) {
    await db.customStatement(
      '''
      INSERT OR IGNORE INTO sender_rules (sender_pattern, bank_name, enabled)
      VALUES (?, ?, 1)
      ''',
      [pattern, bank],
    );
  }
}

Future<bool> ledgerTableExists(GeneratedDatabase db, String table) async {
  final rows = await db
      .customSelect(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        variables: [Variable.withString(table)],
      )
      .get();
  return rows.isNotEmpty;
}

Future<void> deleteLedgerExtensions(GeneratedDatabase db) async {
  for (final table in const [
    'merchant_aliases',
    'categorisation_rules',
    'tx_extras',
    'ignored_payments',
    'capture_dedupe',
    'merchants',
    'expens_meta',
  ]) {
    if (await ledgerTableExists(db, table)) {
      await db.customStatement('DELETE FROM $table');
    }
  }
}

Future<String?> metaValue(GeneratedDatabase db, String key) async {
  final rows = await db
      .customSelect(
        'SELECT value FROM expens_meta WHERE key = ?',
        variables: [Variable.withString(key)],
      )
      .get();
  if (rows.isEmpty) return null;
  return rows.first.read<String>('value');
}

Future<void> setMetaValue(
  GeneratedDatabase db,
  String key,
  String value,
) async {
  await db.customStatement(
    '''
    INSERT INTO expens_meta (key, value) VALUES (?, ?)
    ON CONFLICT(key) DO UPDATE SET value = excluded.value
    ''',
    [key, value],
  );
}

Future<bool> keepRawSms(GeneratedDatabase db) async =>
    (await metaValue(db, 'keep_raw_sms')) == '1';

Future<Map<String, dynamic>> exportLedgerExtensions(
  GeneratedDatabase db,
) async {
  Future<List<Map<String, Object?>>> dump(String table) async {
    if (!await ledgerTableExists(db, table)) return const [];
    final rows = await db.customSelect('SELECT * FROM $table').get();
    return [for (final row in rows) Map<String, Object?>.from(row.data)];
  }

  return {
    'merchants': await dump('merchants'),
    'merchantAliases': await dump('merchant_aliases'),
    'categorisationRules': await dump('categorisation_rules'),
    'txExtras': await dump('tx_extras'),
    'ignoredPayments': await dump('ignored_payments'),
    'captureDedupe': await dump('capture_dedupe'),
    'expensMeta': await dump('expens_meta'),
  };
}

const _importColumns = <String, Set<String>>{
  'merchants': {
    'id',
    'name',
    'normalized_name',
    'default_category_id',
    'emoji',
    'created_at',
  },
  'merchant_aliases': {'id', 'merchant_id', 'alias', 'normalized_alias'},
  'categorisation_rules': {'id', 'merchant_id', 'category_id', 'enabled'},
  'tx_extras': {
    'transaction_id',
    'payment_method',
    'bank_reference',
    'source',
    'needs_review',
    'merchant_id',
    'raw_sms',
  },
  'ignored_payments': {
    'id',
    'dedupe_key',
    'amount_paise',
    'direction',
    'account_hint',
    'merchant',
    'reference',
    'sender',
    'received_at',
    'reason',
    'summary',
    'raw_body',
    'restored',
  },
  'capture_dedupe': {
    'dedupe_key',
    'kind',
    'transaction_id',
    'ignored_id',
    'created_at',
  },
  'expens_meta': {'key', 'value'},
};

/// Restores extension tables from a backup. Missing keys (an XPENC backup
/// that predates them) are a no-op. Unknown columns are ignored.
Future<void> importLedgerExtensions(
  GeneratedDatabase db,
  Map<String, dynamic> data,
) async {
  await deleteLedgerExtensions(db);
  await _load(db, 'merchants', data['merchants']);
  await _load(db, 'merchant_aliases', data['merchantAliases']);
  await _load(db, 'categorisation_rules', data['categorisationRules']);
  await _load(db, 'tx_extras', data['txExtras']);
  await _load(db, 'ignored_payments', data['ignoredPayments']);
  await _load(db, 'capture_dedupe', data['captureDedupe']);
  await _load(db, 'expens_meta', data['expensMeta']);
}

Future<void> _load(GeneratedDatabase db, String table, Object? raw) async {
  if (raw is! List) return;
  final allowed = _importColumns[table]!;
  for (final item in raw) {
    if (item is! Map) continue;
    final map = <String, Object?>{};
    item.forEach((key, value) {
      if (key is String && allowed.contains(key)) map[key] = value;
    });
    if (map.isEmpty) continue;
    final cols = map.keys.map((k) => '"$k"').join(', ');
    final marks = List.filled(map.length, '?').join(', ');
    await db.customStatement(
      'INSERT OR REPLACE INTO $table ($cols) VALUES ($marks)',
      map.values.toList(),
    );
  }
}
