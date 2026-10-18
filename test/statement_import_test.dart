import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpenc/core/money.dart';
import 'package:xpenc/data/database.dart';
import 'package:xpenc/data/tables.dart';
import 'package:xpenc/features/merchants/merchant_store.dart';
import 'package:xpenc/features/statement_import/statement_import.dart';
import 'package:xpenc/features/statement_import/statement_parser.dart';

void main() {
  late Directory temp;
  late AppDatabase db;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('expens_stmt_');
    db = AppDatabase(NativeDatabase(File('${temp.path}/ledger.sqlite')));
  });

  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  test('dedupes by reference, then amount date payee, and does not double insert', () async {
    final cash = (await db.watchAccounts().first).single.id;
    final food = await db.addCategory(
      name: 'Food',
      kind: CategoryKind.expense,
      colorValue: 0xFF000000,
      iconKey: 'food',
    );
    final store = MerchantStore(db);
    final swiggy = await store.upsertFromRaw('Swiggy');
    await store.setDefaultCategory(swiggy, food);
    await store.addAlias(swiggy, 'Swiggy Instamart');

    final smsId = await db.addTransaction(
      type: TxType.expense,
      amount: const Money(25050),
      accountId: cash,
      date: DateTime(2026, 10, 12, 14, 30),
      payee: 'Swiggy',
    );
    await store.setTxExtra(
      transactionId: smsId,
      bankReference: '123456789012',
      source: 'SMS',
      needsReview: true,
    );
    final manualId = await db.addTransaction(
      type: TxType.expense,
      amount: const Money(3300),
      accountId: cash,
      date: DateTime(2026, 10, 14, 8),
      payee: 'DMART',
    );

    final service = StatementImportService(db);
    final choices = await service.preview([
      StatementRow(
        app: StatementApp.gpay,
        date: DateTime(2026, 10, 12, 14, 30),
        amountPaise: 25050,
        direction: StatementDirection.debit,
        merchant: 'Swiggy Instamart',
        reference: '123456789012',
      ),
      StatementRow(
        app: StatementApp.gpay,
        date: DateTime(2026, 10, 14, 20, 15),
        amountPaise: 3300,
        direction: StatementDirection.debit,
        merchant: 'Dmart',
        reference: '888888888888',
      ),
      StatementRow(
        app: StatementApp.phonepe,
        date: DateTime(2026, 10, 16, 9),
        amountPaise: 8000,
        direction: StatementDirection.debit,
        merchant: 'Metro',
        reference: '777777777777',
      ),
    ]);
    expect(choices[0].existingId, smsId);
    expect(choices[1].existingId, manualId);
    expect(choices[2].existingId, isNull);

    final result = await service.save(choices);
    expect(result.inserted, 1);
    expect(result.merged, 2);
    final rows = await db.select(db.transactions).get();
    expect(rows, hasLength(3));

    final sms = rows.singleWhere((row) => row.id == smsId);
    expect(sms.payee, 'Swiggy');
    expect(sms.categoryId, food);
    final smsExtra = await db.customSelect(
      'SELECT source FROM tx_extras WHERE transaction_id = ?',
      variables: [Variable.withInt(smsId)],
    ).getSingle();
    expect(smsExtra.read<String>('source'), 'SMS');

    final manualExtra = await db.customSelect(
      'SELECT bank_reference, source FROM tx_extras WHERE transaction_id = ?',
      variables: [Variable.withInt(manualId)],
    ).getSingle();
    expect(manualExtra.read<String>('bank_reference'), '888888888888');
    expect(manualExtra.read<String>('source'), 'MANUAL');

    final imported = rows.singleWhere((row) => row.payee == 'Metro');
    expect(imported.amount.paise, 8000);
    final importedExtra = await db.customSelect(
      'SELECT source, bank_reference FROM tx_extras WHERE transaction_id = ?',
      variables: [Variable.withInt(imported.id)],
    ).getSingle();
    expect(importedExtra.read<String>('source'), 'IMPORT_PDF');
    expect(importedExtra.read<String>('bank_reference'), '777777777777');
  });

  test('a match fills empty fields and never overwrites user-set ones', () async {
    final cash = (await db.watchAccounts().first).single;
    final hdfc = await db.addAccount(
      name: 'HDFC',
      type: AccountType.bank,
      colorValue: 0xFF1A237E,
      iconKey: 'bank',
      openingBalance: const Money(0),
      last4: '1234',
    );
    final food = await db.addCategory(
      name: 'Food',
      kind: CategoryKind.expense,
      colorValue: 0xFF000000,
      iconKey: 'food',
    );
    final travel = await db.addCategory(
      name: 'Travel',
      kind: CategoryKind.expense,
      colorValue: 0xFF0000FF,
      iconKey: 'travel',
    );
    final home = await db.addTag(name: 'home', colorValue: 0xFF006600);
    final store = MerchantStore(db);
    final irctc = await store.upsertFromRaw('IRCTC');
    await store.setDefaultCategory(irctc, travel);
    final cafe = await store.upsertFromRaw('Cafe');
    await store.setDefaultCategory(cafe, food);

    final setId = await db.addTransaction(
      type: TxType.expense,
      amount: const Money(25050),
      accountId: cash.id,
      categoryId: food,
      date: DateTime(2026, 10, 12, 14, 30),
      payee: 'Swiggy',
      note: 'my note',
    );
    await db.setTransactionTags(setId, {home});
    await store.setTxExtra(
      transactionId: setId,
      bankReference: '123456789012',
      source: 'MANUAL',
    );

    final emptyId = await db.addTransaction(
      type: TxType.expense,
      amount: const Money(4000),
      accountId: cash.id,
      date: DateTime(2026, 10, 2, 9),
    );
    await store.setTxExtra(
      transactionId: emptyId,
      bankReference: '999999999999',
      source: 'SMS',
      needsReview: true,
    );

    final service = StatementImportService(db);
    final result = await service.save(
      await service.preview([
        StatementRow(
          app: StatementApp.gpay,
          date: DateTime(2026, 10, 12, 14, 30),
          amountPaise: 25050,
          direction: StatementDirection.debit,
          merchant: 'IRCTC',
          reference: '123456789012',
          accountLast4: '1234',
        ),
        StatementRow(
          app: StatementApp.phonepe,
          date: DateTime(2026, 10, 2, 9),
          amountPaise: 4000,
          direction: StatementDirection.debit,
          merchant: 'Cafe',
          reference: '999999999999',
          accountLast4: '1234',
        ),
      ]),
    );
    expect(result.inserted, 0);
    expect(result.merged, 2);

    final kept = await (db.select(db.transactions)
          ..where((t) => t.id.equals(setId)))
        .getSingle();
    expect(kept.accountId, cash.id);
    expect(kept.accountId, isNot(hdfc));
    expect(kept.categoryId, food);
    expect(kept.payee, 'Swiggy');
    expect(kept.note, 'my note');
    expect(await db.tagIdsForTransaction(setId), [home]);

    final filled = await (db.select(db.transactions)
          ..where((t) => t.id.equals(emptyId)))
        .getSingle();
    expect(filled.accountId, cash.id);
    expect(filled.payee, 'Cafe');
    expect(filled.note, 'PhonePe');
    expect(filled.categoryId, food);
    expect(await db.tagIdsForTransaction(emptyId), isEmpty);
  });
}
