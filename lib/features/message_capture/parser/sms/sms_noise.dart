import 'sms_models.dart';

/// Messages that must never become a ledger row. A false reject costs one
/// manual entry. A false accept invents money.
class SmsNoise {
  const SmsNoise._();

  static final _otp = RegExp(
    r'\b(otp|one[\s-]?time[\s-]?password|verification code|do not share|'
    r'one time password)\b',
    caseSensitive: false,
  );

  static final _declined = RegExp(
    r'\b(declined|failed|unsuccessful|not processed|could not be processed|'
    r'rejected|reversal failed)\b',
    caseSensitive: false,
  );

  static final _mandate = RegExp(
    r'\b(e-?mandate|mandate (?:created|registered|set up|setup)|'
    r'autopay (?:registration|setup|set up)|'
    r'standing instruction (?:has been )?(?:set|registered)|'
    r'registered for autopay|upi pin set|collect request|'
    r'has requested (?:rs|inr|₹))\b',
    caseSensitive: false,
  );

  static final _promotional = RegExp(
    r'\b(pre-?approved|click here|t&c apply|unsubscribe|loan offer|'
    r'cashback offer|apply now|congratulations|limited period)\b',
    caseSensitive: false,
  );

  static final _balanceOnly = RegExp(
    r'\b(balance is|bal is|available balance|a/?c bal)\b',
    caseSensitive: false,
  );

  /// Null when the body might still be a real transaction.
  static SmsIgnoreReason? reject(String body, {required bool hasDirection}) {
    if (_otp.hasMatch(body)) return SmsIgnoreReason.otp;
    if (_mandate.hasMatch(body)) return SmsIgnoreReason.mandate;
    if (_declined.hasMatch(body)) return SmsIgnoreReason.declined;
    if (_promotional.hasMatch(body)) return SmsIgnoreReason.promotional;
    if (!hasDirection && _balanceOnly.hasMatch(body)) {
      return SmsIgnoreReason.balanceOnly;
    }
    return null;
  }
}

/// Sender-ID checks. A phone number, or a short code with no known bank
/// header, is treated as spoofed and dropped.
class SmsSenderGuard {
  const SmsSenderGuard._();

  static String normalize(String sender) =>
      sender.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

  static bool looksLikeBankSender(String sender) {
    final s = normalize(sender);
    if (s.isEmpty) return false;
    if (RegExp(r'^\+?\d{6,}$').hasMatch(s)) return false;
    return RegExp(r'^[A-Z]{2}-[A-Z0-9]{4,10}(?:-[A-Z])?$').hasMatch(s) ||
        RegExp(r'^[A-Z]{4,12}$').hasMatch(s);
  }

  static bool containsHeader(String sender, String header) =>
      normalize(sender).contains(header.toUpperCase());
}
