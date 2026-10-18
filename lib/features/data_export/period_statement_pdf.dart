import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/branding/app_info.dart';
import '../message_capture/parser/sms/sms_models.dart';
import 'export_format.dart';

/// A period statement: income, expense, and a category summary.
/// Transfers are listed but do not change the category totals.
Future<Uint8List> buildPeriodStatementPdf({
  required DateTime start,
  required DateTime end,
  required List<ExportRow> rows,
  String subtitle = '',
}) async {
  final doc = pw.Document(title: '${AppInfo.name} statement');
  final income = rows
      .where((r) => r.type == 'Income')
      .fold<int>(0, (s, r) => s + r.amountPaise);
  final expense = rows
      .where((r) => r.type == 'Expense')
      .fold<int>(0, (s, r) => s + r.amountPaise);
  final byCategory = <String, int>{};
  for (final row in rows.where((r) => r.type == 'Expense')) {
    final name = row.category.isEmpty ? 'Uncategorised' : row.category;
    byCategory[name] = (byCategory[name] ?? 0) + row.amountPaise;
  }
  final categories = byCategory.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      footer: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Text(
          '${AppInfo.name}  |  on-device statement  |  page ${context.pageNumber}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ),
      build: (context) => [
        pw.Text(
          '${AppInfo.name} statement',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          '${_d(start)} to ${_d(end)}',
          style: const pw.TextStyle(fontSize: 11),
        ),
        if (subtitle.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(subtitle, style: const pw.TextStyle(fontSize: 11)),
        ],
        pw.SizedBox(height: 12),
        pw.Text('Income  ${formatPaise(income)}'),
        pw.Text('Expense  ${formatPaise(expense)}'),
        pw.Text('Net  ${formatPaise(income - expense)}'),
        pw.SizedBox(height: 14),
        pw.Text(
          'Category summary',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        if (categories.isEmpty)
          pw.Text('No expenses in this period.')
        else
          pw.TableHelper.fromTextArray(
            headers: const ['Category', 'Amount'],
            data: [
              for (final entry in categories)
                [entry.key, formatPaise(entry.value)],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 9),
          ),
        pw.SizedBox(height: 14),
        pw.Text(
          'Transactions',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        if (rows.isEmpty)
          pw.Text('No transactions in this period.')
        else
          pw.TableHelper.fromTextArray(
            headers: const ['Date', 'Type', 'Amount', 'Account', 'Category', 'Merchant'],
            data: [
              for (final row in rows)
                [
                  _d(row.date),
                  row.type,
                  formatPaise(row.amountPaise),
                  row.account,
                  row.subcategory.isEmpty
                      ? row.category
                      : '${row.category} / ${row.subcategory}',
                  row.merchant,
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
            cellStyle: const pw.TextStyle(fontSize: 8),
          ),
      ],
    ),
  );
  return doc.save();
}

String _d(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
