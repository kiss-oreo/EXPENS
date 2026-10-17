import '../message_capture/parser/sms/sms_models.dart';

/// One accountant-facing export row. Amounts stay integer paise until
/// [formatPaise] writes the exact decimal.
class ExportRow {
  const ExportRow({
    required this.date,
    required this.type,
    required this.amountPaise,
    required this.account,
    this.category = '',
    this.subcategory = '',
    this.merchant = '',
    this.paymentMethod = '',
    this.referenceNo = '',
    this.note = '',
    this.tags = '',
    this.source = 'MANUAL',
  });

  final DateTime date;
  final String type;
  final int amountPaise;
  final String account;
  final String category;
  final String subcategory;
  final String merchant;
  final String paymentMethod;
  final String referenceNo;
  final String note;
  final String tags;
  final String source;
}

class ExportFilter {
  const ExportFilter({
    this.start,
    this.endInclusive,
    this.account,
    this.category,
    this.type,
  });

  final DateTime? start;
  final DateTime? endInclusive;
  final String? account;
  final String? category;
  final String? type;

  bool accepts(ExportRow row) {
    if (start != null && row.date.isBefore(start!)) return false;
    if (endInclusive != null) {
      final end = DateTime(
        endInclusive!.year,
        endInclusive!.month,
        endInclusive!.day,
        23,
        59,
        59,
      );
      if (row.date.isAfter(end)) return false;
    }
    if (account != null && account!.isNotEmpty && row.account != account) {
      return false;
    }
    if (category != null &&
        category!.isNotEmpty &&
        row.category != category &&
        row.subcategory != category) {
      return false;
    }
    if (type != null && type!.isNotEmpty && row.type != type) return false;
    return true;
  }
}

const exportCsvHeader = [
  'Date',
  'Time',
  'Type',
  'Amount',
  'Account',
  'Category',
  'Subcategory',
  'Merchant',
  'Payment Method',
  'Reference No',
  'Note',
  'Tags',
  'Source',
];

String exportCsv(List<ExportRow> rows) {
  final b = StringBuffer('${exportCsvHeader.join(',')}\n');
  for (final row in rows) {
    b.writeln(
      [
        _date(row.date),
        _time(row.date),
        row.type,
        formatPaise(row.amountPaise),
        row.account,
        row.category,
        row.subcategory,
        row.merchant,
        row.paymentMethod,
        row.referenceNo,
        row.note,
        row.tags,
        row.source,
      ].map(_csv).join(','),
    );
  }
  return b.toString();
}

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _time(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}';

String _csv(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

class CategoryMonthTotal {
  const CategoryMonthTotal({
    required this.month,
    required this.category,
    required this.amountPaise,
  });

  final String month;
  final String category;
  final int amountPaise;
}

/// Transfers are excluded — they move money, they don't spend or earn it.
List<CategoryMonthTotal> summaryTotals(List<ExportRow> rows) {
  final totals = <String, int>{};
  for (final row in rows) {
    if (row.type == 'Transfer') continue;
    final month = row.date.toIso8601String().substring(0, 7);
    final category = row.category.isEmpty ? 'Uncategorised' : row.category;
    final signed = row.type == 'Income' ? row.amountPaise : -row.amountPaise;
    final key = '$month|$category';
    totals[key] = (totals[key] ?? 0) + signed;
  }
  final out = [
    for (final entry in totals.entries)
      CategoryMonthTotal(
        month: entry.key.split('|').first,
        category: entry.key.split('|').sublist(1).join('|'),
        amountPaise: entry.value,
      ),
  ]..sort((a, b) {
      final month = a.month.compareTo(b.month);
      if (month != 0) return month;
      return a.category.compareTo(b.category);
    });
  return out;
}

String typeLabel(String storageName) => switch (storageName) {
  'income' => 'Income',
  'expense' => 'Expense',
  'transfer' => 'Transfer',
  'personOut' => 'Lending out',
  'personIn' => 'Lending in',
  'correctionIn' || 'correctionOut' => 'Correction',
  _ => storageName,
};
