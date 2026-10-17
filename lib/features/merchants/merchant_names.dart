/// Merchant name normalisation. Pure — no database, no Flutter.
class MerchantNames {
  const MerchantNames._();

  /// Comparison key: upper case, punctuation stripped, VPA local-part and
  /// the token before `*` kept so `SWIGGY`, `Swiggy*Order` and
  /// `swiggy@okaxis` share a stem.
  static String normalize(String input) {
    var s = input.trim().toUpperCase();
    final at = s.indexOf('@');
    if (at > 0) s = s.substring(0, at);
    final star = s.indexOf('*');
    if (star > 0) s = s.substring(0, star);
    s = s.split('/').first;
    return s.replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  /// Display name. `swiggy@okaxis` → `Swiggy`, `SWIGGY*ORDER` → `Swiggy`.
  static String canonical(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    final at = s.indexOf('@');
    if (at > 0) s = s.substring(0, at);
    final star = s.indexOf('*');
    if (star > 0) s = s.substring(0, star);
    s = s.split('/').first.trim();
    if (s.isEmpty) s = raw.trim();
    return s
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) {
          final lower = w.toLowerCase();
          return lower[0].toUpperCase() + lower.substring(1);
        })
        .join(' ');
  }

  /// First enabled rule whose name is the same merchant as [payee].
  /// Disabled rules never win. This is the pure form of the Settings rule list.
  static int? categoryFor(
    String payee,
    Iterable<({String name, int categoryId, bool enabled})> rules,
  ) {
    for (final rule in rules) {
      if (!rule.enabled) continue;
      if (sameMerchant(payee, rule.name)) return rule.categoryId;
    }
    return null;
  }

  static bool sameMerchant(String a, String b) {
    final na = normalize(a);
    final nb = normalize(b);
    if (na.isEmpty || nb.isEmpty) return false;
    return na == nb;
  }
}
