import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/branding/app_info.dart';
import '../../core/permissions/app_permissions.dart';
import '../../core/widgets/app_surfaces.dart';
import '../../core/widgets/nav_bar_inset.dart';

/// Shown before Android's SMS dialog. The permission is asked only here,
/// when the user turns capture on.
class SmsPermissionScreen extends StatelessWidget {
  const SmsPermissionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppTopBar(title: const Text('Incoming SMS')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32).plusNavBar(context),
        children: [
          Text(
            '${AppInfo.name} can record a bank payment from the SMS that '
            'just arrived.',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'It uses the incoming-message permission only. It never asks to '
            'read your inbox, never scans old messages, and never sends the '
            'text anywhere. Only the amount, account, merchant and reference '
            'are kept. The message itself is discarded unless you turn on '
            '“keep raw SMS for debugging”.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () async {
              final state = await AppPermissions.request(AppPermission.sms);
              if (!context.mounted) return;
              context.pop(state == PermissionState.granted);
            },
            child: const Text('Continue'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }
}
