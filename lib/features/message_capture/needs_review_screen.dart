import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/widgets/app_surfaces.dart';
import '../../core/widgets/nav_bar_inset.dart';
import '../../data/providers.dart';
import 'needs_review.dart';

final needsReviewProvider = StreamProvider<List<ReviewItem>>((ref) {
  final db = ref.watch(dbProvider);
  return db.watchTransactions().asyncMap((_) => loadNeedsReview(db));
});

/// Unassigned or uncategorised SMS payments, and anything flagged for review.
class NeedsReviewScreen extends ConsumerWidget {
  const NeedsReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(needsReviewProvider);
    return Scaffold(
      appBar: AppTopBar(title: const Text('Needs review')),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nothing to review. Unassigned or uncategorised SMS payments show up here.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32).plusNavBar(
              context,
            ),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = rows[index];
              final who = (item.payee == null || item.payee!.trim().isEmpty)
                  ? 'Unknown'
                  : item.payee!;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '$who · ${MoneyFormat.symbol(Money(item.amountPaise))}',
                ),
                subtitle: Text(
                  '${DateFormat('d MMM yyyy').format(item.date)} · ${item.reasonLabel}',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/add?id=${item.id}'),
              );
            },
          );
        },
      ),
    );
  }
}
