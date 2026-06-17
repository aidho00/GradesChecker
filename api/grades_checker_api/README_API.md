# Grades Checker API

Endpoints:

- `ping.php` - connection test
- `periods.php` - returns academic periods from `tbl_period`
- `parse_excel.php` - parses uploaded HEMIS `.xlsx` using pure PHP ZIP/XML reading
- `check_grades.php` - checks parsed subject-grade rows against HEMIS tables in batches
- `export_excel.php` - generates formatted Excel-compatible `.xls` export
- `inspect_schema.php` - basic schema helper

Configure database connection in `config.php`.
