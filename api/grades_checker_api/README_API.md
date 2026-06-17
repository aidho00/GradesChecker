# Grades Checker PHP API

Copy this whole `grades_checker_api` folder to either:

```text
C:\wamp64\www\grades_checker_api
```

or:

```text
C:\xampp\htdocs\grades_checker_api
```

Then open these in a browser:

```text
http://localhost/grades_checker_api/ping.php
http://localhost/grades_checker_api/periods.php
http://localhost/grades_checker_api/inspect_schema.php
```

The Flutter app calls:

```text
http://localhost/grades_checker_api/check_grades.php
```

If Apache uses another port, use that in Flutter, for example:

```text
http://localhost:8080/grades_checker_api/check_grades.php
```

## Matching logic

The API checks rows from Excel against:

- `tbl_student`
- `tbl_course`
- `tbl_period`
- `tbl_subject`
- `tbl_students_grades`

Default matching:

```text
student: Excel ID OR first name + last name
subject: Excel SUBJECT# = tbl_subject.subject_code
period: period_id if supplied, otherwise academic year + semester text
record: tbl_students_grades.sg_student_id + sg_subject_id + sg_period_id
```

Returned comparisons:

- Excel grade vs `tbl_students_grades.sg_grade`
- Excel units vs `tbl_students_grades.sg_credits`
- Excel units vs `tbl_subject.subject_units`

Edit `config.php` to switch student matching to `name_only` or `id_only`.
