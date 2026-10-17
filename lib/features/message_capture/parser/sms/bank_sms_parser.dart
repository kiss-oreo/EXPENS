import 'sms_fields.dart';
import 'sms_models.dart';

/// One bank's SMS dialect. New banks are a new subclass plus one line in
/// [kBankParsers] — nothing else has to change.
abstract class BankSmsParser {
  const BankSmsParser();

  String get id;
  String get bankName;

  /// Substrings that appear in that bank's DLT sender ID (`HDFCBK`, `SBIUPI`).
  List<String> get senderHeaders;

  List<RegExp> get merchantPatterns => const [];
  List<RegExp> get referencePatterns => const [];

  bool claims(String sender) {
    final s = sender.toUpperCase();
    for (final header in senderHeaders) {
      if (s.contains(header.toUpperCase())) return true;
    }
    return false;
  }

  /// Never throws. Unknown wording becomes an ignore, not a crash.
  SmsParseOutcome parse(String body, DateTime receivedAt) {
    try {
      final direction = smsDirectionOf(body);
      if (direction == null) {
        if (RegExp(r'bal', caseSensitive: false).hasMatch(body)) {
          return const SmsIgnored(SmsIgnoreReason.balanceOnly);
        }
        return const SmsIgnored(SmsIgnoreReason.noDirection);
      }
      final parsed = SmsFields.extract(
        body: body,
        receivedAt: receivedAt,
        bankName: bankName,
        direction: direction,
        merchantPatterns: merchantPatterns,
        referencePatterns: referencePatterns,
      );
      if (parsed == null) return const SmsIgnored(SmsIgnoreReason.noAmount);
      return SmsParsedMessage(parsed);
    } catch (_) {
      return const SmsIgnored(SmsIgnoreReason.malformed);
    }
  }
}
