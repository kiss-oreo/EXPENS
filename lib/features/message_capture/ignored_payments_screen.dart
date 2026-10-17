import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/app_surfaces.dart';
import '../../core/widgets/nav_bar_inset.dart';
import '../../data/providers.dart';
import '../merchants/merchant_store.dart';
import 'parser/sms/sms_models.dart';
import 'sms_ingest.dart';

final ignoredPaymentsProvider = FutureProvider<List<IgnoredPaymentRecord>>((
  ref,
) {
  return MerchantStore(ref.watch(dbProvider)).ignored();
});

/// Payments the parser dropped. Restore rebuilds a transaction from the
/// fields that were kept — it does not re-read an inbox.
class IgnoredPaymentsScreen extends ConsumerWidget {
  const IgnoredPaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ignored = ref.watch(ignoredPaymentsProvider);
    return Scaffold(
      appBar: AppTopBar(title: const Text('Removed payments')),
      body: ignored.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(child: Text('Nothing ignored.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              20,
              8,
              20,
              32,
            ).plusNavBar(context),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _Tile(row: rows[i]),
          );
        },
      ),
    );
  }
}

class _Tile extends ConsumerWidget {
  const _Tile({required this.row});

  final IgnoredPaymentRecord row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final amount = row.amountPaise == null
        ? 'No amount kept'
        : 'Rs ${formatPaise(row.amountPaise!)}';
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(amount, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              [
                row.reason,
                row.merchant,
                row.summary,
              ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (!row.restored && row.amountPaise != null) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => _restore(context, ref, row.id),
                child: const Text('Restore'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref, int id) async {
    final db = ref.read(dbProvider);
    final created = await SmsIngestService().restoreIgnored(db, id);
    ref.invalidate(ignoredPaymentsProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          created == null
              ? 'Could not restore that payment.'
              : 'Restored. It is marked for review.',
        ),
      ),
    );
  }
}
