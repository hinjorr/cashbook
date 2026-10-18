# Cashbook

A personal finance app for Android (Flutter), modelled on Money Manager, with
**investment tracking**, **Google Drive backup** and **Money Manager import**.

## Features

- **Transactions**: income, expense and transfer, with categories and
  subcategories, notes and descriptions. Views: Daily, Calendar and Monthly.
  Search across all transactions.
- **Stats**: Income and Expenses pie charts by category, and an **Invested**
  tab. Periods: weekly, monthly, yearly, all time or a custom range.
- **Investment stats**: mark accounts (Stocks, Savings, Funds…) as
  *investment accounts*. Every transfer from a regular account into one of them
  counts as invested; transfers back out count as withdrawn. For any period the
  tab shows:
  - invested, withdrawn, net invested, and income booked on investment accounts
  - current holdings
  - a chart over time (days, weeks or months, depending on the period)
  - per-account breakdown and the list of investment transfers
- **Accounts**: groups, opening balances, assets, liabilities and holdings,
  plus per-account history.
- **Budgets**: a monthly budget per expense category, with progress bars.
- **Month start day**: monthly views can run from your salary day (e.g. 5th–4th).
- **Backup**: Google Drive (manual, plus an automatic daily backup that keeps
  the latest 15), or a `.json` backup file you can share or save anywhere.
- **Import from Money Manager**: reads its "Export data to Excel" file. That
  file is usually tab-separated text with an `.xlsx` name, and real
  `.xlsx`/CSV files work too. Re-importing the same file skips duplicates.

## Getting the APK

Every push runs the **Build APK** workflow (GitHub › Actions). Open a run and
download the `cashbook-apk` artifact.

## Google Drive setup (one-time)

Google requires every app that uses Drive to be registered:

1. Go to <https://console.cloud.google.com/>, create a project and enable the
   **Google Drive API**.
2. Under **Google Auth Platform › Branding**, set up the consent screen
   (External). While it is in "Testing", add your Gmail under *Audience ›
   Test users*.
3. Under **Clients**, create:
   - an **Android** client with package name `com.hinjorr.cashbook` and the
     SHA-1 of your signing key (see below).
   - a **Web application** client. Copy its client ID.
4. In GitHub › Settings › Secrets and variables › Actions, add
   `GOOGLE_SERVER_CLIENT_ID` = the *Web* client ID.

### Signing key (needed for Drive and for updates)

```sh
keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias cashbook
keytool -list -v -keystore release.jks -alias cashbook   # shows the SHA-1
base64 -w0 release.jks                                   # value for KEYSTORE_BASE64
```

Add these repository secrets: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`,
`KEY_ALIAS` (`cashbook`) and `KEY_PASSWORD`. Keep `release.jks` safe: an APK
signed with a different key can't update the installed app.

## Development

```sh
flutter pub get
flutter test
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com
```

Code layout: `lib/data` (models, SQLite, app state), `lib/logic` (periods,
stats, money), `lib/services` (Drive, file backup, Money Manager import), and
`lib/screens`.
