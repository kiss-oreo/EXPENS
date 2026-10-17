/// Dedupe identity for a captured payment.
///
/// A bank reference (UTR / RRN / UPI ref) is conclusive. Without one, the
/// fallback is amount + account last-4 + minute + payee — never the raw SMS.
class SmsDedupe {
  const SmsDedupe._();

  static String key({
    String? reference,
    required int amountPaise,
    String? accountLast4,
    required DateTime receivedAt,
    String? payee,
  }) {
    final ref = reference?.trim();
    if (ref != null && ref.isNotEmpty) {
      return 'ref:${ref.toUpperCase()}';
    }
    final minute = DateTime(
      receivedAt.year,
      receivedAt.month,
      receivedAt.day,
      receivedAt.hour,
      receivedAt.minute,
    );
    final who = (payee ?? '')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9@.]'), '');
    return 'fb:$amountPaise|${accountLast4 ?? ''}|${minute.toIso8601String()}|$who';
  }
}
