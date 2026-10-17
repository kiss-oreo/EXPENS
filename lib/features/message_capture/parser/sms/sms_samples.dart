import 'sms_models.dart';

/// One block from `samples/sms_samples.txt`.
class SmsSample {
  const SmsSample({
    required this.id,
    required this.sender,
    required this.body,
    required this.expect,
    this.reason,
    this.amountPaise,
    this.account,
    this.merchantContains,
    this.reference,
    this.balancePaise,
    this.paymentMethod,
  });

  final String id;
  final String sender;
  final String body;

  /// `debit`, `credit`, or `ignore`.
  final String expect;
  final SmsIgnoreReason? reason;
  final int? amountPaise;
  final String? account;
  final String? merchantContains;
  final String? reference;
  final int? balancePaise;
  final String? paymentMethod;
}

/// Parses the sample file. Lines starting with `#` are comments. Blocks are
/// separated by a line that is exactly `===`.
List<SmsSample> parseSmsSamples(String text) {
  final blocks = text.split(RegExp(r'^===\s*$', multiLine: true));
  final out = <SmsSample>[];
  for (final raw in blocks) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) continue;
    final sample = _one(trimmed);
    if (sample != null) out.add(sample);
  }
  return out;
}

SmsSample? _one(String block) {
  final sep = block.indexOf('\n---\n');
  if (sep < 0) return null;
  final header = block.substring(0, sep);
  final body = block.substring(sep + 5).trim();
  final fields = <String, String>{};
  for (final line in header.split('\n')) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final colon = t.indexOf(':');
    if (colon <= 0) continue;
    fields[t.substring(0, colon).trim()] = t.substring(colon + 1).trim();
  }
  final id = fields['id'];
  final sender = fields['sender'];
  final expect = fields['expect'];
  if (id == null || sender == null || expect == null || body.isEmpty) {
    return null;
  }
  return SmsSample(
    id: id,
    sender: sender,
    body: body,
    expect: expect,
    reason: _reason(fields['reason']),
    amountPaise: int.tryParse(fields['amount_paise'] ?? ''),
    account: fields['account'],
    merchantContains: fields['merchant_contains'],
    reference: fields['reference'],
    balancePaise: int.tryParse(fields['balance_paise'] ?? ''),
    paymentMethod: fields['payment_method'],
  );
}

SmsIgnoreReason? _reason(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  for (final reason in SmsIgnoreReason.values) {
    if (reason.name == raw) return reason;
  }
  return null;
}
