import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/app_surfaces.dart';
import '../../data/providers.dart';
import 'export_format.dart';
import 'import_from_file.dart';
import '../../core/widgets/nav_bar_inset.dart';

/// Export the ledger to a file the user can carry off the phone, or bring
/// one back in.
///
/// Export never uploads anything — every export button writes a file locally
/// and then hands it to the system share sheet, so the data leaves only when
/// the user picks a destination themselves. Import is the other direction:
/// a JSON file exported from here (or a backup made on another phone) can be
/// read back in from the same screen — see `importDataFromFile`.
class DownloadDataScreen extends ConsumerStatefulWidget {
  const DownloadDataScreen({super.key});

  @override
  ConsumerState<DownloadDataScreen> createState() => _DownloadDataScreenState();
}

class _DownloadDataScreenState extends ConsumerState<DownloadDataScreen> {
  bool _busy = false;
  String? _running;

  Future<void> _export({
    required String tag,
    required Future<File> Function() write,
    required String subject,
  }) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(backupServiceProvider);
    setState(() {
      _busy = true;
      _running = tag;
    });
    try {
      final f = await write();
      await service.share(f, subject: subject);
      if (!mounted) return;
      final name = f.uri.pathSegments.last;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Exported $name'),
            action: SnackBarAction(
              label: 'Share again',
              onPressed: () => service.share(f, subject: subject),
            ),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text("Couldn't export: $e")));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _running = null;
        });
      }
    }
  }

  Future<void> _exportFiltered(String tag) async {
    final db = ref.read(dbProvider);
    final accounts = await db.select(db.accounts).get();
    final categories = await db.select(db.categories).get();
    if (!mounted) return;
    final accountNames = accounts.map((a) => a.name).toSet().toList()..sort();
    final categoryNames = categories.map((c) => c.name).toSet().toList()
      ..sort();
    final filter = await showDialog<ExportFilter>(
      context: context,
      builder: (ctx) => _ExportFilterDialog(
        accountNames: accountNames,
        categoryNames: categoryNames,
      ),
    );
    if (filter == null || !mounted) return;
    final service = ref.read(backupServiceProvider);
    await _export(
      tag: tag,
      subject: 'Expens $tag',
      write: () {
        switch (tag) {
          case 'xlsx':
            return service.writeXlsx(filter: filter);
          case 'pdf':
            return service.writePeriodPdf(filter: filter);
          default:
            return service.writeAccountantCsv(filter: filter);
        }
      },
    );
  }

  Future<void> _importFromFile() async {
    if (_busy) return;
    await importDataFromFile(
      context,
      ref,
      setBusy: (busy) {
        if (mounted) {
          setState(() {
            _busy = busy;
            _running = busy ? 'import' : null;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: const Text('Download Data')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32).plusNavBar(context),
        children: [
          const _IntroCard(),
          const SizedBox(height: 16),
          _ActionCard(
            icon: Icons.table_chart_outlined,
            title: 'Transactions (CSV)',
            subtitle:
                'Date, time, type, amount, account, category, subcategory, '
                'merchant, reference, tags and source. Amounts are exact paise. '
                'Filter by date, account, category, or type first.',
            buttonLabel: 'Export CSV',
            busy: _busy && _running == 'csv',
            enabled: !_busy,
            onPressed: () => _exportFiltered('csv'),
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.grid_on_outlined,
            title: 'Excel (XLSX)',
            subtitle:
                'A summary sheet and a transactions sheet, using the same '
                'date, account, category, and type filters as CSV.',
            buttonLabel: 'Export Excel',
            busy: _busy && _running == 'xlsx',
            enabled: !_busy,
            onPressed: () => _exportFiltered('xlsx'),
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.picture_as_pdf_outlined,
            title: 'PDF statement',
            subtitle:
                'Totals and a category summary for the same date, account, '
                'category, and type filters. An open date range uses the '
                'rows that match, not the current month.',
            buttonLabel: 'Export PDF',
            busy: _busy && _running == 'pdf',
            enabled: !_busy,
            onPressed: () => _exportFiltered('pdf'),
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.data_object_outlined,
            title: 'Everything (JSON)',
            subtitle:
                'A complete copy of every account, transaction, budget and '
                'person.',
            buttonLabel: 'Export JSON',
            busy: _busy && _running == 'json',
            enabled: !_busy,
            onPressed: () => _export(
              tag: 'json',
              write: () => ref.read(backupServiceProvider).writeJson(),
              subject: 'Expens data',
            ),
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Import',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          _ActionCard(
            icon: Icons.file_open_outlined,
            title: 'From a JSON file',
            subtitle:
                'Bring in an "Everything (JSON)" export — from this phone or '
                'another one. Replaces all current data; a safety copy is '
                'saved first.',
            buttonLabel: 'Import JSON',
            busy: _busy && _running == 'import',
            enabled: !_busy,
            onPressed: _importFromFile,
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.table_chart_outlined,
            title: 'From a bank CSV statement',
            subtitle:
                "Adds transactions from a bank's exported .csv statement "
                "into an account you choose — doesn't touch anything else.",
            buttonLabel: 'Import CSV',
            busy: false,
            enabled: !_busy,
            onPressed: () => context.push('/import-csv'),
          ),
        ],
      ),
    );
  }
}

class _ExportFilterDialog extends StatefulWidget {
  const _ExportFilterDialog({
    required this.accountNames,
    required this.categoryNames,
  });

  final List<String> accountNames;
  final List<String> categoryNames;

  @override
  State<_ExportFilterDialog> createState() => _ExportFilterDialogState();
}

class _ExportFilterDialogState extends State<_ExportFilterDialog> {
  DateTime? _start;
  DateTime? _end;
  String? _account;
  String? _category;
  String? _type;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Export filters'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('From'),
              subtitle: Text(_start == null ? 'Any' : _fmt(_start!)),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  initialDate: _start ?? DateTime.now(),
                );
                if (picked != null) setState(() => _start = picked);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('To'),
              subtitle: Text(_end == null ? 'Any' : _fmt(_end!)),
              trailing: _start == null && _end == null
                  ? null
                  : IconButton(
                      tooltip: 'Clear dates',
                      onPressed: () => setState(() {
                        _start = null;
                        _end = null;
                      }),
                      icon: const Icon(Icons.clear),
                    ),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  initialDate: _end ?? DateTime.now(),
                );
                if (picked != null) setState(() => _end = picked);
              },
            ),
            DropdownButtonFormField<String?>(
              initialValue: _account,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Account'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Any'),
                ),
                for (final name in widget.accountNames)
                  DropdownMenuItem<String?>(value: name, child: Text(name)),
              ],
              onChanged: (value) => _account = value,
            ),
            DropdownButtonFormField<String?>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Any'),
                ),
                for (final name in widget.categoryNames)
                  DropdownMenuItem<String?>(value: name, child: Text(name)),
              ],
              onChanged: (value) => _category = value,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final type in const ['Income', 'Expense', 'Transfer'])
                  ChoiceChip(
                    label: Text(type),
                    selected: _type == type,
                    onSelected: (on) => setState(() => _type = on ? type : null),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            ExportFilter(
              start: _start,
              endInclusive: _end,
              account: _account,
              category: _category,
              type: _type,
            ),
          ),
          child: const Text('Export'),
        ),
      ],
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Reassures the user that exporting is a deliberate, local-first action.
class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIcon(Icons.lock_outline, color: cs.onSurfaceVariant),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Your data never leaves this phone unless you choose to share '
                'it.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One export format: an icon, a plain-language description and a button that
/// spins while its file is being written.
class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.busy,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: AppIcon(icon, color: cs.onSurface, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: enabled ? onPressed : null,
              child: busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}
