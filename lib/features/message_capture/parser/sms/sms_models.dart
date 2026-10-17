/// Pure SMS-parse models. No Flutter, no Android, no database.
///
/// Money is integer paise. Callers format with integer division, never
/// `double`.

enum SmsDirection { debit, credit }

enum SmsIgnoreReason {
  otp,
  promotional,
  balanceOnly,
  declined,
  mandate,
  spoofed,
  unknownBank,
  disabledBank,
  noAmount,
  noDirection,
  malformed,
}

/// A transaction lifted from one incoming SMS. [timestamp] is the bank's
/// stated time when the body has one, otherwise the receive time.
class SmsParsed {
  const SmsParsed({
    required this.amountPaise,
    required this.direction,
    required this.timestamp,
    required this.bankName,
    required this.confidence,
    this.accountLast4,
    this.merchant,
    this.reference,
    this.balancePaise,
    this.paymentMethod,
  });

  final int amountPaise;
  final SmsDirection direction;
  final String? accountLast4;
  final String? merchant;
  final String? reference;
  final int? balancePaise;
  final DateTime timestamp;
  final String bankName;

  /// `UPI`, `CARD`, `CASH`, or `NETBANKING`. Null when the body doesn't say.
  final String? paymentMethod;

  /// 0–100. Informational — capture does not auto-post from this alone.
  final int confidence;
}

sealed class SmsParseOutcome {
  const SmsParseOutcome();
}

class SmsParsedMessage extends SmsParseOutcome {
  const SmsParsedMessage(this.value);
  final SmsParsed value;
}

class SmsIgnored extends SmsParseOutcome {
  const SmsIgnored(this.reason);
  final SmsIgnoreReason reason;
}

/// `Rs X spent at Y. Tap to edit` — the capture notification body.
String captureNotificationBody({
  required int amountPaise,
  required bool spent,
  String? merchant,
}) {
  final who = (merchant == null || merchant.trim().isEmpty)
      ? 'unknown'
      : merchant.trim();
  final verb = spent ? 'spent at' : 'received from';
  return 'Rs ${formatPaise(amountPaise)} $verb $who. Tap to edit';
}

/// Exact decimal rupees from integer paise. Never uses floating point.
String formatPaise(int paise) {
  final sign = paise < 0 ? '-' : '';
  final abs = paise.abs();
  final rupees = abs ~/ 100;
  final frac = (abs % 100).toString().padLeft(2, '0');
  return '$sign$rupees.$frac';
}

/// Inverse of [formatPaise] for a string like `1,234.50` or `12.5`.
/// Returns null when the text is not a plain decimal amount.
int? paiseFromDecimal(String raw) {
  final cleaned = raw.replaceAll(',', '').trim();
  if (cleaned.isEmpty) return null;
  final negative = cleaned.startsWith('-');
  final body = negative ? cleaned.substring(1) : cleaned;
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(body)) return null;
  final parts = body.split('.');
  final rupees = int.tryParse(parts[0]);
  if (rupees == null) return null;
  var frac = 0;
  if (parts.length == 2) {
    final f = parts[1];
    frac = f.length == 1 ? int.parse(f) * 10 : int.parse(f);
  }
  final paise = rupees * 100 + frac;
  return negative ? -paise : paise;
}
