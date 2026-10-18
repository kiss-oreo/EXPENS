import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xpenc/features/statement_import/statement_parser.dart';

void main() {
  const parser = StatementParser();

  test('gpay sample keeps completed rows and skips failed or pending', () {
    final text = File('samples/gpay_statement.txt').readAsStringSync();
    final parsed = parser.parse(text);
    expect(parsed.app, StatementApp.gpay);
    expect(parsed.skipped, 2);
    expect(parsed.rows, hasLength(3));
    expect(parsed.rows[0].amountPaise, 25050);
    expect(parsed.rows[0].direction, StatementDirection.debit);
    expect(parsed.rows[0].merchant, 'Swiggy');
    expect(parsed.rows[0].reference, '123456789012');
    expect(parsed.rows[0].accountLast4, '1234');
    expect(parsed.rows[0].date, DateTime(2026, 10, 12, 14, 30));
    expect(parsed.rows[1].amountPaise, 150000);
    expect(parsed.rows[1].direction, StatementDirection.credit);
    expect(parsed.rows[1].merchant, 'Rahul');
    expect(parsed.rows[2].amountPaise, 3300);
    expect(parsed.rows[2].merchant, 'Dmart');
    expect(
      parsed.rows.map((row) => row.merchant),
      isNot(contains('Metro')),
    );
    expect(parsed.rows.map((row) => row.merchant), isNot(contains('Cafe')));
  });

  test('phonepe sample uses the UTR, not the app transaction id', () {
    final text = File('samples/phonepe_statement.txt').readAsStringSync();
    final parsed = parser.parse(text);
    expect(parsed.app, StatementApp.phonepe);
    expect(parsed.skipped, 2);
    expect(parsed.rows, hasLength(3));
    expect(parsed.rows[0].reference, '123456789012');
    expect(parsed.rows[0].date, DateTime(2025, 4, 2, 14, 30));
    expect(parsed.rows[0].amountPaise, 25050);
    expect(parsed.rows[1].direction, StatementDirection.credit);
    expect(parsed.rows[1].amountPaise, 150000);
    expect(parsed.rows[2].merchant, 'Postoffice');
    expect(parsed.rows[2].amountPaise, 1500);
    expect(parsed.rows[2].accountLast4, '5555');
  });

  test('a rupee sign and a flattened pipe line still parse as integer paise', () {
    const text = '''
Google Pay
12 Oct 2026 | 14:30 | Paid to Swiggy | 123456789012 | -250.50 | Completed
12 Oct 2026 Paid to Cafe ₹40.00
Pending
''';
    final parsed = parser.parse(text);
    expect(parsed.rows, hasLength(1));
    expect(parsed.rows.single.amountPaise, 25050);
    expect(parsed.rows.single.direction, StatementDirection.debit);
    expect(parsed.rows.single.merchant, 'Swiggy');
    expect(parsed.skipped, 1);
  });

  test('unknown text returns no rows and does not throw', () {
    expect(parser.parse('hello').rows, isEmpty);
    expect(parser.parse('').rows, isEmpty);
  });
}
