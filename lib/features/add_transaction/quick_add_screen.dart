import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/app_surfaces.dart';
import '../../core/widgets/nav_bar_inset.dart';
import '../../data/providers.dart';
import '../merchants/merchant_names.dart';
import 'quick_add.dart';

final _merchantNamesProvider = FutureProvider<List<String>>((ref) async {
  final db = ref.watch(dbProvider);
  final merchants = await db.customSelect(
    'SELECT name FROM merchants ORDER BY name COLLATE NOCASE LIMIT 40',
  ).get();
  if (merchants.isNotEmpty) {
    return [for (final row in merchants) row.read<String>('name')];
  }
  final payees = await db.customSelect(
    '''
    SELECT payee FROM transactions
    WHERE payee IS NOT NULL AND payee != ''
    GROUP BY payee
    ORDER BY MAX(date) DESC
    LIMIT 40
    ''',
  ).get();
  return [for (final row in payees) row.read<String>('payee')];
});

/// Amount first, then a merchant chip, then Save. Those three taps are enough
/// when the amount is one of the chips.
class QuickAddScreen extends ConsumerStatefulWidget {
  const QuickAddScreen({super.key});

  @override
  ConsumerState<QuickAddScreen> createState() => _QuickAddScreenState();
}

class _QuickAddScreenState extends ConsumerState<QuickAddScreen> {
  static const _amounts = ['50', '100', '200', '500'];
  final _amount = TextEditingController();
  final _merchant = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final names = ref.watch(_merchantNamesProvider).valueOrNull ?? const [];
    final query = MerchantNames.normalize(_merchant.text);
    final shown = [
      for (final name in names)
        if (query.isEmpty || MerchantNames.normalize(name).contains(query))
          name,
    ].take(8);
    return Scaffold(
      appBar: AppTopBar(title: const Text('Quick add')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32).plusNavBar(context),
        children: [
          Text(
            'Amount, merchant, save.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text('Amount', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final amount in _amounts)
                ChoiceChip(
                  label: Text(amount),
                  selected: _amount.text == amount,
                  onSelected: (_) => setState(() {
                    _amount.text = amount;
                    _error = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Or type an amount',
              hintText: '250.50',
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 20),
          Text('Merchant', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _merchant,
            decoration: const InputDecoration(labelText: 'Merchant'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in shown)
                ChoiceChip(
                  label: Text(name),
                  selected: MerchantNames.sameMerchant(_merchant.text, name),
                  onSelected: (_) => setState(() => _merchant.text = name),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving' : 'Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final error = await saveQuickAdd(
      db: ref.read(dbProvider),
      amountText: _amount.text,
      merchant: _merchant.text,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved.')),
    );
    Navigator.of(context).pop();
  }
}
