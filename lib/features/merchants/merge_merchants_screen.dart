import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/app_surfaces.dart';
import '../../core/widgets/nav_bar_inset.dart';
import '../../data/providers.dart';
import 'merchant_store.dart';
import 'merchants_screen.dart';

/// Folds one or more merchants into a keeper. Payee text, aliases and rules
/// move with them. The dropped rows are removed.
class MergeMerchantsScreen extends ConsumerStatefulWidget {
  const MergeMerchantsScreen({this.initialKeepId, super.key});

  final int? initialKeepId;

  @override
  ConsumerState<MergeMerchantsScreen> createState() =>
      _MergeMerchantsScreenState();
}

class _MergeMerchantsScreenState extends ConsumerState<MergeMerchantsScreen> {
  int? _keepId;
  final _dropIds = <int>{};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _keepId = widget.initialKeepId;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final merchants = ref.watch(merchantsProvider);
    return Scaffold(
      appBar: AppTopBar(title: const Text('Merge merchants')),
      body: merchants.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (rows) {
          if (rows.length < 2) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'You need at least two merchants before any can be merged.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final keep = rows.where((m) => m.id == _keepId).firstOrNull;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  children: [
                    Text(
                      'Keep one name. The others become aliases, and their '
                      'transactions are rewritten to the name you keep.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'KEEP',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final row in rows)
                      ListTile(
                        leading: Icon(
                          _keepId == row.id
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                        ),
                        title: Text(_label(row)),
                        subtitle: row.aliases.isEmpty
                            ? null
                            : Text(row.aliases.join(', ')),
                        onTap: _busy
                            ? null
                            : () => setState(() {
                                _keepId = row.id;
                                _dropIds.remove(row.id);
                              }),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'FOLD IN',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final row in rows)
                      if (row.id != _keepId)
                        CheckboxListTile(
                          value: _dropIds.contains(row.id),
                          title: Text(_label(row)),
                          onChanged: _busy || _keepId == null
                              ? null
                              : (on) => setState(() {
                                  if (on ?? false) {
                                    _dropIds.add(row.id);
                                  } else {
                                    _dropIds.remove(row.id);
                                  }
                                }),
                        ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16).plusNavBar(
                  context,
                ),
                child: FilledButton(
                  onPressed: _busy || keep == null || _dropIds.isEmpty
                      ? null
                      : () => _merge(rows, keep),
                  child: Text(
                    _busy ? 'Merging…' : 'Merge into ${keep?.name ?? '…'}',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _label(MerchantRecord row) =>
      '${row.emoji ?? ''} ${row.name}'.trim();

  Future<void> _merge(List<MerchantRecord> rows, MerchantRecord keep) async {
    final names = rows
        .where((m) => _dropIds.contains(m.id))
        .map((m) => m.name)
        .join(', ');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Merge merchants?'),
        content: Text(
          '$names will be folded into ${keep.name}. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Merge'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final store = MerchantStore(ref.read(dbProvider));
      for (final id in _dropIds.toList()) {
        await store.merge(keepId: keep.id, dropId: id);
      }
      ref.invalidate(merchantsProvider);
      ref.invalidate(categorisationRulesProvider);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not merge: $e')),
      );
    }
  }
}
