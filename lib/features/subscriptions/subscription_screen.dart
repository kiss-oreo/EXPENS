import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/widgets/app_surfaces.dart';
import '../../core/widgets/nav_bar_inset.dart';
import '../../data/providers.dart';
import '../../data/tables.dart';
import 'subscription_detect.dart';

final subscriptionsProvider = StreamProvider<List<SubscriptionGuess>>((ref) {
  final db = ref.watch(dbProvider);
  return db.watchTransactions().asyncMap((rows) async {
    return detectSubscriptions([
      for (final row in rows)
        if (row.type == TxType.expense && (row.payee ?? '').trim().isNotEmpty)
          SubscriptionPayment(
            payee: row.payee!,
            amountPaise: row.amount.paise,
            date: row.date,
          ),
    ]);
  });
});

/// Reminders only. Opening this screen never creates a transaction.
class SubscriptionsScreen extends ConsumerWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final guesses = ref.watch(subscriptionsProvider);
    return Scaffold(
      appBar: AppTopBar(title: const Text('Subscriptions')),
      body: guesses.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (rows) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32).plusNavBar(
              context,
            ),
            children: [
              Text(
                'A merchant with three similar payments on a weekly, monthly, '
                'or yearly gap is listed here with the next expected date. '
                'This is a reminder only. Nothing is added to your ledger.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              if (rows.isEmpty)
                const Text('No regular payments yet.')
              else
                for (final guess in rows) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${guess.merchant} · ${MoneyFormat.symbol(Money(guess.amountPaise))}',
                    ),
                    subtitle: Text(
                      '${guess.interval.name} · next ${DateFormat('d MMM yyyy').format(guess.nextDate)}',
                    ),
                  ),
                  const Divider(height: 1),
                ],
            ],
          );
        },
      ),
    );
  }
}
