# Observed Excel Format

Uploaded file inspected:

`HEMIS - Promotional List - 2019-2020-1ST SEM UNO.xlsx`

Worksheet:

`Sheet1`

Used range:

`A1:AS4046`

Header row fields include:

- `ID`
- `LAST NAME`
- `FIRST NAME`
- `MIDDLE NAME`
- `EXTENSION`
- `SEX`
- `NATIONALITY`
- `COURSE`
- `MAJOR`
- `YEARLEVEL`
- `BIRTHDATE`
- repeated subject grade groups:
  - `SUBJECT1`, `UNITS1`, `GRADE1`
  - ...
  - `SUBJECT10`, `UNITS10`, `GRADE10`
- `REMARKS`
- `TOTALUNITS`
- `TOTALSUBJECT`
- `GRADESTATUS`

The Flutter parser converts each non-empty subject group into one grade-check row.
Example: one student row with 6 subjects becomes 6 grade-check rows.
