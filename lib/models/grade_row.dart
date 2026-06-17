class GradeRow {
  GradeRow({
    required this.excelRowNumber,
    required this.subjectNo,
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
    this.studentFound,
    this.subjectFound,
    this.gradeMatches,
    this.unitsMatch,
    this.databaseGrade,
    this.databaseCredits,
    this.subjectUnits,
    this.databaseCourse,
    this.subjectDescription,
    this.databaseReference,
    this.message,
  });

  final int excelRowNumber;
  final int subjectNo;
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
  bool? studentFound;
  bool? subjectFound;
  bool? gradeMatches;
  bool? unitsMatch;
  String? databaseGrade;
  String? databaseCredits;
  String? subjectUnits;
  String? databaseCourse;
  String? subjectDescription;
  String? databaseReference;
  String? message;

  String get studentName {
    final last = lastName.trim();
    final first = firstName.trim();
    final middle = middleName.trim();
    final parts = <String>[];
    if (last.isNotEmpty) parts.add(last);
    if (first.isNotEmpty) parts.add(first);
    if (middle.isNotEmpty) parts.add(middle);
    return parts.isEmpty ? studentId : parts.join(', ');
  }

  String get statusLabel {
    if (studentFound == false) return 'Student not found';
    if (subjectFound == false) return 'Subject not found';
    if (!existsInDatabase && studentFound == null && subjectFound == null) return 'Unchecked';
    if (!existsInDatabase) return 'Missing grade';
    if (gradeMatches == false && unitsMatch == false) return 'Grade + Units differ';
    if (gradeMatches == false) return 'Grade differs';
    if (unitsMatch == false) return 'Units differ';
    return 'Exists';
  }

  Map<String, dynamic> toApiJson() {
    return {
      'excel_row_number': excelRowNumber,
      'subject_no': subjectNo,
      'student_id': studentId,
      'last_name': lastName,
      'first_name': firstName,
      'middle_name': middleName,
      'course': course,
      'year_level': yearLevel,
      'subject_code': subjectCode,
      'units': units,
      'excel_grade': excelGrade,
      'period_id': periodId,
      'school_year': schoolYear,
      'semester': semester,
    };
  }

  GradeRow copyWithCheckResult(Map<String, dynamic> json) {
    return GradeRow(
      excelRowNumber: excelRowNumber,
      subjectNo: subjectNo,
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
      studentFound: json['student_found'] is bool ? json['student_found'] as bool : null,
      subjectFound: json['subject_found'] is bool ? json['subject_found'] as bool : null,
      gradeMatches: json['grade_matches'] is bool ? json['grade_matches'] as bool : null,
      unitsMatch: json['units_match'] is bool ? json['units_match'] as bool : null,
      databaseGrade: json['database_grade']?.toString(),
      databaseCredits: json['database_credits']?.toString(),
      subjectUnits: json['subject_units']?.toString(),
      databaseCourse: json['database_course']?.toString(),
      subjectDescription: json['subject_description']?.toString(),
      databaseReference: json['database_reference']?.toString(),
      message: json['message']?.toString(),
    );
  }
}
