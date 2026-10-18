import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/widgets/app_surfaces.dart';
import '../../core/widgets/nav_bar_inset.dart';
import '../../data/providers.dart';
import 'pdf_text.dart';
import 'statement_import.dart';
import 'statement_parser.dart';

/// Picks a PDF with the system file picker. No storage permission is requested.
/// Parsing stays on this device. Nothing is written until Save.
class StatementPreviewScreen extends ConsumerStatefulWidget {
  const StatementPreviewScreen({super.key});

  @override
  ConsumerState<StatementPreviewScreen> createState() =>
      _StatementPreviewScreenState();
}

class _StatementPreviewScreenState
    extends ConsumerState<StatementPreviewScreen> {
  final _parser = const StatementParser();
  List<StatementChoice> _choices = const [];
  List<bool> _selected = const [];
  var _skipped = 0;
  var _busy = false;
  String? _error;
  String? _fileName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppTopBar(title: const Text('Import statement')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32).plusNavBar(context),
        children: [
          Text(
            'Choose a Google Pay or PhonePe PDF. It is read on this phone. '
            'Failed and pending rows are skipped. Nothing is saved until you confirm.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(_fileName == null ? 'Choose PDF' : 'Choose another PDF'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (_choices.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              _skipped == 0
                  ? '${_choices.length} completed payments'
                  : '${_choices.length} completed payments. $_skipped failed or pending rows were skipped.',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _choices.length; i++) _tile(i),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy || !_selected.contains(true) ? null : _save,
              child: Text(_busy ? 'Saving' : 'Save selected'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tile(int index) {
    final choice = _choices[index];
    final row = choice.row;
    final when = DateFormat('d MMM yyyy, HH:mm').format(row.date);
    final who = row.merchant.isEmpty ? 'Unknown' : row.merchant;
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: _selected[index],
      onChanged: _busy
          ? null
          : (value) => setState(() => _selected[index] = value ?? false),
      title: Text('$who · ${MoneyFormat.symbol(Money(row.amountPaise))}'),
      subtitle: Text(
        choice.isDuplicate
            ? '$when · Already in your ledger'
            : '$when · ${row.direction.name}',
      ),
    );
  }

  Future<void> _pick() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      // System picker only. withData reads the granted URI. No storage permission.
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
      );
      if (!mounted || picked == null) return;
      final file = picked.files.single;
      final bytes = file.bytes ?? await _bytesFromPath(file.path);
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        setState(() => _error = "Couldn't read that file. Nothing was saved.");
        return;
      }
      final text = PdfText.extract(bytes);
      final parsed = _parser.parse(text);
      if (parsed.rows.isEmpty) {
        setState(() {
          _choices = const [];
          _selected = const [];
          _skipped = parsed.skipped;
          _fileName = file.name;
          _error = parsed.skipped > 0
              ? 'Those rows were failed or pending, so nothing was imported.'
              : "This doesn't look like a Google Pay or PhonePe statement. Nothing was saved.";
        });
        return;
      }
      final choices = await StatementImportService(
        ref.read(dbProvider),
      ).preview(parsed.rows);
      if (!mounted) return;
      setState(() {
        _choices = choices;
        _selected = [for (final _ in choices) true];
        _skipped = parsed.skipped;
        _fileName = file.name;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't read that PDF. Nothing was saved.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Uint8List?> _bytesFromPath(String? path) async {
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    return file.readAsBytes();
  }

  Future<void> _save() async {
    final selected = <StatementChoice>[
      for (var i = 0; i < _choices.length; i++)
        if (_selected[i]) _choices[i],
    ];
    setState(() => _busy = true);
    try {
      final result = await StatementImportService(
        ref.read(dbProvider),
      ).save(selected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved ${result.inserted}. Merged ${result.merged}. '
            'Duplicates were not added again.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't save those rows. Nothing new was added.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
