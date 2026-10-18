/// On-device statement parser for the layouts in `/samples`.
///
/// No Flutter, no Android, no file access. Money is integer paise.
/// Unknown text returns no rows. It never throws.
enum StatementApp { gpay, phonepe }

enum StatementDirection { debit, credit }

class StatementRow {
  const StatementRow({
    required this.app,
    required this.date,
    required this.amountPaise,
    required this.direction,
    required this.merchant,
    this.reference,
    this.accountLast4,
  });

  final StatementApp? app;
  final DateTime date;
  final int amountPaise;
  final StatementDirection direction;
  final String merchant;
  final String? reference;
  final String? accountLast4;
}

class StatementParseResult {
  const StatementParseResult({
    required this.app,
    required this.rows,
    required this.skipped,
  });

  final StatementApp? app;
  final List<StatementRow> rows;

  /// Failed, pending, or incomplete rows that were not returned.
  final int skipped;
}

class StatementParser {
  const StatementParser();

  StatementParseResult parse(String text) {
    try {
      return _parse(text);
    } catch (_) {
      return const StatementParseResult(app: null, rows: [], skipped: 0);
    }
  }

  StatementParseResult _parse(String text) {
    final app = _appOf(text);
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .toList();
    final blocks = <List<String>>[];
    List<String>? current;
    for (final line in lines) {
      if (_startsPayment(line)) {
        if (current != null) blocks.add(current);
        current = [line];
      } else if (current != null) {
        current.add(line);
      }
    }
    if (current != null) blocks.add(current);

    final rows = <StatementRow>[];
    var skipped = 0;
    for (final block in blocks) {
      final row = _row(block, app);
      if (row == null) {
        skipped++;
      } else {
        rows.add(row);
      }
    }
    return StatementParseResult(app: app, rows: rows, skipped: skipped);
  }

  StatementApp? _appOf(String text) {
    final lower = text.toLowerCase();
    final phonePe = lower.contains('phonepe');
    final gpay = lower.contains('google pay') || lower.contains('gpay');
    if (phonePe && !gpay) return StatementApp.phonepe;
    if (gpay && !phonePe) return StatementApp.gpay;
    if (phonePe && gpay) {
      return lower.indexOf('phonepe') < lower.indexOf('google pay') &&
              lower.indexOf('phonepe') < lower.indexOf('gpay')
          ? StatementApp.phonepe
          : StatementApp.gpay;
    }
    return null;
  }

  bool _startsPayment(String line) {
    if (_dateAt(line) == null) return false;
    if (RegExp(r'\d{4}\s+to\s+', caseSensitive: false).hasMatch(line) &&
        !RegExp(
          r'paid to|received from|\bdebit\b|\bcredit\b',
          caseSensitive: false,
        ).hasMatch(line)) {
      return false;
    }
    return RegExp(
      r'(?:₹|rs\.?|inr)|paid to|received from|\bdebit\b|\bcredit\b|\|',
      caseSensitive: false,
    ).hasMatch(line);
  }

  StatementRow? _row(List<String> block, StatementApp? app) {
    final joined = block.join('\n');
    if (_badStatus(joined)) return null;
    final date = _dateAt(block.first);
    if (date == null) return null;
    final amount = _amount(block.first) ?? _amount(joined);
    if (amount == null || amount <= 0) return null;
    final direction = _direction(block.first) ?? _direction(joined);
    if (direction == null) return null;
    final merchant = _merchant(block.first);
    if (merchant.isEmpty) return null;
    return StatementRow(
      app: app,
      date: _withTime(date, joined),
      amountPaise: amount,
      direction: direction,
      merchant: merchant,
      reference: _reference(joined),
      accountLast4: _last4(joined),
    );
  }

  bool _badStatus(String text) {
    return RegExp(
      r'\b(failed|pending|declined|processing|unsuccessful|cancelled|canceled)\b',
      caseSensitive: false,
    ).hasMatch(text);
  }

  DateTime? _dateAt(String line) {
    final dayMonth = RegExp(
      r'^(\d{1,2})\s+([A-Za-z]{3,})[a-z]*\s+(\d{4})\b',
    ).firstMatch(line);
    if (dayMonth != null) {
      return _date(
        int.parse(dayMonth.group(1)!),
        dayMonth.group(2)!,
        int.parse(dayMonth.group(3)!),
      );
    }
    final monthDay = RegExp(
      r'^([A-Za-z]{3,})[a-z]*\s+(\d{1,2}),?\s+(\d{4})\b',
    ).firstMatch(line);
    if (monthDay != null) {
      return _date(
        int.parse(monthDay.group(2)!),
        monthDay.group(1)!,
        int.parse(monthDay.group(3)!),
      );
    }
    final numeric = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})\b')
        .firstMatch(line);
    if (numeric != null) {
      final year = int.parse(numeric.group(3)!);
      return DateTime(
        year < 100 ? 2000 + year : year,
        int.parse(numeric.group(2)!),
        int.parse(numeric.group(1)!),
      );
    }
    return null;
  }

  DateTime? _date(int day, String monthName, int year) {
    const months = {
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
    final month = months[monthName.toLowerCase().substring(0, 3)];
    if (month == null || day < 1 || day > 31) return null;
    return DateTime(year, month, day);
  }

  DateTime _withTime(DateTime date, String text) {
    final match = RegExp(
      r'\b(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([AP]M)?\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return date;
    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final second = int.tryParse(match.group(3) ?? '') ?? 0;
    final ampm = match.group(4)?.toUpperCase();
    if (ampm == 'PM' && hour < 12) hour += 12;
    if (ampm == 'AM' && hour == 12) hour = 0;
    if (hour > 23 || minute > 59) return date;
    return DateTime(date.year, date.month, date.day, hour, minute, second);
  }

  int? _amount(String text) {
    final signed = RegExp(
      r'(?:^|\|)\s*([+-])\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*(?:\||$)',
    ).firstMatch(text);
    if (signed != null) {
      return _paise(signed.group(2)!);
    }
    final currency = RegExp(
      r'(?:₹|rs\.?|inr)\s*([0-9]{1,3}(?:,[0-9]{2,3})*(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)',
      caseSensitive: false,
    ).firstMatch(text);
    if (currency == null) return null;
    return _paise(currency.group(1)!);
  }

  /// Integer paise. `1,500.00` is 150000. One decimal digit is a tenth of a rupee.
  int? _paise(String raw) {
    final cleaned = raw.replaceAll(',', '').trim();
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(cleaned)) return null;
    final parts = cleaned.split('.');
    final rupees = int.tryParse(parts[0]);
    if (rupees == null) return null;
    var frac = 0;
    if (parts.length == 2) {
      final f = parts[1];
      frac = f.length == 1 ? int.parse(f) * 10 : int.parse(f);
    }
    return rupees * 100 + frac;
  }

  StatementDirection? _direction(String text) {
    final lower = text.toLowerCase();
    if (RegExp(r'\bcredit\b|received from|received in').hasMatch(lower)) {
      return StatementDirection.credit;
    }
    if (RegExp(r'\bdebit\b|paid to|paid from').hasMatch(lower)) {
      return StatementDirection.debit;
    }
    final signed = RegExp(r'(?:^|\|)\s*([+-])\s*[0-9]').firstMatch(text);
    if (signed == null) return null;
    return signed.group(1) == '-'
        ? StatementDirection.debit
        : StatementDirection.credit;
  }

  String _merchant(String line) {
    final named = RegExp(
      r'(?:paid to|received from)\s+(.+)',
      caseSensitive: false,
    ).firstMatch(line);
    var raw = named?.group(1) ?? '';
    if (raw.isEmpty && line.contains('|')) {
      final parts = line.split('|').map((p) => p.trim()).toList();
      if (parts.length >= 3) raw = parts[2];
    }
    raw = raw.replaceAll(
      RegExp(r'\b(debit|credit)\b.*', caseSensitive: false),
      '',
    );
    raw = raw.replaceAll(
      RegExp(
        r'(?:₹|rs\.?|inr)\s*[0-9][0-9,]*(?:\.[0-9]{1,2})?',
        caseSensitive: false,
      ),
      '',
    );
    raw = raw.replaceAll(RegExp(r'[|+].*'), '');
    return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String? _reference(String text) {
    final utr = RegExp(
      r'\bUTR(?:\s*No\.?)?\s*[:.#-]?\s*([A-Za-z0-9]{6,40})',
      caseSensitive: false,
    ).firstMatch(text);
    if (utr != null) return utr.group(1);
    final upi = RegExp(
      r'\bUPI(?:\s*Transaction)?\s*(?:ID|Ref(?:erence)?)\s*[:.#-]?\s*([A-Za-z0-9]{6,40})',
      caseSensitive: false,
    ).firstMatch(text);
    if (upi != null) return upi.group(1);
    final txn = RegExp(
      r'\bTransaction\s*ID\s*[:.#-]?\s*([A-Za-z0-9]{6,40})',
      caseSensitive: false,
    ).firstMatch(text);
    return txn?.group(1);
  }

  String? _last4(String text) {
    final masked = RegExp(r'(?:XX|\*{2,}|X{2,}|•{2,})(\d{4})\b').firstMatch(text);
    if (masked != null) return masked.group(1);
    final paidBy = RegExp(
      r'Paid by\s+\D*(\d{4})\b',
      caseSensitive: false,
    ).firstMatch(text);
    return paidBy?.group(1);
  }
}
