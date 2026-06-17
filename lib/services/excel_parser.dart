import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../models/grade_row.dart';

class HemisExcelParser {
  static List<GradeRow> parsePromotionalList({
    required Uint8List bytes,
    required String schoolYear,
    required String semester,
    required String periodId,
  }) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      throw const FormatException('The Excel file has no worksheets.');
    }

    final sheetName = excel.tables.keys.first;
    final sheet = excel.tables[sheetName];
    if (sheet == null || sheet.rows.isEmpty) {
      throw const FormatException('The first worksheet is empty.');
    }

    final headerRow = sheet.rows.first;
    final headers = <String, int>{};
    for (var i = 0; i < headerRow.length; i++) {
      final key = _normalizeHeader(_cellText(headerRow[i]));
      if (key.isNotEmpty) headers[key] = i;
    }

    String fromRow(List<Data?> row, String header) {
      final index = headers[_normalizeHeader(header)];
      if (index == null || index >= row.length) return '';
      return _cellText(row[index]);
    }

    final parsed = <GradeRow>[];

    for (var rowIndex = 1; rowIndex < sheet.rows.length; rowIndex++) {
      final row = sheet.rows[rowIndex];
      final studentId = fromRow(row, 'ID');
      final lastName = fromRow(row, 'LAST NAME');
      final firstName = fromRow(row, 'FIRST NAME');

      if (studentId.trim().isEmpty &&
          lastName.trim().isEmpty &&
          firstName.trim().isEmpty) {
        continue;
      }

      final middleName = fromRow(row, 'MIDDLE NAME');
      final course = fromRow(row, 'COURSE');
      final yearLevel = fromRow(row, 'YEARLEVEL');

      for (var subjectNo = 1; subjectNo <= 10; subjectNo++) {
        final subject = fromRow(row, 'SUBJECT$subjectNo');
        if (subject.trim().isEmpty) continue;

        parsed.add(
          GradeRow(
            excelRowNumber: rowIndex + 1,
            studentId: studentId,
            lastName: lastName,
            firstName: firstName,
            middleName: middleName,
            course: course,
            yearLevel: yearLevel,
            subjectCode: subject,
            units: fromRow(row, 'UNITS$subjectNo'),
            excelGrade: fromRow(row, 'GRADE$subjectNo'),
            schoolYear: schoolYear,
            semester: semester,
            periodId: periodId,
          ),
        );
      }
    }

    return parsed;
  }

  static String _normalizeHeader(String value) {
    return value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  static String _cellText(Data? cell) {
    final value = cell?.value;
    if (value == null) return '';

    try {
      final dynamic dynamicValue = value;
      final dynamic inner = dynamicValue.value;
      if (inner == null) return '';

      try {
        final dynamic text = inner.text;
        if (text != null) return _clean(text.toString());
      } catch (_) {
        // Numeric values usually do not have a text property.
      }

      return _clean(inner.toString());
    } catch (_) {
      return _clean(value.toString());
    }
  }

  static String _clean(String value) {
    final cleaned = value.trim();
    if (RegExp(r'^-?\d+\.0$').hasMatch(cleaned)) {
      return cleaned.substring(0, cleaned.length - 2);
    }
    return cleaned;
  }
}
