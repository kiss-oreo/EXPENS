import 'bank_sms_parser.dart';

class HdfcSmsParser extends BankSmsParser {
  const HdfcSmsParser();

  @override
  String get id => 'hdfc';
  @override
  String get bankName => 'HDFC Bank';
  @override
  List<String> get senderHeaders => const ['HDFCBK', 'HDFCBN'];

  @override
  List<RegExp> get merchantPatterns => const [];
}

class SbiSmsParser extends BankSmsParser {
  const SbiSmsParser();

  @override
  String get id => 'sbi';
  @override
  String get bankName => 'State Bank of India';
  @override
  List<String> get senderHeaders => const [
    'SBIINB',
    'SBIUPI',
    'SBIPSG',
    'SBIATM',
    'CBSSBI',
  ];

  @override
  List<RegExp> get merchantPatterns => [
    RegExp(r'Info:\s*(?:UPI|NEFT|IMPS)/([^/\n]{2,40})', caseSensitive: false),
  ];
}

class IciciSmsParser extends BankSmsParser {
  const IciciSmsParser();

  @override
  String get id => 'icici';
  @override
  String get bankName => 'ICICI Bank';
  @override
  List<String> get senderHeaders => const ['ICICIB', 'ICICIT'];

  @override
  List<RegExp> get merchantPatterns => [
    RegExp(r';\s*([A-Za-z0-9][A-Za-z0-9 &._-]{2,40}?)\s+credited',
        caseSensitive: false),
  ];
}

class AxisSmsParser extends BankSmsParser {
  const AxisSmsParser();

  @override
  String get id => 'axis';
  @override
  String get bankName => 'Axis Bank';
  @override
  List<String> get senderHeaders => const ['AXISBK', 'AXISB'];

  @override
  List<RegExp> get merchantPatterns => [
    RegExp(r'\bat\s+([A-Za-z0-9][A-Za-z0-9 &._*-]{1,40}?)\.',
        caseSensitive: false),
  ];
}

class KotakSmsParser extends BankSmsParser {
  const KotakSmsParser();

  @override
  String get id => 'kotak';
  @override
  String get bankName => 'Kotak Mahindra Bank';
  @override
  List<String> get senderHeaders => const ['KOTAKB'];

  @override
  List<RegExp> get merchantPatterns => [
    RegExp(r'Payee:\s*([A-Za-z0-9][A-Za-z0-9 &._*-]{1,40})',
        caseSensitive: false),
  ];
}

class PnbSmsParser extends BankSmsParser {
  const PnbSmsParser();

  @override
  String get id => 'pnb';
  @override
  String get bankName => 'Punjab National Bank';
  @override
  List<String> get senderHeaders => const ['PNBSMS', 'PNBBNK'];
}

class BobSmsParser extends BankSmsParser {
  const BobSmsParser();

  @override
  String get id => 'bob';
  @override
  String get bankName => 'Bank of Baroda';
  @override
  List<String> get senderHeaders => const ['BOBTXN', 'BOBSMS', 'BARBNK'];

  @override
  List<RegExp> get merchantPatterns => [
    RegExp(r'towards\s+UPI/([^/\n]{2,40})', caseSensitive: false),
  ];
}

class CanaraSmsParser extends BankSmsParser {
  const CanaraSmsParser();

  @override
  String get id => 'canara';
  @override
  String get bankName => 'Canara Bank';
  @override
  List<String> get senderHeaders => const ['CANBNK', 'CNRBNK'];

  @override
  List<RegExp> get merchantPatterns => [
    RegExp(r'towards\s+([A-Za-z0-9][A-Za-z0-9 &._*-]{1,40}?)\.',
        caseSensitive: false),
  ];
}

class UnionSmsParser extends BankSmsParser {
  const UnionSmsParser();

  @override
  String get id => 'union';
  @override
  String get bankName => 'Union Bank of India';
  @override
  List<String> get senderHeaders => const ['UNIONB', 'UBINBK'];

  @override
  List<RegExp> get merchantPatterns => [
    RegExp(r'Info:\s*UPI/([^/\n]{2,40})', caseSensitive: false),
  ];
}

class IdfcSmsParser extends BankSmsParser {
  const IdfcSmsParser();

  @override
  String get id => 'idfc';
  @override
  String get bankName => 'IDFC FIRST Bank';
  @override
  List<String> get senderHeaders => const ['IDFCFB', 'IDFCBK'];

  @override
  List<RegExp> get merchantPatterns => [
    RegExp(r'\bto\s+([A-Za-z0-9][A-Za-z0-9 &._*-]{1,40}?)\.',
        caseSensitive: false),
  ];
}

class YesSmsParser extends BankSmsParser {
  const YesSmsParser();

  @override
  String get id => 'yes';
  @override
  String get bankName => 'Yes Bank';
  @override
  List<String> get senderHeaders => const ['YESBNK'];

  @override
  List<RegExp> get merchantPatterns => [
    RegExp(r'Info:\s*([A-Za-z0-9][A-Za-z0-9 &._*-]{1,40}?)\.',
        caseSensitive: false),
  ];
}

class IppbSmsParser extends BankSmsParser {
  const IppbSmsParser();

  @override
  String get id => 'ippb';
  @override
  String get bankName => 'India Post Payments Bank';
  @override
  List<String> get senderHeaders => const ['IPPBNK', 'IPPB'];
}

/// The registry. Append a parser here to support another bank.
const List<BankSmsParser> kBankParsers = [
  HdfcSmsParser(),
  SbiSmsParser(),
  IciciSmsParser(),
  AxisSmsParser(),
  KotakSmsParser(),
  PnbSmsParser(),
  BobSmsParser(),
  CanaraSmsParser(),
  UnionSmsParser(),
  IdfcSmsParser(),
  YesSmsParser(),
  IppbSmsParser(),
];
