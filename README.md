# UNO to SMS Grade Checker

Web/desktop Flutter + PHP/Database checker for comparing legacy UNO promotional-list Excel files against current SMS grade records.

## What this version does

- Streams the uploaded `.xlsx` to the PHP API instead of loading/decoding the full workbook inside Flutter Web.
- Parses the workbook on the PHP API to reduce browser upload/parse freezes.
- Checks grade records in smaller batches against:
  - `tbl_period`
  - `tbl_student`
  - `tbl_course`
  - `tbl_subject`
  - `tbl_students_grades`
- Displays one compact table row per student with `Subject 1` to `Subject 10` across the row.
- Uses cached student grouping and pagination to reduce table lag.
- Supports 50, 100, 150, and 250 rows per page.
- Provides pagination controls at the top and bottom of the table.
- Keeps the horizontal table position controllable using a bottom sticky horizontal scroll control.
- Lets you tap a subject cell to inspect subject description, selected-period DB grades, duplicate grades, and grades found in other academic periods.
- Exports a formatted Excel-compatible `.xls` file with status colors and DB comparison columns.
- Generates an overall interpretation after the table.

## Install API

Copy:

```text
grades_checker_starter/api/grades_checker_api
```

To XAMPP:

```text
C:\xampp\htdocs\grades_checker_api
```

Or WAMP:

```text
C:\wamp64\www\grades_checker_api
```

Edit `config.php` if your Database username/password/port is different.

## Test API

Open:

```text
http://localhost/grades_checker_api/ping.php
http://localhost/grades_checker_api/periods.php
```

## Run Flutter Web

```bash
cd grades_checker_starter/flutter_grades_checker
flutter clean
flutter pub get
flutter run -d chrome
```

Default API endpoint in the app:

```text
http://localhost/grades_checker_api/check_grades.php
```

Use the Connection button only if Apache is on another port or server IP.

## Notes

The export uses an Excel-compatible HTML `.xls` file so formatting works without requiring Composer, PhpSpreadsheet, or PHP ZipArchive.
