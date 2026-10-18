import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpenc/core/money.dart';
import 'package:xpenc/data/database.dart';
import 'package:xpenc/data/tables.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('expens_mig_'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('schema 80 side tables appear without dropping a transaction', () async {
    final file = File('${temp.path}/ledger.sqlite');
    final db = AppDatabase(NativeDatabase(file));
    final cash = (await db.watchAccounts().first).single.id;
    final id = await db.addTransaction(
      type: TxType.expense,
      amount: const Money(5000),
      accountId: cash,
      date: DateTime(2026, 10, 2),
      note: 'kept',
    );
    await db.customStatement('PRAGMA user_version = 79');
    await db.close();

    final reopened = AppDatabase(NativeDatabase(file));
    final rows = await reopened.select(reopened.transactions).get();
    expect(rows.single.id, id);
    expect(rows.single.note, 'kept');
    final merchants = await reopened
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'merchants'",
        )
        .get();
    expect(merchants, isNotEmpty);
    await reopened.close();
  });

  test('schema 80 reopens to 81 without dropping a transaction', () async {
    final file = File('${temp.path}/ledger81.sqlite');
    final db = AppDatabase(NativeDatabase(file));
    final cash = (await db.watchAccounts().first).single.id;
    final id = await db.addTransaction(
      type: TxType.expense,
      amount: const Money(2500),
      accountId: cash,
      date: DateTime(2026, 10, 3),
      note: 'kept-81',
    );
    await db.customStatement('PRAGMA user_version = 80');
    await db.close();

    final reopened = AppDatabase(NativeDatabase(file));
    final version = await reopened.customSelect('PRAGMA user_version').get();
    expect(version.single.read<int>('user_version'), 81);
    final rows = await reopened.select(reopened.transactions).get();
    expect(rows.single.id, id);
    expect(rows.single.note, 'kept-81');
    final extras = await reopened
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'tx_extras'",
        )
        .get();
    expect(extras, isNotEmpty);
    await reopened.close();
  });

  test('net worth is the sum of balance-holding accounts', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final bank = await db.addAccount(
      name: 'HDFC',
      type: AccountType.bank,
      colorValue: 0xFF1565C0,
      iconKey: 'bank',
      openingBalance: const Money(100000),
      last4: '1234',
    );
    await db.addAccount(
      name: 'HDFC debit',
      type: AccountType.card,
      cardKind: CardKind.debit,
      linkedAccountId: bank,
      colorValue: 0xFF1565C0,
      iconKey: 'card',
      openingBalance: const Money(999999),
      last4: '9999',
    );
    await db.addAccount(
      name: 'Card',
      type: AccountType.card,
      cardKind: CardKind.credit,
      colorValue: 0xFF6A1B9A,
      iconKey: 'card',
      openingBalance: const Money(-20000),
    );
    final holding = await db.watchBalanceHoldingAccounts().first;
    final sum = holding
        .where((a) => a.includeInNetWorth)
        .fold<Money>(const Money.zero(), (s, a) => s + a.currentBalance);
    expect(await db.watchNetWorth().first, sum);
    expect(sum, const Money(80000));
    expect(holding.map((a) => a.name), isNot(contains('HDFC debit')));
  });

  test('a transfer does not change that sum', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final cash = (await db.watchAccounts().first).single.id;
    final bank = await db.addAccount(
      name: 'SBI',
      type: AccountType.bank,
      colorValue: 0xFF2E7D32,
      iconKey: 'bank',
      openingBalance: const Money(50000),
    );
    final before = await db.watchNetWorth().first;
    await db.addTransaction(
      type: TxType.transfer,
      amount: const Money(15000),
      accountId: bank,
      toAccountId: cash,
      date: DateTime(2026, 10, 3),
    );
    expect(await db.watchNetWorth().first, before);
  });

  test('JSON backup without the new keys still restores', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dump = await db.exportAll();
    expect(dump.containsKey('merchants'), isTrue);
    dump.remove('merchants');
    dump.remove('txExtras');
    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    await expectLater(other.importAll(dump), completes);
  });
}
