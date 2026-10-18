import '../merchants/merchant_names.dart';

enum SubscriptionInterval { weekly, monthly, yearly }

class SubscriptionPayment {
  const SubscriptionPayment({
    required this.payee,
    required this.amountPaise,
    required this.date,
  });

  final String payee;
  final int amountPaise;
  final DateTime date;
}

class SubscriptionGuess {
  const SubscriptionGuess({
    required this.merchant,
    required this.amountPaise,
    required this.interval,
    required this.lastDate,
    required this.nextDate,
    required this.count,
  });

  final String merchant;
  final int amountPaise;
  final SubscriptionInterval interval;
  final DateTime lastDate;
  final DateTime nextDate;
  final int count;
}

class PlannedReminder {
  const PlannedReminder({
    required this.key,
    required this.id,
    required this.title,
    required this.body,
  });

  final String key;
  final int id;
  final String title;
  final String body;
}

/// Three or more similar expenses, on a roughly regular weekly, monthly, or
/// yearly gap. This only returns guesses. It does not create transactions.
List<SubscriptionGuess> detectSubscriptions(
  List<SubscriptionPayment> payments,
) {
  final groups = <String, List<SubscriptionPayment>>{};
  for (final payment in payments) {
    final key = MerchantNames.normalize(payment.payee);
    if (key.isEmpty || payment.amountPaise <= 0) continue;
    groups.putIfAbsent(key, () => []).add(payment);
  }
  final out = <SubscriptionGuess>[];
  for (final group in groups.values) {
    final guess = _one(group);
    if (guess != null) out.add(guess);
  }
  out.sort((a, b) => a.nextDate.compareTo(b.nextDate));
  return out;
}

SubscriptionGuess? _one(List<SubscriptionPayment> payments) {
  if (payments.length < 3) return null;
  final amounts = [for (final p in payments) p.amountPaise];
  if (!_similar(amounts)) return null;
  final dates = [for (final p in payments) _day(p.date)]..sort();
  final unique = <DateTime>[];
  for (final date in dates) {
    if (unique.isEmpty || unique.last != date) unique.add(date);
  }
  if (unique.length < 3) return null;
  final gaps = <int>[
    for (var i = 1; i < unique.length; i++)
      unique[i].difference(unique[i - 1]).inDays,
  ];
  final gap = _median(gaps);
  final interval = _interval(gap);
  if (interval == null) return null;
  final tolerance = switch (interval) {
    SubscriptionInterval.weekly => 2,
    SubscriptionInterval.monthly => 4,
    SubscriptionInterval.yearly => 15,
  };
  if (gaps.any((g) => (g - gap).abs() > tolerance)) return null;
  final last = unique.last;
  final latest = payments.reduce((a, b) => a.date.isAfter(b.date) ? a : b);
  return SubscriptionGuess(
    merchant: latest.payee.trim(),
    amountPaise: _median(amounts),
    interval: interval,
    lastDate: last,
    nextDate: _add(last, interval),
    count: payments.length,
  );
}

bool _similar(List<int> amounts) {
  final sorted = [...amounts]..sort();
  final med = sorted[sorted.length ~/ 2];
  final percent = (med * 10) ~/ 100;
  final tolerance = percent > 100 ? percent : 100;
  return sorted.last - sorted.first <= tolerance;
}

SubscriptionInterval? _interval(int medianGap) {
  if (medianGap >= 6 && medianGap <= 8) return SubscriptionInterval.weekly;
  if (medianGap >= 26 && medianGap <= 35) return SubscriptionInterval.monthly;
  if (medianGap >= 350 && medianGap <= 380) return SubscriptionInterval.yearly;
  return null;
}

int _median(List<int> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime _add(DateTime date, SubscriptionInterval interval) {
  return switch (interval) {
    SubscriptionInterval.weekly => date.add(const Duration(days: 7)),
    SubscriptionInterval.monthly => _addMonths(date, 1),
    SubscriptionInterval.yearly => _addMonths(date, 12),
  };
}

DateTime _addMonths(DateTime date, int months) {
  final total = date.month - 1 + months;
  final year = date.year + total ~/ 12;
  final month = total % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  final day = date.day > lastDay ? lastDay : date.day;
  return DateTime(year, month, day);
}

/// Reminders due today or within the next three days. Already-sent keys are
/// skipped. This list is the only thing a reminder may post — no ledger row.
List<PlannedReminder> planSubscriptionReminders(
  List<SubscriptionGuess> guesses, {
  required DateTime today,
  Set<String> alreadySent = const {},
}) {
  final day = _day(today);
  final out = <PlannedReminder>[];
  for (final guess in guesses) {
    final next = _day(guess.nextDate);
    final days = next.difference(day).inDays;
    if (days < 0 || days > 3) continue;
    final key =
        'sub_reminded:${MerchantNames.normalize(guess.merchant)}:${_iso(next)}';
    if (alreadySent.contains(key)) continue;
    out.add(
      PlannedReminder(
        key: key,
        id: 930000 + (_hash(key) % 5000),
        title: 'Expected payment',
        body:
            '${guess.merchant} is expected around ${_label(next)}. '
            'This is a reminder only. Nothing was added.',
      ),
    );
  }
  return out;
}

String _iso(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _label(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

int _hash(String key) {
  var hash = 0;
  for (final unit in key.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return hash;
}
