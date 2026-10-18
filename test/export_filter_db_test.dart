import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpenc/core/money.dart';
import 'package:xpenc/data/database.dart';
import 'package:xpenc/data/tables.dart';
import 'package:xpenc/features/data_export/export_format.dart';
import 'package:xpenc/features/data_export/export_rows.dart';
import 'package:xpenc/features/data_export/period_statement_pdf.dart';
import 'package:xpenc/features/data_export/xlsx_writer.dart';

void main() {
  test('CSV and XLSX use the same date, account, category, and type filter', () async {
    final temp = Directory.systemTemp.createTempSync('expens_export_');
    final db = AppDatabase(NativeDatabase(File('${temp.path}/ledger.sqlite')));
    addTearDown(() async {
      await db.close();
      temp.deleteSync(recursive: true);
    });

    final cash = (await db.watchAccounts().first).single.id;
    final hdfc = await db.addAccount(
      name: 'HDFC',
      type: AccountType.bank,
      colorValue: 0xFF1A237E,
      iconKey: 'bank',
      openingBalance: const Money(0),
    );
    final food = await db.addCategory(
      name: 'Food',
      kind: CategoryKind.expense,
      colorValue: 0xFF000000,
      iconKey: 'food',
    );
    final delivery = await db.addCategory(
      name: 'Delivery',
      kind: CategoryKind.expense,
      colorValue: 0xFF111111,
      iconKey: 'food',
      parentId: food,
    );
    final tag = await db.addTag(name: 'home', colorValue: 0xFF006600);
    final kept = await db.addTransaction(
      type: TxType.expense,
      amount: const Money(25050),
      accountId: hdfc,
      categoryId: delivery,
      date: DateTime(2026, 10, 12, 14, 30),
      payee: 'Swiggy',
      note: 'dinner',
    );
    await db.setTransactionTags(kept, {tag});
    await db.addTransaction(
      type: TxType.income,
      amount: const Money(5000000),
      accountId: cash,
      date: DateTime(2026, 9, 1),
      payee: 'Employer',
    );

    final filter = ExportFilter(
      start: DateTime(2026, 10, 1),
      endInclusive: DateTime(2026, 10, 31),
      account: 'HDFC',
      category: 'Food',
      type: 'Expense',
    );
    final rows = await loadExportRows(db, filter: filter);
    expect(rows, hasLength(1));
    expect(rows.single.merchant, 'Swiggy');
    expect(rows.single.subcategory, 'Delivery');
    expect(rows.single.tags, 'home');
    expect(rows.single.amountPaise, 25050);

    final csv = exportCsv(rows);
    expect(csv, contains('Swiggy'));
    expect(csv, contains('Delivery'));
    expect(csv, contains('home'));
    expect(csv, isNot(contains('Employer')));

    final xlsx = String.fromCharCodes(buildWorkbook(
      summary: summaryTotals(rows),
      transactions: rows,
    ));
    expect(xlsx, contains('Swiggy'));
    expect(xlsx, isNot(contains('Employer')));

    final pdf = await buildPeriodStatementPdf(
      start: DateTime(2026, 10, 1),
      end: DateTime(2026, 10, 31),
      rows: rows,
      subtitle: filter.describe(),
    );
    expect(pdf.length, greaterThan(100));

    final range = filter.displayRange(rows, DateTime(2026, 11, 1));
    expect(range.start, DateTime(2026, 10, 1));
    expect(range.end, DateTime(2026, 10, 31));
    expect(filter.describe(), 'Account: HDFC · Category: Food · Type: Expense');

    final open = const ExportFilter(account: 'HDFC').displayRange(
      rows,
      DateTime(2026, 11, 1),
    );
    expect(open.start, DateTime(2026, 10, 12, 14, 30));
    expect(open.end.month, 10);
  });
}
