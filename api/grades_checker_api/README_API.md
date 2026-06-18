# Grades Checker API

Endpoints:

- `ping.php` - connection test
- `login.php` - access-only login using existing `tbl_user_account`
- `periods.php` - returns academic periods from `tbl_period`
- `courses.php` - returns course choices from `tbl_course`
- `parse_excel.php` - parses uploaded UNO promotional-list `.xlsx` using pure PHP ZIP/XML reading; supports `SUBJECTDESC1..SUBJECTDESC10` and `BIRTHDATE`/`BIRTH DATE`/`DOB`
- `check_grades.php` - checks parsed subject-grade rows against SMS tables in batches and ranks same-code subjects by UNO description/units
- `create_student_profile.php` - creates a basic `tbl_student` profile from a missing UNO student row, including course, year level, gender, and birthdate
- `export_excel.php` - generates formatted UNO report-compatible `.xls` export
- `inspect_schema.php` - basic schema helper

Configure database connection and optional access allow-list in `config.php`.

- Added `insert_grade.php` to insert a missing grade to SMS from the subject inspection modal.
