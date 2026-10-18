import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xpenc/features/message_capture/parser/sms/sms_capture_parser.dart';
import 'package:xpenc/features/message_capture/parser/sms/sms_models.dart';
import 'package:xpenc/features/message_capture/parser/sms/sms_samples.dart';
import 'package:xpenc/features/statement_import/pdf_text.dart';
import 'package:xpenc/features/statement_import/statement_parser.dart';

/// Permanent check for the redacted files the user places in `samples/real/`.
///
/// This test must not be skipped and must not be fed invented statements.
/// If the directory is missing, the formats were not run.
void main() {
  const statements = StatementParser();
  const sms = SmsCaptureParser();

  test('redacted files in samples/real parse', () {
    final dir = Directory('samples/real');
    expect(
      dir.existsSync(),
      isTrue,
      reason:
          'samples/real is not in the workspace. Google Pay PDF, PhonePe PDF, '
          'and bank SMS formats were not run.',
    );
    final files = dir
        .listSync()
        .whereType<File>()
        .where((file) => !file.path.endsWith('.gitkeep'))
        .toList();
    expect(
      files,
      isNotEmpty,
      reason:
          'samples/real has no files. Google Pay PDF, PhonePe PDF, and bank '
          'SMS formats were not run.',
    );

    final failures = <String>[];
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      final lower = name.toLowerCase();
      try {
        if (lower.endsWith('.pdf')) {
          final text = PdfText.extract(file.readAsBytesSync());
          final parsed = statements.parse(text);
          if (parsed.rows.isEmpty) {
            failures.add('$name: PDF parser returned no settled rows');
          }
        } else if (lower.endsWith('.txt')) {
          final text = file.readAsStringSync();
          if (text.contains('\n===' ) || text.startsWith('===')) {
            final samples = parseSmsSamples(text);
            if (samples.isEmpty) {
              failures.add('$name: SMS sample file has no blocks');
              continue;
            }
            for (final sample in samples) {
              final outcome = sms.parse(
                body: sample.body,
                sender: sample.sender,
                receivedAt: DateTime(2026, 10, 12, 14, 30),
              );
              final parsed = outcome is SmsParsedMessage
                  ? outcome.value
                  : null;
              final ok = switch (sample.expect) {
                'ignore' => outcome is SmsIgnored,
                'debit' => parsed?.direction == SmsDirection.debit,
                'credit' => parsed?.direction == SmsDirection.credit,
                _ => parsed != null,
              };
              if (!ok) failures.add('$name ${sample.id}: $outcome');
            }
          } else {
            final parsed = statements.parse(text);
            final smsRows = _parseLooseSms(text, sms);
            if (parsed.rows.isEmpty && smsRows == 0) {
              failures.add(
                '$name: neither the statement parser nor the bank SMS parser '
                'produced a row',
              );
            }
          }
        } else {
          failures.add('$name: unsupported file type');
        }
      } catch (e) {
        failures.add('$name: $e');
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}

int _parseLooseSms(String text, SmsCaptureParser parser) {
  final blocks = text.split(RegExp(r'\n\s*\n'));
  var parsed = 0;
  for (final block in blocks) {
    final lines = block
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .toList();
    if (lines.length < 2) continue;
    final outcome = parser.parse(
      sender: lines.first,
      body: lines.skip(1).join('\n'),
      receivedAt: DateTime(2026, 10, 12, 14, 30),
    );
    if (outcome is SmsParsedMessage) parsed++;
  }
  return parsed;
}
