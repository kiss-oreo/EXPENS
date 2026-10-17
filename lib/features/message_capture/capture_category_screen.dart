import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/app_surfaces.dart';
import '../../core/widgets/nav_bar_inset.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../data/tables.dart';
import '../merchants/merchant_store.dart';
import 'parser/sms/sms_models.dart';

/// The notification "Category" action. Sets the category on the captured
/// payment, and can save it as a rule for that merchant.
class CaptureCategoryScreen extends ConsumerStatefulWidget {
  const CaptureCategoryScreen({required this.transactionId, super.key});

  final int transactionId;

  @override
  ConsumerState<CaptureCategoryScreen> createState() =>
      _CaptureCategoryScreenState();
}

class _CaptureCategoryScreenState extends ConsumerState<CaptureCategoryScreen> {
  bool _applyAll = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tx = ref.watch(_txProvider(widget.transactionId));
    return Scaffold(
      appBar: AppTopBar(title: const Text('Category')),
      body: tx.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (row) {
          if (row == null) {
            return const Center(child: Text('That payment is gone.'));
          }
          if (!row.type.isIncomeOrExpense) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Transfers have no category. They never affect budgets.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () =>
                          context.push('/add?id=${widget.transactionId}'),
                      child: const Text('Open transaction'),
                    ),
                  ],
                ),
              ),
            );
          }
          final kind = row.type == TxType.income
              ? CategoryKind.income
              : CategoryKind.expense;
          final categories =
              ref.watch(categoriesProvider(kind)).valueOrNull ?? const [];
          final amount = 'Rs ${formatPaise(row.amount.paise)}';
          final who = (row.payee == null || row.payee!.trim().isEmpty)
              ? 'unknown'
              : row.payee!.trim();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32).plusNavBar(
              context,
            ),
            children: [
              Text(amount, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                row.type == TxType.income
                    ? 'Received from $who'
                    : 'Spent at $who',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (row.payee != null && row.payee!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Apply to all from this merchant'),
                  subtitle: const Text('Also saves it as a rule'),
                  value: _applyAll,
                  onChanged: _busy
                      ? null
                      : (on) => setState(() => _applyAll = on),
                ),
              ],
              const SizedBox(height: 8),
              if (categories.isEmpty)
                const Text('Add a category first, from More → Categories.')
              else
                for (final category in _ordered(categories))
                  ListTile(
                    contentPadding: EdgeInsets.only(
                      left: category.parentId == null ? 0 : 16,
                    ),
                    leading: KeyIcon(
                      category.iconKey,
                      color: Color(category.colorValue),
                    ),
                    title: Text(category.name),
                    enabled: !_busy,
                    onTap: () => _save(row, category.id),
                  ),
            ],
          );
        },
      ),
    );
  }

  List<CategoryRow> _ordered(List<CategoryRow> rows) {
    final parents = rows.where((c) => c.parentId == null).toList();
    final children = <int, List<CategoryRow>>{};
    for (final row in rows) {
      final parentId = row.parentId;
      if (parentId != null) {
        children.putIfAbsent(parentId, () => []).add(row);
      }
    }
    return [
      for (final parent in parents) ...[
        parent,
        ...children[parent.id] ?? const <CategoryRow>[],
      ],
    ];
  }

  Future<void> _save(TransactionRow row, int categoryId) async {
    setState(() => _busy = true);
    try {
      await MerchantStore(ref.read(dbProvider)).setTransactionCategory(
        transactionId: row.id,
        categoryId: categoryId,
        payee: row.payee,
        applyToAll: _applyAll,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the category: $e')),
      );
    }
  }
}

final _txProvider = FutureProvider.family<TransactionRow?, int>((ref, id) {
  return ref.watch(dbProvider).transactionById(id);
});
