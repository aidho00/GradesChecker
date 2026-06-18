# UNO to SMS Grade Checker

Web/desktop Flutter + PHP/Database checker with simple access login for comparing legacy UNO promotional-list UNO files against current SMS grade records.

## What this version does

- Streams the uploaded `.xlsx` to the PHP API instead of loading/decoding the full workbook inside Flutter Web.
- Parses the workbook on the PHP API to reduce browser upload/parse freezes.
- Validates the uploaded UNO as a UNO promotional-list style file before accepting it.
- Supports the updated UNO subject description columns: `SUBJECTDESC1` to `SUBJECTDESC10`.
- Supports optional birthdate columns: `BIRTHDATE`, `BIRTH DATE`, or `DOB`.
- Checks grade records in smaller batches against:
  - `tbl_period`
  - `tbl_student`
  - `course records`
  - `tbl_subject`
  - `tbl_students_grades`
- Displays one compact table row per student with `Subject 1` to `Subject 10` across the row.
- Shows the UNO subject description inside the subject cell and the subject inspection modal.
- Ranks same-code `tbl_subject` choices using UNO subject description and units for better subject comparison.
- Uses cached student grouping and pagination to reduce table lag.
- Supports 50, 100, 150, and 250 rows per page.
- Provides pagination controls at the top and bottom of the table.
- Keeps the horizontal table position controllable using a bottom sticky rounded-rectangle scroll control.
- Lets you tap a missing student row to open a profile creation form directly.
- Profile creation includes editable student details, course selector from `course records`, year level, gender, and birthdate.
- Year level is normalized to `1st Year`, `2nd Year`, `3rd Year`, or `4th Year`; other values default to `1st Year`.
- Saves profile fields to `tbl_student`, including `s_course_id`, `s_gender`, and `s_dob` when those columns exist.
- Lets you tap a subject cell to inspect all `tbl_subject` records with the same subject code, including different descriptions/units, selected-period DB grades, duplicate grades, and grades found in other academic periods.
- Exports a formatted UNO report-compatible `.xls` file with status colors and DB comparison columns.
- Generates an overall interpretation after the table.

## Simple login

This version includes an access-only login using the existing `tbl_user_account` table. No audit log is created.

By default, any active SMS user account can sign in. To limit access to selected users only, edit:

```text
api/grades_checker_api/config.php
```

Then add allowed IDs or usernames:

```php
const GRADE_CHECKER_ALLOWED_USER_IDS = [1, 2];
const GRADE_CHECKER_ALLOWED_USERNAMES = ['registrar', 'mis'];
```

For intranet/production use, also change `GRADE_CHECKER_TOKEN_SECRET` in `config.php`.

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
```

`periods.php` and other endpoints require login from the Flutter app.

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

The export uses an UNO report-compatible HTML `.xls` file so formatting works without requiring Composer, PhpSpreadsheet, or PHP ZipArchive.

## Latest profile modal update

- Profile creation modal was reformatted into clear sections.
- Course selection now includes a searchable course field before the `course records` dropdown.
- Birthdate from UNO is normalized to `YYYY-MM-DD` when possible, including UNO serial-date values.
- Birthdate in the profile form now uses a date picker and saves as `YYYY-MM-DD` to `tbl_student.s_dob`.

- Added `insert_grade.php` to insert a missing grade to SMS from the subject inspection modal.

- Insert grade button appears only for missing grades; update grade appears only when UNO and SMS grade/units differ.
- Student profile creation uses safer legacy defaults to avoid save errors on required SMS profile fields.
