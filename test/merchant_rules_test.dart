import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpenc/core/money.dart';
import 'package:xpenc/data/database.dart';
import 'package:xpenc/data/tables.dart';
import 'package:xpenc/features/merchants/merchant_names.dart';
import 'package:xpenc/features/merchants/merchant_store.dart';

void main() {
  test('aliases and VPA local-parts are the same merchant', () {
    expect(MerchantNames.sameMerchant('SWIGGY', 'swiggy@okaxis'), isTrue);
    expect(MerchantNames.sameMerchant('Swiggy*Order', 'swiggy'), isTrue);
    expect(MerchantNames.canonical('swiggy@okaxis'), 'Swiggy');
    expect(
      MerchantNames.categoryFor('SWIGGY*ORDER', [
        (name: 'Zomato', categoryId: 1, enabled: true),
        (name: 'swiggy@okaxis', categoryId: 9, enabled: false),
        (name: 'Swiggy', categoryId: 4, enabled: true),
      ]),
      4,
    );
    expect(
      MerchantNames.categoryFor('Unknown', [
        (name: 'Swiggy', categoryId: 4, enabled: true),
      ]),
      isNull,
    );
  });

  test('a saved rule categorises later payments from that merchant', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final food = (await db.watchCategories(CategoryKind.expense).first)
        .firstWhere((c) => c.name == 'Food')
        .id;
    final store = MerchantStore(db);
    await store.upsertFromRaw('swiggy@okaxis', categoryId: food);
    expect(await store.categoryForMerchant('SWIGGY*ORDER'), food);

    final cash = (await db.watchAccounts().first).single.id;
    await db.addTransaction(
      type: TxType.expense,
      amount: const Money(19900),
      accountId: cash,
      date: DateTime(2026, 10, 1),
      payee: 'Swiggy',
    );
    final updated = await store.applyCategoryToAll(
      payee: 'Swiggy',
      categoryId: food,
    );
    expect(updated, 1);
    final row = (await db.watchTransactions().first).single;
    expect(row.categoryId, food);
  });

  test('setting a category on one payment can be limited to that row', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final food = (await db.watchCategories(CategoryKind.expense).first)
        .firstWhere((c) => c.name == 'Food')
        .id;
    final cash = (await db.watchAccounts().first).single.id;
    final id = await db.addTransaction(
      type: TxType.expense,
      amount: const Money(5000),
      accountId: cash,
      date: DateTime(2026, 10, 4),
      payee: 'Cafe',
    );
    await db.addTransaction(
      type: TxType.expense,
      amount: const Money(7000),
      accountId: cash,
      date: DateTime(2026, 10, 5),
      payee: 'Cafe',
    );
    await MerchantStore(db).setTransactionCategory(
      transactionId: id,
      categoryId: food,
      payee: 'Cafe',
    );
    final rows = await db.watchTransactions().first;
    expect(rows.singleWhere((t) => t.id == id).categoryId, food);
    expect(rows.where((t) => t.categoryId == food), hasLength(1));
  });
}
