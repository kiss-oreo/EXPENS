import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xpenc/features/data_export/export_format.dart';
import 'package:xpenc/features/data_export/xlsx_writer.dart';

void main() {
  final rows = [
    ExportRow(
      date: DateTime(2026, 10, 12, 14, 30),
      type: 'Expense',
      amountPaise: 25050,
      account: 'HDFC',
      category: 'Food',
      subcategory: 'Delivery',
      merchant: 'Swiggy',
      paymentMethod: 'UPI',
      referenceNo: '123456789012',
      note: 'dinner, extra',
      tags: 'home',
      source: 'SMS',
    ),
    ExportRow(
      date: DateTime(2026, 10, 13, 9, 0),
      type: 'Transfer',
      amountPaise: 100000,
      account: 'HDFC',
      category: 'Transfers',
      merchant: 'Self',
      source: 'MANUAL',
    ),
    ExportRow(
      date: DateTime(2026, 9, 1, 8, 0),
      type: 'Income',
      amountPaise: 5000000,
      account: 'SBI',
      category: 'Salary',
      source: 'MANUAL',
    ),
  ];

  test('CSV columns and exact paise decimals', () {
    final csv = exportCsv(rows);
    final lines = csv.trim().split('\n');
    expect(
      lines.first,
      'Date,Time,Type,Amount,Account,Category,Subcategory,Merchant,'
      'Payment Method,Reference No,Note,Tags,Source',
    );
    expect(lines[1], contains('2026-10-12,14:30,Expense,250.50,HDFC,Food'));
    expect(lines[1], contains('"dinner, extra"'));
    expect(lines[1], contains(',SMS'));
    expect(lines[2], contains(',1000.00,'));
  });

  test('filters by date, account, category and type', () {
    final filtered = rows
        .where(
          (row) => const ExportFilter(
            start: DateTime(2026, 10, 1),
            account: 'HDFC',
            type: 'Expense',
            category: 'Food',
          ).accepts(row),
        )
        .toList();
    expect(filtered, hasLength(1));
    expect(filtered.single.merchant, 'Swiggy');
  });

  test('summary excludes transfers and keeps integer paise', () {
    final totals = summaryTotals(rows);
    expect(totals.map((t) => t.category), isNot(contains('Transfers')));
    final food = totals.singleWhere((t) => t.category == 'Food');
    expect(food.amountPaise, -25050);
    expect(food.month, '2026-10');
    final salary = totals.singleWhere((t) => t.category == 'Salary');
    expect(salary.amountPaise, 5000000);
  });

  test('xlsx is a zip with both sheets and the exact amount', () {
    final bytes = buildWorkbook(summary: summaryTotals(rows), transactions: rows);
    expect(bytes[0], 0x50);
    expect(bytes[1], 0x4b);
    final text = latin1.decode(bytes, allowInvalid: true);
    expect(text, contains('sheet1.xml'));
    expect(text, contains('sheet2.xml'));
    expect(text, contains('250.50'));
    expect(text, contains('Summary'));
  });
}
