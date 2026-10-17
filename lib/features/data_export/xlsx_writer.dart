import 'dart:convert';
import 'dart:typed_data';

import '../message_capture/parser/sms/sms_models.dart';
import 'export_format.dart';

/// A minimal uncompressed .xlsx (OOXML zip). No extra packages — the lockfile
/// stays untouched, and amounts are written as exact decimal strings.
Uint8List buildWorkbook({
  required List<CategoryMonthTotal> summary,
  required List<ExportRow> transactions,
}) {
  final files = <String, List<int>>{
    '[Content_Types].xml': utf8.encode(_contentTypes),
    '_rels/.rels': utf8.encode(_rootRels),
    'xl/workbook.xml': utf8.encode(_workbook),
    'xl/_rels/workbook.xml.rels': utf8.encode(_workbookRels),
    'xl/worksheets/sheet1.xml': utf8.encode(_summarySheet(summary)),
    'xl/worksheets/sheet2.xml': utf8.encode(_transactionsSheet(transactions)),
  };
  return _zipStored(files);
}

const _contentTypes = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>
''';

const _rootRels = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
''';

const _workbook = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="Summary" sheetId="1" r:id="rId1"/>
    <sheet name="Transactions" sheetId="2" r:id="rId2"/>
  </sheets>
</workbook>
''';

const _workbookRels = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
</Relationships>
''';

String _summarySheet(List<CategoryMonthTotal> rows) {
  final byCategory = <String, int>{};
  final byMonth = <String, int>{};
  for (final row in rows) {
    byCategory[row.category] = (byCategory[row.category] ?? 0) + row.amountPaise;
    byMonth[row.month] = (byMonth[row.month] ?? 0) + row.amountPaise;
  }
  final cells = <List<String>>[
    ['Totals by category', 'Amount'],
    for (final entry in byCategory.entries)
      [entry.key, formatPaise(entry.value)],
    [],
    ['Totals by month', 'Amount'],
    for (final entry in byMonth.entries) [entry.key, formatPaise(entry.value)],
    [],
    ['Month', 'Category', 'Amount'],
    for (final row in rows)
      [row.month, row.category, formatPaise(row.amountPaise)],
  ];
  return _sheet(cells);
}

String _transactionsSheet(List<ExportRow> rows) {
  final cells = <List<String>>[
    exportCsvHeader,
    for (final row in rows)
      [
        _d(row.date),
        _t(row.date),
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
      ],
  ];
  return _sheet(cells);
}

String _d(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _t(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _sheet(List<List<String>> rows) {
  final b = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>',
  );
  for (var r = 0; r < rows.length; r++) {
    b.write('<row r="${r + 1}">');
    for (var c = 0; c < rows[r].length; c++) {
      final ref = '${_col(c)}${r + 1}';
      b.write(
        '<c r="$ref" t="inlineStr"><is><t>${_xml(rows[r][c])}</t></is></c>',
      );
    }
    b.write('</row>');
  }
  b.write('</sheetData></worksheet>');
  return b.toString();
}

String _col(int index) {
  var n = index;
  final chars = <String>[];
  do {
    chars.add(String.fromCharCode(65 + (n % 26)));
    n = n ~/ 26 - 1;
  } while (n >= 0);
  return chars.reversed.join();
}

String _xml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// ZIP with method 0 (stored). Excel accepts it; we avoid a compression lib.
Uint8List _zipStored(Map<String, List<int>> files) {
  final local = BytesBuilder();
  final central = BytesBuilder();
  var offset = 0;
  for (final entry in files.entries) {
    final name = utf8.encode(entry.key);
    final data = entry.value;
    final crc = _crc32(data);
    local.add(_u32(0x04034b50));
    local.add(_u16(20));
    local.add(_u16(0));
    local.add(_u16(0));
    local.add(_u16(0));
    local.add(_u16(0));
    local.add(_u32(crc));
    local.add(_u32(data.length));
    local.add(_u32(data.length));
    local.add(_u16(name.length));
    local.add(_u16(0));
    local.add(name);
    local.add(data);

    central.add(_u32(0x02014b50));
    central.add(_u16(20));
    central.add(_u16(20));
    central.add(_u16(0));
    central.add(_u16(0));
    central.add(_u16(0));
    central.add(_u16(0));
    central.add(_u32(crc));
    central.add(_u32(data.length));
    central.add(_u32(data.length));
    central.add(_u16(name.length));
    central.add(_u16(0));
    central.add(_u16(0));
    central.add(_u16(0));
    central.add(_u16(0));
    central.add(_u32(0));
    central.add(_u32(offset));
    central.add(name);
    offset += 30 + name.length + data.length;
  }
  final centralBytes = central.toBytes();
  final end = BytesBuilder()
    ..add(_u32(0x06054b50))
    ..add(_u16(0))
    ..add(_u16(0))
    ..add(_u16(files.length))
    ..add(_u16(files.length))
    ..add(_u32(centralBytes.length))
    ..add(_u32(offset))
    ..add(_u16(0));
  return Uint8List.fromList([
    ...local.toBytes(),
    ...centralBytes,
    ...end.toBytes(),
  ]);
}

List<int> _u16(int v) => [v & 0xff, (v >> 8) & 0xff];
List<int> _u32(int v) => [
  v & 0xff,
  (v >> 8) & 0xff,
  (v >> 16) & 0xff,
  (v >> 24) & 0xff,
];

int _crc32(List<int> data) {
  var crc = 0xffffffff;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      final mask = -(crc & 1);
      crc = (crc >> 1) ^ (0xedb88320 & mask);
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
