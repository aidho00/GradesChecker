import 'dart:async';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../models/grade_row.dart';

typedef ExcelParseProgress = void Function(String phase, int processed, int total);

class HemisExcelParser {
  static Future<List<GradeRow>> parsePromotionalListAsync({
    required Uint8List bytes,
    required String schoolYear,
    required String semester,
    required String periodId,
    ExcelParseProgress? onProgress,
  }) async {
    onProgress?.call('Preparing workbook reader', 0, 0);
    await Future<void>.delayed(Duration.zero);

    // The excel package decodes the workbook synchronously. Keep this single step
    // small in the UI and make the row parsing/checking parts chunked below.
    onProgress?.call('Decoding workbook', 0, 0);
    final excel = Excel.decodeBytes(bytes);
    await Future<void>.delayed(Duration.zero);

    if (excel.tables.isEmpty) {
      throw const FormatException('The Excel file has no worksheets.');
    }

    final sheetName = excel.tables.keys.first;
    final sheet = excel.tables[sheetName];
    if (sheet == null || sheet.rows.isEmpty) {
      throw const FormatException('The first worksheet is empty.');
    }

    final rows = sheet.rows;
    final headerRow = rows.first;
    final headers = <String, int>{};
    for (var i = 0; i < headerRow.length; i++) {
      final key = _normalizeHeader(_cellText(headerRow[i]));
      if (key.isNotEmpty) headers[key] = i;
    }

    final idIndex = headers[_normalizeHeader('ID')];
    final lastNameIndex = headers[_normalizeHeader('LAST NAME')];
    final firstNameIndex = headers[_normalizeHeader('FIRST NAME')];
    final middleNameIndex = headers[_normalizeHeader('MIDDLE NAME')];
    final courseIndex = headers[_normalizeHeader('COURSE')];
    final yearLevelIndex = headers[_normalizeHeader('YEARLEVEL')];

    final subjectSlots = <_SubjectSlot>[];
    for (var subjectNo = 1; subjectNo <= 10; subjectNo++) {
      subjectSlots.add(
        _SubjectSlot(
          subjectNo: subjectNo,
          subjectIndex: headers[_normalizeHeader('SUBJECT$subjectNo')],
          unitsIndex: headers[_normalizeHeader('UNITS$subjectNo')],
          gradeIndex: headers[_normalizeHeader('GRADE$subjectNo')],
        ),
      );
    }

    final parsed = <GradeRow>[];
    final totalExcelRows = rows.length > 1 ? rows.length - 1 : 0;
    onProgress?.call('Parsing Excel rows', 0, totalExcelRows);

    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      final studentId = _fromIndex(row, idIndex);
      if (studentId.trim().isNotEmpty) {
        final lastName = _fromIndex(row, lastNameIndex);
        final firstName = _fromIndex(row, firstNameIndex);
        final middleName = _fromIndex(row, middleNameIndex);
        final course = _fromIndex(row, courseIndex);
        final yearLevel = _fromIndex(row, yearLevelIndex);

        for (final slot in subjectSlots) {
          final subject = _fromIndex(row, slot.subjectIndex);
          if (subject.trim().isEmpty) continue;

          parsed.add(
            GradeRow(
              excelRowNumber: rowIndex + 1,
              subjectNo: slot.subjectNo,
              studentId: studentId,
              lastName: lastName,
              firstName: firstName,
              middleName: middleName,
              course: course,
              yearLevel: yearLevel,
              subjectCode: subject,
              units: _fromIndex(row, slot.unitsIndex),
              excelGrade: _fromIndex(row, slot.gradeIndex),
              schoolYear: schoolYear,
              semester: semester,
              periodId: periodId,
            ),
          );
        }
      }

      // Updating every row is slower and can cause UI jank on large files.
      // Every 100 rows keeps the browser responsive without too many rebuilds.
      final processed = rowIndex;
      if (processed % 100 == 0 || rowIndex == rows.length - 1) {
        onProgress?.call('Parsing Excel rows', processed, totalExcelRows);
        await Future<void>.delayed(Duration.zero);
      }
    }

    onProgress?.call('Parsed subject-grade records', parsed.length, parsed.length);
    return parsed;
  }

  static String _fromIndex(List<Data?> row, int? index) {
    if (index == null || index < 0 || index >= row.length) return '';
    return _cellText(row[index]);
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
        // Most numeric values do not have a text property.
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

class _SubjectSlot {
  const _SubjectSlot({
    required this.subjectNo,
    required this.subjectIndex,
    required this.unitsIndex,
    required this.gradeIndex,
  });

  final int subjectNo;
  final int? subjectIndex;
  final int? unitsIndex;
  final int? gradeIndex;
}
