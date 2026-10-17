import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xpenc/features/message_capture/parser/sms/sms_capture_parser.dart';
import 'package:xpenc/features/message_capture/parser/sms/sms_models.dart';
import 'package:xpenc/features/message_capture/parser/sms/sms_samples.dart';

void main() {
  const parser = SmsCaptureParser();
  final received = DateTime(2026, 10, 12, 14, 30);

  test('every sample in samples/sms_samples.txt parses as labelled', () {
    final text = File('samples/sms_samples.txt').readAsStringSync();
    final samples = parseSmsSamples(text);
    expect(samples.length, greaterThanOrEqualTo(12));

    final banks = samples
        .map((s) => s.id.split('-').first)
        .where((id) => id != 'spoofed')
        .toSet();
    expect(
      banks,
      containsAll([
        'hdfc',
        'sbi',
        'icici',
        'axis',
        'kotak',
        'pnb',
        'bob',
        'canara',
        'union',
        'idfc',
        'yes',
        'ippb',
      ]),
    );

    for (final sample in samples) {
      final outcome = parser.parse(
        body: sample.body,
        sender: sample.sender,
        receivedAt: received,
      );
      if (sample.expect == 'ignore') {
        expect(outcome, isA<SmsIgnored>(), reason: sample.id);
        expect((outcome as SmsIgnored).reason, sample.reason, reason: sample.id);
        continue;
      }
      expect(outcome, isA<SmsParsedMessage>(), reason: sample.id);
      final parsed = (outcome as SmsParsedMessage).value;
      expect(
        parsed.direction.name,
        sample.expect,
        reason: sample.id,
      );
      expect(parsed.amountPaise, sample.amountPaise, reason: sample.id);
      expect(parsed.accountLast4, sample.account, reason: sample.id);
      if (sample.merchantContains != null) {
        expect(
          parsed.merchant,
          contains(sample.merchantContains),
          reason: sample.id,
        );
      }
      if (sample.reference != null) {
        expect(parsed.reference, sample.reference, reason: sample.id);
      }
      if (sample.balancePaise != null) {
        expect(parsed.balancePaise, sample.balancePaise, reason: sample.id);
      }
      if (sample.paymentMethod != null) {
        expect(parsed.paymentMethod, sample.paymentMethod, reason: sample.id);
      }
    }
  });

  test('an unknown body never throws', () {
    expect(
      parser.parse(
        body: '???',
        sender: 'not a sender',
        receivedAt: received,
      ),
      isA<SmsIgnored>(),
    );
  });

  test('a disabled bank header is dropped', () {
    final outcome = parser.parse(
      body: 'Rs 10.00 debited from A/c XX1234 at Shop. UTR 123456789012.',
      sender: 'VM-HDFCBK-S',
      receivedAt: received,
      enabledHeaders: {'SBIUPI'},
    );
    expect(outcome, isA<SmsIgnored>());
    expect((outcome as SmsIgnored).reason, SmsIgnoreReason.disabledBank);
  });
}
