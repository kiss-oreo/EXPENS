import 'package:flutter_test/flutter_test.dart';
import 'package:xpenc/features/message_capture/parser/sms/sms_dedupe.dart';
import 'package:xpenc/features/message_capture/parser/sms/sms_models.dart';

void main() {
  test('paise format is an exact decimal, never a rounded float', () {
    expect(formatPaise(25050), '250.50');
    expect(formatPaise(1), '0.01');
    expect(formatPaise(10), '0.10');
    expect(formatPaise(-125), '-1.25');
    expect(paiseFromDecimal('1,234.50'), 123450);
    expect(paiseFromDecimal('12.5'), 1250);
    expect(paiseFromDecimal('nope'), isNull);
  });

  test('UTR is the dedupe key', () {
    final a = SmsDedupe.key(
      reference: 'abc123456',
      amountPaise: 100,
      accountLast4: '1234',
      receivedAt: DateTime(2026, 1, 1, 1, 2, 3),
      payee: 'Shop',
    );
    final b = SmsDedupe.key(
      reference: 'ABC123456',
      amountPaise: 999,
      accountLast4: '9999',
      receivedAt: DateTime(2026, 2, 2),
      payee: 'Other',
    );
    expect(a, b);
    expect(a, 'ref:ABC123456');
  });

  test('without a reference, amount account minute and payee match', () {
    final at = DateTime(2026, 10, 12, 14, 30, 45);
    final a = SmsDedupe.key(
      amountPaise: 25050,
      accountLast4: '1234',
      receivedAt: at,
      payee: 'Swiggy',
    );
    final b = SmsDedupe.key(
      amountPaise: 25050,
      accountLast4: '1234',
      receivedAt: at.add(const Duration(seconds: 10)),
      payee: 'swiggy',
    );
    final otherMinute = SmsDedupe.key(
      amountPaise: 25050,
      accountLast4: '1234',
      receivedAt: at.add(const Duration(minutes: 1)),
      payee: 'Swiggy',
    );
    expect(a, b);
    expect(a, isNot(otherMinute));
  });

  test('capture notification names the amount and the merchant', () {
    expect(
      captureNotificationBody(
        amountPaise: 25050,
        spent: true,
        merchant: 'Swiggy',
      ),
      'Rs 250.50 spent at Swiggy. Tap to edit',
    );
  });
}
