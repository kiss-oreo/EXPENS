import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/app_surfaces.dart';
import '../message_capture/capture_health.dart';
import '../message_capture/needs_review_screen.dart';

/// Capture health, and a link when something is waiting for review.
class DashboardAlerts extends ConsumerWidget {
  const DashboardAlerts({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(captureHealthProvider).valueOrNull;
    final review = ref.watch(needsReviewProvider).valueOrNull;
    final waiting = review?.length ?? 0;
    if ((health == null || !health.showBanner) && waiting == 0) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        children: [
          if (health != null && health.showBanner)
            AppCard(
              child: ListTile(
                leading: Icon(
                  Icons.pause_circle_outline,
                  color: theme.colorScheme.error,
                ),
                title: Text(health.title),
                subtitle: Text(health.message),
                onTap: () => context.push('/more/capture'),
              ),
            ),
          if (waiting > 0) ...[
            if (health != null && health.showBanner) const SizedBox(height: 8),
            AppCard(
              child: ListTile(
                leading: const Icon(Icons.rate_review_outlined),
                title: Text(
                  waiting == 1 ? '1 needs review' : '$waiting need review',
                ),
                subtitle: const Text(
                  'Unassigned or uncategorised SMS payments',
                ),
                onTap: () => context.push('/more/needs-review'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
