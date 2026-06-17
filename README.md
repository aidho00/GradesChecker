# Grades Checker Starter

Flutter Web + PHP API starter for checking HEMIS promotional-list Excel grades against MySQL.

## Current UI version

This build is optimized for web/desktop use.

### Included changes

- One full table row per student.
- Columns for Subject 1 to Subject 10.
- Color legend for status.
- Full-width data workspace below the setup controls.
- Page scrolls naturally from top to bottom; the results area is no longer trapped in a limited viewport.
- Connection/API settings are hidden inside a modal.
- Academic period selector shows `period_name - period_semester` while hiding the internal period ID.
- Faster parsing/checking behavior:
  - Excel rows are parsed with cached column indexes.
  - UI progress is throttled to avoid excessive rebuilds.
  - Database checking uses batches of 500 records per request.
  - PHP checks each batch using grouped SQL lookups instead of one query per row.

## Folder placement

Copy this folder:

```text
api/grades_checker_api
```

To XAMPP:

```text
C:\xampp\htdocs\grades_checker_api
```

Or WAMP:

```text
C:\wamp64\www\grades_checker_api
```

## Database config

Edit:

```text
api/grades_checker_api/config.php
```

Typical local settings:

```php
const DB_HOST = '127.0.0.1';
const DB_PORT = '3306';
const DB_NAME = 'cfcissmsdb';
const DB_USER = 'root';
const DB_PASS = '';
```

## Test API

Open in browser:

```text
http://localhost/grades_checker_api/ping.php
http://localhost/grades_checker_api/periods.php
http://localhost/grades_checker_api/inspect_schema.php
```

## Run Flutter Web

From:

```text
flutter_grades_checker
```

Run:

```bash
flutter pub get
flutter run -d chrome
```

Or fixed web-server port:

```bash
flutter run -d web-server --web-port 53902
```

## Notes on very large Excel files

The app now batches database checking and throttles UI updates. The only unavoidable pause can still happen while the `excel` package decodes the workbook, because that package reads the XLSX workbook synchronously in Flutter Web. After decoding, parsing and database checking are chunked so the browser can repaint progress.
