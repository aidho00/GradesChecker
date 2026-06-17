class GradeRow {
  GradeRow({
    required this.excelRowNumber,
    required this.studentId,
    required this.lastName,
    required this.firstName,
    required this.middleName,
    required this.course,
    required this.yearLevel,
    required this.subjectCode,
    required this.units,
    required this.excelGrade,
    required this.schoolYear,
    required this.semester,
    required this.periodId,
    this.existsInDatabase = false,
    this.gradeMatches,
    this.unitsMatchDatabase,
    this.unitsMatchSubjectMaster,
    this.databaseGrade,
    this.databaseUnits,
    this.subjectUnits,
    this.databaseReference,
    this.databaseStudentId,
    this.databaseSubjectId,
    this.periodLabel,
    this.message,
  });

  final int excelRowNumber;
  final String studentId;
  final String lastName;
  final String firstName;
  final String middleName;
  final String course;
  final String yearLevel;
  final String subjectCode;
  final String units;
  final String excelGrade;
  final String schoolYear;
  final String semester;
  final String periodId;

  bool existsInDatabase;
  bool? gradeMatches;
  bool? unitsMatchDatabase;
  bool? unitsMatchSubjectMaster;
  String? databaseGrade;
  String? databaseUnits;
  String? subjectUnits;
  String? databaseReference;
  String? databaseStudentId;
  String? databaseSubjectId;
  String? periodLabel;
  String? message;

  String get studentName {
    final name = [lastName, firstName, middleName]
        .where((item) => item.trim().isNotEmpty)
        .join(', ');
    return name.isEmpty ? studentId : name;
  }

  bool get hasAnyUnitsDifference =>
      unitsMatchDatabase == false || unitsMatchSubjectMaster == false;

  String get statusLabel {
    if (!existsInDatabase && gradeMatches == null) return 'Unchecked / Missing';
    if (!existsInDatabase) return 'Missing';
    if (gradeMatches == false && hasAnyUnitsDifference) return 'Grade + units differ';
    if (gradeMatches == false) return 'Grade differs';
    if (hasAnyUnitsDifference) return 'Units differ';
    return 'Exists';
  }

  Map<String, dynamic> toApiJson() {
    return {
      'excel_row_number': excelRowNumber,
      'student_id': studentId,
      'last_name': lastName,
      'first_name': firstName,
      'middle_name': middleName,
      'course': course,
      'year_level': yearLevel,
      'subject_code': subjectCode,
      'units': units,
      'excel_grade': excelGrade,
      'school_year': schoolYear,
      'semester': semester,
      'period_id': periodId,
    };
  }

  GradeRow copyWithCheckResult(Map<String, dynamic> json) {
    bool? boolField(String key) => json[key] is bool ? json[key] as bool : null;

    return GradeRow(
      excelRowNumber: excelRowNumber,
      studentId: studentId,
      lastName: lastName,
      firstName: firstName,
      middleName: middleName,
      course: course,
      yearLevel: yearLevel,
      subjectCode: subjectCode,
      units: units,
      excelGrade: excelGrade,
      schoolYear: schoolYear,
      semester: semester,
      periodId: periodId,
      existsInDatabase: json['exists'] == true,
      gradeMatches: boolField('grade_matches'),
      unitsMatchDatabase: boolField('units_match_database'),
      unitsMatchSubjectMaster: boolField('units_match_subject_master'),
      databaseGrade: json['database_grade']?.toString(),
      databaseUnits: json['database_units']?.toString(),
      subjectUnits: json['subject_units']?.toString(),
      databaseReference: json['database_reference']?.toString(),
      databaseStudentId: json['database_student_id']?.toString(),
      databaseSubjectId: json['database_subject_id']?.toString(),
      periodLabel: json['period_label']?.toString(),
      message: json['message']?.toString(),
    );
  }
}
