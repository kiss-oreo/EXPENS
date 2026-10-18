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
- Current schema: **81** (`lib/data/database.dart`). Side tables are created
  by `lib/data/ledger_extensions.dart` with idempotent SQL. Schema 81 only
  re-runs that step. Tags and subcategories already live there. Do not add a
  second schema for them. Do not hand-edit `lib/data/database.g.dart`. Do not
  drop user rows in a migration.

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
  runs the parser against every block. Add a bank only when `/samples`
  contains it. Each bank needs at least three payment samples in that file.
- PDF statement import lives in `lib/features/statement_import/`. It uses the
  system file picker only — no storage permission, no network. Parse the
  layouts in `samples/gpay_statement.txt` and `samples/phonepe_statement.txt`.
  Do not copy parser code from another project. New rows use
  `tx_extras.source = IMPORT_PDF`. A duplicate only fills empty fields. Never
  overwrite a user-set category, account, note, tags, or payee.
- Redacted real statements belong in `samples/real/`. `test/real_samples_test.dart`
  runs every file there. Do not invent fixtures and report them as those files.
  If the directory is missing, that test fails and those formats were not run.
- Subscriptions (`lib/features/subscriptions/`) are reminders only. Never
  auto-create a transaction from a detected pattern.
- Capture health states are Not set up, Active, Paused by you, and Permission
  revoked. Only the last two warn. A fresh install is Not set up, tracked by
  `expens_meta.capture_ever_enabled` (and `lastMessageScanAt` for older rows).
- `CaptureHealthCheck` updates the balance widget label about every six hours
  from saved flags plus the incoming-SMS permission. It is not an SMS receiver
  and must not read a message. `CaptureHealthBoot` reschedules it after reboot.

## Layout

- `lib/features/merchants/` — merchant directory, aliases, rules, and
  `/more/merchants/merge`
- `lib/features/statement_import/` — `/more/import-statement`
- `lib/features/subscriptions/` — `/more/subscriptions`
- Quick add is `/more/quick-add`. Needs review is `/more/needs-review`.
- Capture notification Category action opens `/more/capture/category/:id`.
  The body tap still opens `/add?id=`. Delete does not open the app.
- `lib/features/message_capture/` — share intake (existing) plus the SMS bridge
- `lib/features/data_export/` — XPENC backup plus accountant CSV, XLSX, period PDF.
  All three accountant formats take `ExportFilter` (date range, account,
  category, type) via `loadExportRows`.
- `android/app/src/main/kotlin/com/kissoreo/expens/` — platform channels
- Backup filenames stay `DDMMYYXPENCEBACKUP.json` and the folder stays
  `BACKUP XPENC` so an XPENC backup still restores.

## Do not

- Do not run `tool/generate_icons.py`. It still draws the old X and exits
  on purpose. The launcher is the E already in `mipmap-*/ic_launcher.png`.
- Do not add a network client, analytics, or a tracker.
- Do not bump `schemaVersion` without a migration that keeps existing rows,
  and a test that reopens an older database.

## Release signing

Do not commit a keystore, `android/key.properties`, or `*.jks`.
`android/.gitignore` already ignores those.

`.github/workflows/release.yml` writes `android/key.properties` only when all
four GitHub Actions secrets are non-empty:

- `ANDROID_KEYSTORE_BASE64` — base64 of the upload `.jks`
- `ANDROID_KEYSTORE_PASSWORD` — `storePassword`
- `ANDROID_KEY_PASSWORD` — `keyPassword`
- `ANDROID_KEY_ALIAS` — `keyAlias`

The workflow decodes the keystore to `android/xpenc-release.jks` on the
runner and points `storeFile` at that path. An empty secret deletes
`android/key.properties` and exits that step. Gradle then debug-signs a
sideloadable APK. That APK must not be uploaded to Play.

A local release build uses the same four keys in `android/key.properties`.
Generate the keystore with `keytool` outside the repo and keep a backup.
See `docs/playstore/release-checklist.md`.

## Checks

`flutter analyze` and `flutter test` are the gate. This environment may not
have Flutter installed; do not claim they passed unless they were run.
CI is `.github/workflows/ci.yml` (analyze + test) and `release.yml`
(release APK). `tool/verify_apk.sh` requires `RECEIVE_SMS` and rejects
`READ_SMS` and `INTERNET`. An empty keystore secret must not write
`android/key.properties`; Gradle then debug-signs a sideloadable APK.
