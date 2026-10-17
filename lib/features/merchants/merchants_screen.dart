import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/app_surfaces.dart';
import '../../core/widgets/nav_bar_inset.dart';
import '../../data/providers.dart';
import '../../data/tables.dart';
import 'category_pick_sheet.dart';
import 'merchant_store.dart';

final merchantsProvider = FutureProvider<List<MerchantRecord>>((ref) {
  return MerchantStore(ref.watch(dbProvider)).list();
});

final categorisationRulesProvider =
    FutureProvider<List<CategorisationRuleRecord>>((ref) {
      return MerchantStore(ref.watch(dbProvider)).rules();
    });

/// Merchants, aliases, merge, and the category rules Settings edits.
class MerchantsScreen extends ConsumerWidget {
  const MerchantsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppTopBar(
          title: const Text('Merchants'),
          actions: [
            IconButton(
              tooltip: 'Merge merchants',
              onPressed: () => context.push('/more/merchants/merge'),
              icon: const Icon(Icons.merge_type),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Merchants'),
              Tab(text: 'Rules'),
            ],
          ),
        ),
        body: const TabBarView(children: [_MerchantList(), _RuleList()]),
      ),
    );
  }
}

class _MerchantList extends ConsumerWidget {
  const _MerchantList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchants = ref.watch(merchantsProvider);
    return merchants.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Merchants appear when you name a payee, or when a bank SMS names one.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32).plusNavBar(context),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _MerchantTile(row: rows[i], all: rows),
        );
      },
    );
  }
}

class _MerchantTile extends ConsumerWidget {
  const _MerchantTile({required this.row, required this.all});

  final MerchantRecord row;
  final List<MerchantRecord> all;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${row.emoji ?? ''} ${row.name}'.trim(),
              style: theme.textTheme.titleMedium,
            ),
            if (row.aliases.isNotEmpty)
              Text(
                row.aliases.join(', '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _alias(context, ref),
                  child: const Text('Add alias'),
                ),
                OutlinedButton(
                  onPressed: () => _emoji(context, ref),
                  child: const Text('Emoji'),
                ),
                OutlinedButton(
                  onPressed: () => _category(context, ref),
                  child: const Text('Category'),
                ),
                if (all.length > 1)
                  OutlinedButton(
                    onPressed: () => context.push(
                      '/more/merchants/merge?keep=${row.id}',
                    ),
                    child: const Text('Merge'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _alias(BuildContext context, WidgetRef ref) async {
    final text = await _ask(context, 'Alias', 'SWIGGY, Swiggy*Order');
    if (text == null || text.trim().isEmpty) return;
    await MerchantStore(ref.read(dbProvider)).addAlias(row.id, text.trim());
    ref.invalidate(merchantsProvider);
  }

  Future<void> _emoji(BuildContext context, WidgetRef ref) async {
    final text = await _ask(context, 'Emoji', '🍔');
    if (text == null) return;
    await MerchantStore(ref.read(dbProvider)).setEmoji(row.id, text.trim());
    ref.invalidate(merchantsProvider);
  }

  Future<void> _category(BuildContext context, WidgetRef ref) async {
    final expense =
        ref.read(categoriesProvider(CategoryKind.expense)).valueOrNull ??
        const <CategoryRow>[];
    final income =
        ref.read(categoriesProvider(CategoryKind.income)).valueOrNull ??
        const <CategoryRow>[];
    final id = await showCategoryPickSheet(
      context,
      categories: [...expense, ...income],
      title: 'Default category',
    );
    if (id == null) return;
    await MerchantStore(ref.read(dbProvider)).setDefaultCategory(row.id, id);
    ref.invalidate(merchantsProvider);
    ref.invalidate(categorisationRulesProvider);
  }
}

class _RuleList extends ConsumerWidget {
  const _RuleList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(categorisationRulesProvider);
    final byId = ref.watch(categoryMapProvider);
    return rules.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Change a transaction’s category and choose “Apply to all” to save a rule.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32).plusNavBar(context),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final rule = rows[i];
            final name = byId[rule.categoryId]?.name ?? 'Category';
            return AppCard(
              child: Column(
                children: [
                  AppSwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(rule.merchantName),
                    subtitle: Text(name),
                    value: rule.enabled,
                    onChanged: (on) async {
                      await MerchantStore(ref.read(dbProvider)).setRuleEnabled(
                        rule.id,
                        on,
                      );
                      ref.invalidate(categorisationRulesProvider);
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => _retarget(context, ref, rule),
                          child: const Text('Change category'),
                        ),
                        TextButton(
                          onPressed: () => _delete(context, ref, rule),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _retarget(
    BuildContext context,
    WidgetRef ref,
    CategorisationRuleRecord rule,
  ) async {
    final expense =
        ref.read(categoriesProvider(CategoryKind.expense)).valueOrNull ??
        const <CategoryRow>[];
    final income =
        ref.read(categoriesProvider(CategoryKind.income)).valueOrNull ??
        const <CategoryRow>[];
    final id = await showCategoryPickSheet(
      context,
      categories: [...expense, ...income],
      title: 'Category for ${rule.merchantName}',
    );
    if (id == null) return;
    await MerchantStore(ref.read(dbProvider)).setDefaultCategory(
      rule.merchantId,
      id,
    );
    ref.invalidate(categorisationRulesProvider);
    ref.invalidate(merchantsProvider);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    CategorisationRuleRecord rule,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this rule?'),
        content: Text(
          '${rule.merchantName} will no longer pick a category on its own. '
          'Existing transactions stay as they are.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await MerchantStore(ref.read(dbProvider)).deleteRule(rule.id);
    ref.invalidate(categorisationRulesProvider);
  }
}

Future<String?> _ask(BuildContext context, String title, String hint) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
