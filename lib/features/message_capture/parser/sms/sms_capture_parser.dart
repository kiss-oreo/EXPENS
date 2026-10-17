import 'bank_sms_parser.dart';
import 'banks.dart';
import 'sms_fields.dart';
import 'sms_models.dart';
import 'sms_noise.dart';

/// Parses one incoming SMS. Fail-safe: unknown formats are dropped, never
/// thrown. Does not read an inbox and has no Android dependency.
class SmsCaptureParser {
  const SmsCaptureParser({this.banks = kBankParsers});

  final List<BankSmsParser> banks;

  /// [enabledHeaders] limits which sender headers are accepted. Null means
  /// every registered bank. An empty set accepts none.
  SmsParseOutcome parse({
    required String body,
    required String sender,
    required DateTime receivedAt,
    Set<String>? enabledHeaders,
  }) {
    try {
      if (!SmsSenderGuard.looksLikeBankSender(sender)) {
        return const SmsIgnored(SmsIgnoreReason.spoofed);
      }
      final bank = _claiming(sender);
      if (bank == null) return const SmsIgnored(SmsIgnoreReason.spoofed);
      if (enabledHeaders != null &&
          !_headerEnabled(sender, bank, enabledHeaders)) {
        return const SmsIgnored(SmsIgnoreReason.disabledBank);
      }
      final direction = smsDirectionOf(body);
      final noise = SmsNoise.reject(body, hasDirection: direction != null);
      if (noise != null) return SmsIgnored(noise);
      return bank.parse(body, receivedAt);
    } catch (_) {
      return const SmsIgnored(SmsIgnoreReason.malformed);
    }
  }

  BankSmsParser? _claiming(String sender) {
    for (final bank in banks) {
      if (bank.claims(sender)) return bank;
    }
    return null;
  }

  bool _headerEnabled(
    String sender,
    BankSmsParser bank,
    Set<String> enabledHeaders,
  ) {
    final upper = enabledHeaders.map((h) => h.toUpperCase()).toSet();
    final s = sender.toUpperCase();
    for (final header in bank.senderHeaders) {
      if (s.contains(header.toUpperCase()) && upper.contains(header.toUpperCase())) {
        return true;
      }
    }
    // A rule may store a shorter pattern the user edited (`SBI`).
    for (final header in upper) {
      if (header.length >= 3 && s.contains(header)) return true;
    }
    return false;
  }
}
