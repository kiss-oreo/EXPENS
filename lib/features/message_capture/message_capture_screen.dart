import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/branding/app_info.dart';
import '../../core/widgets/app_surfaces.dart';
import '../../core/widgets/nav_bar_inset.dart';
import '../../data/ledger_extensions.dart';
import '../../data/providers.dart';
import 'sms_capture_bridge.dart';

final keepRawSmsProvider = FutureProvider<bool>((ref) {
  return keepRawSms(ref.watch(dbProvider));
});

final senderRulesListProvider = StreamProvider((ref) {
  return ref.watch(dbProvider).watchSenderRules();
});

/// Incoming-SMS capture. Off until the user turns it on, after an
/// explanation screen. Never scans the inbox.
class MessageCaptureScreen extends ConsumerWidget {
  const MessageCaptureScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final settings = ref.watch(settingsProvider).valueOrNull;
    final enabled = settings?.messageCaptureEnabled ?? false;
    final keepRaw = ref.watch(keepRawSmsProvider).valueOrNull ?? false;
    final rules = ref.watch(senderRulesListProvider).valueOrNull ?? const [];
    final pending = ref.watch(pendingCountProvider);

    return Scaffold(
      appBar: AppTopBar(title: const Text('Message Capture')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32).plusNavBar(context),
        children: [
          Text(
            '${AppInfo.name} listens only for the SMS that just arrived. '
            'It does not read your inbox, does not store the message unless '
            'you ask, and does not use the internet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              children: [
                AppSwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  secondary: const AppIcon(Icons.sms_outlined),
                  title: const Text('Capture incoming SMS'),
                  subtitle: Text(
                    enabled
                        ? 'On. Pause this any time — nothing already saved is deleted.'
                        : 'Off. Bank texts are ignored until you turn this on.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  value: enabled,
                  onChanged: (on) => _setEnabled(context, ref, on),
                ),
                Divider(height: 1, indent: 60, color: cs.outline),
                AppSwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  secondary: const AppIcon(Icons.bug_report_outlined),
                  title: const Text('Keep raw SMS for debugging'),
                  subtitle: Text(
                    'Off by default. When on, the message text is stored with '
                    'the transaction so a bad parse can be inspected.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  value: keepRaw,
                  onChanged: (on) async {
                    await setMetaValue(ref.read(dbProvider), 'keep_raw_sms', on ? '1' : '0');
                    await SmsCaptureBridge.setKeepRaw(on);
                    ref.invalidate(keepRawSmsProvider);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              children: [
                AppListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: const AppIcon(Icons.science_outlined),
                  title: const Text('Parser test'),
                  subtitle: Text(
                    'Paste a sample and see the fields',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  trailing: const AppIcon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/more/capture/parser-test'),
                ),
                Divider(height: 1, indent: 60, color: cs.outline),
                AppListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: const AppIcon(Icons.restore_outlined),
                  title: const Text('Removed payments'),
                  subtitle: Text(
                    'Restore one that was dropped by mistake',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  trailing: const AppIcon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/more/capture/ignored'),
                ),
                Divider(height: 1, indent: 60, color: cs.outline),
                AppListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: const AppIcon(Icons.rate_review_outlined),
                  title: const Text('Needs review'),
                  subtitle: Text(
                    'Unassigned or uncategorised SMS payments',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  trailing: const AppIcon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/more/needs-review'),
                ),
                if (pending > 0) ...[
                  Divider(height: 1, indent: 60, color: cs.outline),
                  AppListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: const AppIcon(Icons.inbox_outlined),
                    title: const Text('Review Inbox'),
                    subtitle: Text(
                      '$pending still waiting',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    trailing: const AppIcon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/inbox'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'ENABLED BANKS',
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          AppCard(
            child: Column(
              children: [
                for (final (i, rule) in rules.indexed) ...[
                  if (i > 0) Divider(height: 1, color: cs.outline),
                  AppSwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(rule.bankName),
                    subtitle: Text(
                      rule.senderPattern,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    value: rule.enabled,
                    onChanged: (on) => ref
                        .read(dbProvider)
                        .setSenderRuleEnabled(rule.id, on),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setEnabled(
    BuildContext context,
    WidgetRef ref,
    bool on,
  ) async {
    final db = ref.read(dbProvider);
    if (on) {
      final granted = await context.push<bool>('/more/capture/permission');
      if (granted != true) return;
    }
    await db.setMessageCaptureEnabled(on);
    await SmsCaptureBridge.setEnabled(on);
  }
}
