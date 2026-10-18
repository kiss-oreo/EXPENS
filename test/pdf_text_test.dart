import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xpenc/features/statement_import/pdf_text.dart';
import 'package:xpenc/features/statement_import/statement_parser.dart';

void main() {
  const parser = StatementParser();

  test('flate sample PDFs round-trip into the same completed rows', () {
    for (final name in ['gpay_statement', 'phonepe_statement']) {
      final text = File('samples/$name.txt').readAsStringSync();
      final pdf = File('samples/$name.pdf').readAsBytesSync();
      final extracted = PdfText.extract(pdf);
      expect(extracted, contains('Paid to'), reason: name);
      final fromPdf = parser.parse(extracted);
      final fromText = parser.parse(text);
      expect(fromPdf.rows.length, fromText.rows.length, reason: name);
      for (var i = 0; i < fromText.rows.length; i++) {
        expect(fromPdf.rows[i].amountPaise, fromText.rows[i].amountPaise);
        expect(fromPdf.rows[i].merchant, fromText.rows[i].merchant);
        expect(fromPdf.rows[i].reference, fromText.rows[i].reference);
        expect(fromPdf.rows[i].direction, fromText.rows[i].direction);
      }
    }
  });

  test('words placed on one line are joined, and a bad file does not throw', () {
    final pdf = _pdf('''
BT
/F1 11 Tf
40 700 Td
(Paid to) Tj
80 0 Td
(Swiggy) Tj
0 -16 Td
(14:30) Tj
ET
''');
    final text = PdfText.extract(pdf);
    expect(text, contains('Paid to Swiggy'));
    expect(text, contains('14:30'));
    expect(PdfText.extract(Uint8List.fromList(utf8.encode('not a pdf'))), '');
    expect(PdfText.extract(Uint8List(0)), '');
  });

  test('a hex string is read', () {
    final text = PdfText.extract(_pdf('BT\n40 700 Td\n<48656C6C6F> Tj\nET\n'));
    expect(text, contains('Hello'));
  });
}

Uint8List _pdf(String content) {
  final stream = latin1.encode(content);
  final objects = <List<int>>[
    latin1.encode('<< /Type /Catalog /Pages 2 0 R >>'),
    latin1.encode('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
    latin1.encode(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
      '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
    ),
    latin1.encode('<< /Length ${stream.length} >>\nstream\n') +
        stream +
        latin1.encode('\nendstream'),
    latin1.encode('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'),
  ];
  final out = BytesBuilder();
  out.add(latin1.encode('%PDF-1.4\n'));
  final offsets = <int>[0];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.add(latin1.encode('${i + 1} 0 obj\n'));
    out.add(objects[i]);
    out.add(latin1.encode('\nendobj\n'));
  }
  final xref = out.length;
  final xrefBuf = StringBuffer('xref\n0 ${objects.length + 1}\n');
  xrefBuf.write('0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    xrefBuf.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  xrefBuf.write(
    'trailer << /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  out.add(latin1.encode(xrefBuf.toString()));
  return out.toBytes();
}
