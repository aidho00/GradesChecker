# Grades Checker Starter Project

This is a starter web-based system for cross-checking a HEMIS promotional-list Excel file against your `cfcissmsdb` MySQL database.

## Yes, Flutter + MySQL is possible

Use this architecture:

```text
Flutter Web UI
  -> reads .xlsx in the browser
  -> converts SUBJECT1/UNITS1/GRADE1 ... SUBJECT10/UNITS10/GRADE10 into subject-grade rows
  -> sends rows to PHP API
  -> PHP API checks MySQL using cfcissmsdb tables
  -> Flutter marks Existing, Missing, Grade differs, or Units differ
```

Direct Flutter Web to MySQL is not recommended because it exposes database credentials in the browser. PHP keeps the MySQL credentials on the local/server side.

## Folders

```text
flutter_grades_checker/        Flutter Web app
api/grades_checker_api/        PHP API for WAMP or XAMPP
sql/                           optional sample API request
README.md                      setup guide
```

## Target database tables

The checker is focused on:

```text
tbl_period
tbl_student
tbl_course
tbl_students_grades
tbl_subject
```

Default matching:

```text
Student: Excel ID OR FIRST NAME + LAST NAME
Subject: Excel SUBJECT# = tbl_subject.subject_code
Period: Period ID if supplied, otherwise Academic Year + Semester
Grade record: tbl_students_grades.sg_student_id + sg_subject_id + sg_period_id
```

It also compares units:

```text
Excel UNITS# vs tbl_students_grades.sg_credits
Excel UNITS# vs tbl_subject.subject_units
```

## Setup for WAMP or XAMPP

1. Import `cfcissmsdb.sql` into MySQL through phpMyAdmin.
2. Copy this folder:

```text
api/grades_checker_api
```

For WAMP, paste it into:

```text
C:\wamp64\www\grades_checker_api
```

For XAMPP, paste it into:

```text
C:\xampp\htdocs\grades_checker_api
```

3. Edit:

```text
grades_checker_api/config.php
```

Common local defaults:

```php
const DB_HOST = '127.0.0.1';
const DB_PORT = '3306';
const DB_NAME = 'cfcissmsdb';
const DB_USER = 'root';
const DB_PASS = '';
```

If your XAMPP/WAMP MySQL has a password or uses a different port, change it there only.

## Test API URLs

Open these in the browser:

```text
http://localhost/grades_checker_api/ping.php
http://localhost/grades_checker_api/periods.php
http://localhost/grades_checker_api/inspect_schema.php
```

If Apache uses another port:

```text
http://localhost:8080/grades_checker_api/ping.php
```

## Run Flutter Web

From the Flutter project folder:

```bash
cd flutter_grades_checker
flutter pub get
flutter run -d chrome
```

Or fixed port:

```bash
flutter run -d web-server --web-port 53902
```

## Using the app

1. Confirm the API endpoint is correct, usually:

```text
http://localhost/grades_checker_api/check_grades.php
```

2. Enter Academic Year and Semester, for example:

```text
Academic Year: 2019-2020
Semester: 1ST SEM
```

3. If period text matching is not exact, open `periods.php`, copy the correct `period_id`, and paste it in the Flutter `Period ID` field.
4. Upload `HEMIS - Promotional List - 2019-2020-1ST SEM UNO.xlsx`.
5. Click **Check Database**.

## Student matching mode

In `config.php`:

```php
const STUDENT_MATCH_MODE = 'id_or_name';
```

Options:

```text
id_or_name  = safest default; checks Excel ID first, then first name + last name
name_only   = ignores Excel ID and checks first name + last name only
id_only     = checks Excel ID only
```

## Notes

- This starter does not insert or update grades. It only cross-checks and displays results.
- If multiple students share the same first and last name, use `id_or_name` or `id_only`.
- If `period_id` is supplied, the app ignores academic-year/semester text and uses the exact period ID.
