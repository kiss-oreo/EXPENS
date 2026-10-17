# AGENTS.md

Read this file at the start of every task. Update it after a structural change.

## What this repo is

Expens is an offline personal-finance Android app, forked from
[XPENC](https://github.com/PATILYASHH/XPENC) (MIT, copyright Yash Patil).
Keep that license and copyright. Credit XPENC in NOTICE. Do not copy GPL code.

- App name: Expens
- Package / application id: `com.kissoreo.expens`
- Dart package name stays `xpenc` so existing imports keep working
- Version lives in `pubspec.yaml` and `lib/core/branding/app_info.dart`.
  `test/branding_test.dart` fails if they drift.
- Current schema: **80** (`lib/data/database.dart`). Side tables are created
  by `lib/data/ledger_extensions.dart` with idempotent SQL. Do not hand-edit
  `lib/data/database.g.dart`. Do not drop user rows in a migration.

## Money

All money is integer paise (`Money` in `lib/core/money.dart`). Never store
or export a floating-point amount. Export decimals with `formatPaise`
(`paise ~/ 100` and `paise % 100`).

Transfers never affect budgets or income/expense reports. Net worth is the
sum of balance-holding account balances. UPI and debit cards are linked
instruments and must not add a second balance.

## SMS capture — hard rules

- Only a manifest-declared `BroadcastReceiver` for
  `android.provider.Telephony.SMS_RECEIVED`, with `RECEIVE_SMS`.
- Never request `READ_SMS`. Never query `content://sms`. Never scan the inbox.
- Only the message that just arrived may be processed.
- Store parsed fields only. Raw body is stored only when
  `expens_meta.keep_raw_sms` is `1`. That toggle defaults to off.
- No Accessibility Service. No notification listener for capture.
- Release builds strip `INTERNET` (`tools:node="remove"` in the main manifest).
- Parser code lives in `lib/features/message_capture/parser/sms/` and must
  stay free of Flutter and Android imports. One class per bank, listed in
  `kBankParsers`. Unknown formats return an ignore, never throw.
- Samples: `samples/sms_samples.txt`. `test/sms_capture_parser_test.dart`
  runs the parser against every block. Add a sample when you add a bank.

## Layout

- `lib/features/merchants/` — merchant directory, aliases, rules, and
  `/more/merchants/merge`
- Capture notification Category action opens `/more/capture/category/:id`.
  The body tap still opens `/add?id=`. Delete does not open the app.
- `lib/features/message_capture/` — share intake (existing) plus the SMS bridge
- `lib/features/data_export/` — XPENC backup plus accountant CSV, XLSX, period PDF
- `android/app/src/main/kotlin/com/kissoreo/expens/` — platform channels
- Backup filenames stay `DDMMYYXPENCEBACKUP.json` and the folder stays
  `BACKUP XPENC` so an XPENC backup still restores.

## Do not

- Do not run `tool/generate_icons.py`. It still draws the old X and exits
  on purpose. The launcher is the E already in `mipmap-*/ic_launcher.png`.
- Do not add a network client, analytics, or a tracker.
- Do not bump `schemaVersion` without a migration that keeps existing rows,
  and a test that reopens an older database.

## Checks

`flutter analyze` and `flutter test` are the gate. This environment may not
have Flutter installed; do not claim they passed unless they were run.
CI is `.github/workflows/ci.yml` (analyze + test) and `release.yml`
(signed-ready release APK when the keystore secrets are present).
