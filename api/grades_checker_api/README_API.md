# Grades Checker API

Copy this folder to either:

```text
C:\xampp\htdocs\grades_checker_api
```

or:

```text
C:\wamp64\www\grades_checker_api
```

Endpoints:

- `ping.php` - connection test
- `periods.php` - loads academic periods from `tbl_period`
- `inspect_schema.php` - quick schema check
- `check_grades.php` - batch grade cross-check endpoint

`check_grades.php` accepts up to 500 subject-grade records per request. The Flutter app sends large files in batches.
