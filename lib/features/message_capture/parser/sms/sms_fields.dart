import 'sms_models.dart';

/// Shared field extraction used by every bank parser. Bank classes pass
/// their own merchant / reference patterns first; these are the fallback.
class SmsFields {
  const SmsFields._();

  static final _amount = RegExp(
    r'(?:rs\.?|inr|₹)\s*([0-9]{1,3}(?:,[0-9]{2,3})*(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );

  static final _balance = RegExp(
    r'(?:avl\.?\s*bal(?:ance)?|available\s*balance|a/?c\s*bal(?:ance)?|'
    r'\bbal(?:ance)?(?:\s+is)?)\s*[:\-.]?\s*(?:rs\.?|inr|₹)?\s*'
    r'([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );

  static final _account = RegExp(
    r'(?:a/?c(?:ct|count)?(?:\s*no\.?)?|card(?:\s*(?:no\.?|ending|xx))?)\s*'
    r'[xX*\d.\s]*?(\d{4})\b',
    caseSensitive: false,
  );

  static final _sharedReference = <RegExp>[
    RegExp(
      r'(?:utr|rrn|upi\s*ref(?:erence)?(?:\s*(?:no|num)\.?)?|'
      r'ref(?:erence)?(?:\s*(?:no|id|num)\.?)?|txn(?:\s*id)?)\s*[:.#-]?\s*'
      r'([A-Za-z0-9]{6,22})',
      caseSensitive: false,
    ),
  ];

  static final _sharedMerchant = <RegExp>[
    RegExp(
      r'\bVPA\s+([A-Za-z0-9._*\-]+@[A-Za-z0-9.]+)',
      caseSensitive: false,
    ),
    RegExp(r'Info:\s*UPI/([^/\n]{2,40})/', caseSensitive: false),
    RegExp(r'UPI/([^/\n]{2,40})/', caseSensitive: false),
    RegExp(r'Payee:\s*([A-Za-z0-9 &._*\-]{2,40})', caseSensitive: false),
    RegExp(
      r'\b(?:towards|at|to)\s+([A-Za-z0-9][A-Za-z0-9 &._*\-]{1,40}?)'
      r'(?:\s+on\b|\.|,|$)',
      caseSensitive: false,
    ),
  ];

  static final _date = RegExp(
    r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b',
  );

  static final _monthDate = RegExp(
    r'\b(\d{1,2})[\- ](Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)'
    r'[a-z]*[\- ](\d{2,4})\b',
    caseSensitive: false,
  );

  static final _time = RegExp(r'\b(\d{1,2}):(\d{2})(?::(\d{2}))?\b');

  static const _months = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  static SmsParsed? extract({
    required String body,
    required DateTime receivedAt,
    required String bankName,
    required SmsDirection direction,
    List<RegExp> merchantPatterns = const [],
    List<RegExp> referencePatterns = const [],
  }) {
    final balance = _balanceMatch(body);
    final amount = _amountPaise(body, skip: balance);
    if (amount == null || amount <= 0) return null;

    final hint = _first(_account, body);
    final merchant = _merchant(body, merchantPatterns);
    final reference = _reference(body, referencePatterns);
    final balancePaise = balance == null
        ? null
        : paiseFromDecimal(balance.group(1)!);

    var score = 40;
    if (hint != null) score += 20;
    if (reference != null) score += 15;
    if (merchant != null) score += 10;
    if (balancePaise != null) score += 5;
    if (score > 100) score = 100;

    return SmsParsed(
      amountPaise: amount,
      direction: direction,
      accountLast4: hint,
      merchant: merchant,
      reference: reference,
      balancePaise: balancePaise,
      timestamp: _timestamp(body, receivedAt),
      bankName: bankName,
      paymentMethod: paymentMethodOf(body),
      confidence: score,
    );
  }

  static String? paymentMethodOf(String body) {
    final b = body.toLowerCase();
    if (b.contains('upi') || b.contains('vpa') || b.contains('@')) return 'UPI';
    if (RegExp(r'\bcard\b').hasMatch(b)) return 'CARD';
    if (b.contains('neft') ||
        b.contains('imps') ||
        b.contains('rtgs') ||
        b.contains('netbanking') ||
        b.contains('net banking')) {
      return 'NETBANKING';
    }
    if (b.contains('atm') || RegExp(r'\bcash\b').hasMatch(b)) return 'CASH';
    return null;
  }

  static RegExpMatch? _balanceMatch(String body) => _balance.firstMatch(body);

  static int? _amountPaise(String body, {RegExpMatch? skip}) {
    for (final m in _amount.allMatches(body)) {
      if (skip != null && m.start >= skip.start && m.end <= skip.end) {
        continue;
      }
      // An amount that sits inside the balance phrase but the phrase's
      // captured group didn't cover the currency token.
      if (skip != null && m.start >= skip.start && m.start < skip.end) {
        continue;
      }
      final paise = paiseFromDecimal(m.group(1)!);
      if (paise != null && paise > 0) return paise;
    }
    return null;
  }

  static String? _merchant(String body, List<RegExp> extra) {
    for (final pattern in [...extra, ..._sharedMerchant]) {
      final raw = pattern.firstMatch(body)?.group(1)?.trim();
      final cleaned = _cleanName(raw);
      if (cleaned != null) return cleaned;
    }
    return null;
  }

  static String? _cleanName(String? raw) {
    if (raw == null) return null;
    var s = raw.replaceAll(RegExp(r'[.,;:]+$'), '').trim();
    if (s.length < 2 || s.length > 80) return null;
    if (RegExp(r'^\d+$').hasMatch(s)) return null;
    if (RegExp(
      r'^(your|the|a/?c|account|inr|rs)$',
      caseSensitive: false,
    ).hasMatch(s)) {
      return null;
    }
    return s;
  }

  static String? _reference(String body, List<RegExp> extra) {
    for (final pattern in [...extra, ..._sharedReference]) {
      final g = pattern.firstMatch(body)?.group(1)?.trim();
      if (g == null || g.isEmpty) continue;
      if (RegExp(r'^(no|num|id)$', caseSensitive: false).hasMatch(g)) {
        continue;
      }
      return g;
    }
    return null;
  }

  static String? _first(RegExp re, String body) {
    final g = re.firstMatch(body)?.group(1)?.trim();
    if (g == null || g.isEmpty) return null;
    return g;
  }

  static DateTime _timestamp(String body, DateTime receivedAt) {
    DateTime? date;
    final numeric = _date.firstMatch(body);
    if (numeric != null) {
      final day = int.parse(numeric.group(1)!);
      final month = int.parse(numeric.group(2)!);
      var year = int.parse(numeric.group(3)!);
      if (year < 100) year += 2000;
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        date = DateTime(year, month, day);
      }
    }
    date ??= () {
      final named = _monthDate.firstMatch(body);
      if (named == null) return null;
      final day = int.parse(named.group(1)!);
      final month = _months[named.group(2)!.substring(0, 3).toLowerCase()];
      if (month == null) return null;
      var year = int.parse(named.group(3)!);
      if (year < 100) year += 2000;
      return DateTime(year, month, day);
    }();

    final time = _time.firstMatch(body);
    if (date == null) return receivedAt;
    if (time == null) {
      return DateTime(
        date.year,
        date.month,
        date.day,
        receivedAt.hour,
        receivedAt.minute,
        receivedAt.second,
      );
    }
    final hour = int.parse(time.group(1)!);
    final minute = int.parse(time.group(2)!);
    final second = int.parse(time.group(3) ?? '0');
    if (hour > 23 || minute > 59 || second > 59) return date;
    return DateTime(date.year, date.month, date.day, hour, minute, second);
  }
}

/// Debit vs credit from the first verb. Null when the body names neither.
SmsDirection? smsDirectionOf(String body) {
  final debit = RegExp(
    r'\b(debited|debit|spent|withdrawn|withdrawal|paid|purchase|deducted|'
    r'sent to|dr)\b',
    caseSensitive: false,
  ).firstMatch(body);
  final credit = RegExp(
    r'\b(credited|credit|received|deposited|refund(?:ed)?|reversed|'
    r'added to|cr)\b',
    caseSensitive: false,
  ).firstMatch(body);
  if (debit == null && credit == null) return null;
  if (debit == null) return SmsDirection.credit;
  if (credit == null) return SmsDirection.debit;
  return debit.start < credit.start
      ? SmsDirection.debit
      : SmsDirection.credit;
}
