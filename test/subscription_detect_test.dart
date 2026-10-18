import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpenc/core/money.dart';
import 'package:xpenc/data/database.dart';
import 'package:xpenc/data/tables.dart';
import 'package:xpenc/features/subscriptions/subscription_detect.dart';
import 'package:xpenc/features/subscriptions/subscription_reminders.dart';

void main() {
  test('weekly, monthly and yearly patterns get a next date', () {
    final guesses = detectSubscriptions([
      _pay('Gym', 9900, DateTime(2026, 10, 1)),
      _pay('Gym', 9900, DateTime(2026, 10, 8)),
      _pay('Gym', 9900, DateTime(2026, 10, 15)),
      _pay('Netflix', 19900, DateTime(2026, 8, 12)),
      _pay('Netflix', 19900, DateTime(2026, 9, 12)),
      _pay('Netflix', 19900, DateTime(2026, 10, 12)),
      _pay('Insurance', 49900, DateTime(2024, 10, 12)),
      _pay('Insurance', 49900, DateTime(2025, 10, 12)),
      _pay('Insurance', 49900, DateTime(2026, 10, 12)),
    ]);
    expect(guesses, hasLength(3));
    final gym = guesses.singleWhere((g) => g.merchant == 'Gym');
    expect(gym.interval, SubscriptionInterval.weekly);
    expect(gym.nextDate, DateTime(2026, 10, 22));
    final netflix = guesses.singleWhere((g) => g.merchant == 'Netflix');
    expect(netflix.interval, SubscriptionInterval.monthly);
    expect(netflix.nextDate, DateTime(2026, 11, 12));
    final insurance = guesses.singleWhere((g) => g.merchant == 'Insurance');
    expect(insurance.interval, SubscriptionInterval.yearly);
    expect(insurance.nextDate, DateTime(2027, 10, 12));
  });

  test('two payments, irregular gaps, and dissimilar amounts are ignored', () {
    expect(
      detectSubscriptions([
        _pay('Gym', 9900, DateTime(2026, 10, 1)),
        _pay('Gym', 9900, DateTime(2026, 10, 8)),
      ]),
      isEmpty,
    );
    expect(
      detectSubscriptions([
        _pay('Cafe', 5000, DateTime(2026, 10, 1)),
        _pay('Cafe', 5000, DateTime(2026, 10, 3)),
        _pay('Cafe', 5000, DateTime(2026, 10, 20)),
      ]),
      isEmpty,
    );
    expect(
      detectSubscriptions([
        _pay('Shop', 10000, DateTime(2026, 8, 12)),
        _pay('Shop', 10000, DateTime(2026, 9, 12)),
        _pay('Shop', 50000, DateTime(2026, 10, 12)),
      ]),
      isEmpty,
    );
  });

  test('reminders are planned only, and detection does not insert', () async {
    final guesses = detectSubscriptions([
      _pay('Netflix', 19900, DateTime(2026, 8, 12)),
      _pay('Netflix', 19900, DateTime(2026, 9, 12)),
      _pay('Netflix', 19900, DateTime(2026, 10, 12)),
    ]);
    final planned = planSubscriptionReminders(
      guesses,
      today: DateTime(2026, 11, 10),
    );
    expect(planned, hasLength(1));
    expect(planned.single.body, contains('Nothing was added'));
    expect(planned.single.body, contains('12 Nov 2026'));
    expect(
      planSubscriptionReminders(
        guesses,
        today: DateTime(2026, 11, 10),
        alreadySent: {planned.single.key},
      ),
      isEmpty,
    );
    expect(
      planSubscriptionReminders(guesses, today: DateTime(2026, 12, 1)),
      isEmpty,
    );

    final temp = Directory.systemTemp.createTempSync('expens_sub_');
    final db = AppDatabase(NativeDatabase(File('${temp.path}/ledger.sqlite')));
    addTearDown(() async {
      await db.close();
      temp.deleteSync(recursive: true);
    });
    final cash = (await db.watchAccounts().first).single.id;
    final other = await db.addAccount(
      name: 'Savings',
      type: AccountType.bank,
      colorValue: 0xFF1565C0,
      iconKey: 'bank',
      openingBalance: const Money.zero(),
    );
    for (final date in [
      DateTime(2026, 8, 12),
      DateTime(2026, 9, 12),
      DateTime(2026, 10, 12),
    ]) {
      await db.addTransaction(
        type: TxType.expense,
        amount: const Money(19900),
        accountId: cash,
        date: date,
        payee: 'Netflix',
      );
    }
    await db.addTransaction(
      type: TxType.transfer,
      amount: const Money(19900),
      accountId: cash,
      toAccountId: other,
      date: DateTime(2026, 11, 12),
      payee: 'Netflix',
    );
    final before = (await db.select(db.transactions).get()).length;
    final loaded = await loadSubscriptionPayments(db);
    expect(loaded, hasLength(3));
    expect(detectSubscriptions(loaded), hasLength(1));
    expect((await db.select(db.transactions).get()).length, before);
  });
}

SubscriptionPayment _pay(String payee, int paise, DateTime date) {
  return SubscriptionPayment(payee: payee, amountPaise: paise, date: date);
}
