import 'package:flutter/material.dart';

import '../../core/widgets/app_surfaces.dart';
import '../../core/widgets/nav_bar_inset.dart';
import 'parser/sms/sms_capture_parser.dart';
import 'parser/sms/sms_models.dart';

/// Paste a sample SMS and see how the pure parser reads it. Nothing is
/// stored. The raw text stays in this screen's controllers.
class ParserTestScreen extends StatefulWidget {
  const ParserTestScreen({super.key});

  @override
  State<ParserTestScreen> createState() => _ParserTestScreenState();
}

class _ParserTestScreenState extends State<ParserTestScreen> {
  final _sender = TextEditingController(text: 'VM-HDFCBK-S');
  final _body = TextEditingController();
  final _parser = const SmsCaptureParser();
  SmsParseOutcome? _outcome;

  @override
  void dispose() {
    _sender.dispose();
    _body.dispose();
    super.dispose();
  }

  void _run() {
    setState(() {
      _outcome = _parser.parse(
        body: _body.text,
        sender: _sender.text,
        receivedAt: DateTime.now(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppTopBar(title: const Text('Parser test')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32).plusNavBar(context),
        children: [
          Text(
            'Paste one message. This screen does not save it, and it never '
            'reads your inbox.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _sender,
                decoration: const InputDecoration(
                  labelText: 'Sender ID',
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _body,
                minLines: 5,
                maxLines: 10,
                decoration: const InputDecoration(
                  hintText: 'Paste the SMS body',
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _run, child: const Text('Parse')),
          const SizedBox(height: 16),
          if (_outcome != null) _Result(outcome: _outcome!),
        ],
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.outcome});

  final SmsParseOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parsed = outcome;
    if (parsed is SmsIgnored) {
      return AppCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Ignored — ${parsed.reason.name}',
            style: theme.textTheme.titleMedium,
          ),
        ),
      );
    }
    final value = (parsed as SmsParsedMessage).value;
    final rows = <(String, String)>[
      ('Direction', value.direction.name),
      ('Amount', 'Rs ${formatPaise(value.amountPaise)}'),
      ('Account', value.accountLast4 ?? '—'),
      ('Merchant', value.merchant ?? '—'),
      ('Reference', value.reference ?? '—'),
      (
        'Balance',
        value.balancePaise == null ? '—' : 'Rs ${formatPaise(value.balancePaise!)}',
      ),
      ('Payment', value.paymentMethod ?? '—'),
      ('Bank', value.bankName),
      ('When', value.timestamp.toString()),
      ('Confidence', '${value.confidence}'),
    ];
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        row.$1,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(child: Text(row.$2)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
