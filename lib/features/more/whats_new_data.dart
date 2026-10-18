import 'package:flutter/material.dart';

/// One line item on the What's New screen — what shipped, where to find it,
/// and what it actually does. Updated by hand alongside CHANGELOG.md each
/// release; there's no automated link between the two (see CHANGELOG.md for
/// the full, dated history — this is just the current version's highlights,
/// written for someone opening the app, not reading a changelog).
class WhatsNewEntry {
  const WhatsNewEntry({
    required this.icon,
    required this.title,
    required this.location,
    required this.description,
  });

  final IconData icon;
  final String title;

  /// Where to find it, e.g. "Persons → tap a person".
  final String location;
  final String description;
}

const whatsNewEntries = <WhatsNewEntry>[
  WhatsNewEntry(
    icon: Icons.picture_as_pdf_outlined,
    title: 'Import a UPI statement',
    location: 'More → Import statement',
    description:
        'Pick a Google Pay or PhonePe PDF. It is read on this phone. '
        'Failed and pending rows are skipped, and anything already in the '
        'ledger is marked before you save.',
  ),
  WhatsNewEntry(
    icon: Icons.bolt_outlined,
    title: 'Quick add',
    location: 'More → Quick add',
    description:
        'Tap an amount, tap a merchant, tap Save. Category rules still apply.',
  ),
  WhatsNewEntry(
    icon: Icons.rate_review_outlined,
    title: 'Needs review',
    location: 'More → Needs review',
    description:
        'SMS payments that landed on Unassigned, or that still have no '
        'category, wait here.',
  ),
  WhatsNewEntry(
    icon: Icons.event_repeat_outlined,
    title: 'Subscription reminders',
    location: 'More → Subscriptions',
    description:
        'Three similar payments on a weekly, monthly, or yearly gap show '
        'the next expected date. Nothing is added for you.',
  ),
  WhatsNewEntry(
    icon: Icons.pause_circle_outline,
    title: 'Capture paused is visible',
    location: 'Home',
    description:
        'If SMS capture is paused, or incoming-SMS permission is off, a '
        'banner says so. A notification is posted only when notifications '
        'are on.',
  ),
];
