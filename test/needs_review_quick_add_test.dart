import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpenc/core/money.dart';
import 'package:xpenc/data/database.dart';
import 'package:xpenc/data/tables.dart';
import 'package:xpenc/features/add_transaction/quick_add.dart';
import 'package:xpenc/features/merchants/merchant_store.dart';
import 'package:xpenc/features/message_capture/needs_review.dart';

void main() {
  late Directory temp;
  late AppDatabase db;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('expens_review_');
    db = AppDatabase(NativeDatabase(File('${temp.path}/ledger.sqlite')));
  });

  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  test('needs review lists uncategorised SMS and unassigned rows only', () async {
    final cash = (await db.watchAccounts().first).single.id;
    final food = await db.addCategory(
      name: 'Food',
      kind: CategoryKind.expense,
      colorValue: 0xFF000000,
      iconKey: 'food',
    );
    final store = MerchantStore(db);
    final uncategorised = await db.addTransaction(
      type: TxType.expense,
      amount: const Money(1000),
      accountId: cash,
      date: DateTime(2026, 10, 2),
      payee: 'Cafe',
    );
    await store.setTxExtra(
      transactionId: uncategorised,
      source: 'SMS',
      needsReview: false,
    );
    final categorised = await db.addTransaction(
      type: TxType.expense,
      amount: const Money(2000),
      accountId: cash,
      categoryId: food,
      date: DateTime(2026, 10, 3),
      payee: 'Swiggy',
    );
    await store.setTxExtra(
      transactionId: categorised,
      source: 'SMS',
      needsReview: false,
    );
    final holding = await db.addAccount(
      name: 'Unassigned',
      type: AccountType.bank,
      colorValue: 0xFF64748B,
      iconKey: 'bank',
      openingBalance: const Money.zero(),
    );
    final unassigned = await db.addTransaction(
      type: TxType.expense,
      amount: const Money(3000),
      accountId: holding,
      categoryId: food,
      date: DateTime(2026, 10, 4),
      payee: 'Metro',
    );

    final items = await loadNeedsReview(db);
    final ids = items.map((item) => item.id).toSet();
    expect(ids, contains(uncategorised));
    expect(ids, contains(unassigned));
    expect(ids, isNot(contains(categorised)));
    expect(
      items.singleWhere((item) => item.id == uncategorised).reasons,
      contains('No category'),
    );
    expect(
      items.singleWhere((item) => item.id == unassigned).reasons,
      contains('Unassigned account'),
    );
  });

  test('quick add stores exact paise and applies a merchant rule', () async {
    expect(paiseFromExactDecimal('250.50'), 25050);
    expect(paiseFromExactDecimal('1,500'), 150000);
    expect(paiseFromExactDecimal('nope'), isNull);

    final food = await db.addCategory(
      name: 'Food',
      kind: CategoryKind.expense,
      colorValue: 0xFF000000,
      iconKey: 'food',
    );
    final store = MerchantStore(db);
    final swiggy = await store.upsertFromRaw('Swiggy');
    await store.setDefaultCategory(swiggy, food);

    final before = (await db.select(db.transactions).get()).length;
    final error = await saveQuickAdd(
      db: db,
      amountText: 'nope',
      merchant: 'Swiggy',
    );
    expect(error, isNotNull);
    expect((await db.select(db.transactions).get()).length, before);

    expect(
      await saveQuickAdd(
        db: db,
        amountText: '250.50',
        merchant: 'Swiggy',
        date: DateTime(2026, 10, 12),
      ),
      isNull,
    );
    final rows = await db.select(db.transactions).get();
    expect(rows, hasLength(before + 1));
    expect(rows.single.amount.paise, 25050);
    expect(rows.single.categoryId, food);
    final extra = await db.customSelect(
      'SELECT source, needs_review FROM tx_extras WHERE transaction_id = ?',
      variables: [Variable.withInt(rows.single.id)],
    ).getSingle();
    expect(extra.read<String>('source'), 'MANUAL');
    expect(extra.read<int>('needs_review'), 0);
  });
}
