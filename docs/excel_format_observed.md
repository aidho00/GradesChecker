# Observed Excel Format

Workbook: `HEMIS - Promotional List - 2019-2020-1ST SEM UNO.xlsx`

Observed headers:

```text
ID, LAST NAME, FIRST NAME, MIDDLE NAME, COURSE, YEARLEVEL, BIRTHDATE,
SUBJECT1, UNITS1, GRADE1,
SUBJECT2, UNITS2, GRADE2,
...
SUBJECT10, UNITS10, GRADE10,
REMARKS, TOTALUNITS, TOTALSUBJECT, GRADESTATUS
```

The Flutter parser expands each student row into multiple subject-grade rows.
For example, a student with 9 subjects becomes 9 rows to check against MySQL.
