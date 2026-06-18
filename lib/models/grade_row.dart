class DatabaseGradeRecord {
  const DatabaseGradeRecord({
    required this.reference,
    required this.grade,
    required this.credits,
    required this.subjectUnits,
    required this.courseCode,
    required this.subjectDescription,
    required this.gradeStatus,
    required this.classId,
    this.periodId = '',
    this.periodLabel = '',
  });

  final String reference;
  final String grade;
  final String credits;
  final String subjectUnits;
  final String courseCode;
  final String subjectDescription;
  final String gradeStatus;
  final String classId;
  final String periodId;
  final String periodLabel;

  factory DatabaseGradeRecord.fromJson(Map<String, dynamic> json) {
    return DatabaseGradeRecord(
      reference: json['reference']?.toString() ?? '',
      grade: json['grade']?.toString() ?? '',
      credits: json['credits']?.toString() ?? '',
      subjectUnits: json['subject_units']?.toString() ?? '',
      courseCode: json['course_code']?.toString() ?? '',
      subjectDescription: json['subject_description']?.toString() ?? '',
      gradeStatus: json['grade_status']?.toString() ?? '',
      classId: json['class_id']?.toString() ?? '',
      periodId: json['period_id']?.toString() ?? '',
      periodLabel: json['period_label']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toExportJson() {
    return {
      'reference': reference,
      'grade': grade,
      'credits': credits,
      'subject_units': subjectUnits,
      'course_code': courseCode,
      'subject_description': subjectDescription,
      'grade_status': gradeStatus,
      'class_id': classId,
      'period_id': periodId,
      'period_label': periodLabel,
    };
  }
}


class SubjectCatalogRecord {
  const SubjectCatalogRecord({
    required this.subjectId,
    required this.subjectCode,
    required this.subjectDescription,
    required this.subjectUnits,
  });

  final String subjectId;
  final String subjectCode;
  final String subjectDescription;
  final String subjectUnits;

  factory SubjectCatalogRecord.fromJson(Map<String, dynamic> json) {
    return SubjectCatalogRecord(
      subjectId: json['subject_id']?.toString() ?? '',
      subjectCode: json['subject_code']?.toString() ?? '',
      subjectDescription: json['subject_description']?.toString() ?? '',
      subjectUnits: json['subject_units']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toExportJson() {
    return {
      'subject_id': subjectId,
      'subject_code': subjectCode,
      'subject_description': subjectDescription,
      'subject_units': subjectUnits,
    };
  }
}

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
    this.excelSubjectDescription = '',
    this.birthDate = '',
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
    this.databaseMatches = const <DatabaseGradeRecord>[],
    this.otherPeriodMatches = const <DatabaseGradeRecord>[],
    this.subjectVariants = const <SubjectCatalogRecord>[],
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
  final String excelSubjectDescription;
  final String birthDate;
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
  List<DatabaseGradeRecord> databaseMatches;
  List<DatabaseGradeRecord> otherPeriodMatches;
  List<SubjectCatalogRecord> subjectVariants;

  factory GradeRow.fromParsedJson(Map<String, dynamic> json) {
    return GradeRow(
      excelRowNumber: int.tryParse(json['excel_row_number']?.toString() ?? '') ?? 0,
      subjectNo: int.tryParse(json['subject_no']?.toString() ?? '') ?? 0,
      studentId: json['student_id']?.toString() ?? '',
      lastName: json['last_name']?.toString() ?? '',
      firstName: json['first_name']?.toString() ?? '',
      middleName: json['middle_name']?.toString() ?? '',
      course: json['course']?.toString() ?? '',
      yearLevel: json['year_level']?.toString() ?? '',
      subjectCode: json['subject_code']?.toString() ?? '',
      excelSubjectDescription: json['subject_description']?.toString() ?? json['excel_subject_description']?.toString() ?? '',
      birthDate: json['birthdate']?.toString() ?? json['birth_date']?.toString() ?? '',
      units: json['units']?.toString() ?? '',
      excelGrade: json['excel_grade']?.toString() ?? '',
      schoolYear: json['school_year']?.toString() ?? '',
      semester: json['semester']?.toString() ?? '',
      periodId: json['period_id']?.toString() ?? '',
    );
  }

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
    if (databaseMatches.length > 1 && gradeMatches == true && unitsMatch != false) return 'Exists (${databaseMatches.length} DB grades)';
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
      'subject_description': excelSubjectDescription,
      'birthdate': birthDate,
      'units': units,
      'excel_grade': excelGrade,
      'period_id': periodId,
      'school_year': schoolYear,
      'semester': semester,
    };
  }

  Map<String, dynamic> toExportJson() {
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
      'excel_subject_description': excelSubjectDescription,
      'birthdate': birthDate,
      'units': units,
      'excel_grade': excelGrade,
      'status': statusLabel,
      'exists': existsInDatabase,
      'student_found': studentFound,
      'subject_found': subjectFound,
      'grade_matches': gradeMatches,
      'units_match': unitsMatch,
      'database_grade': databaseGrade ?? '',
      'database_credits': databaseCredits ?? '',
      'subject_units': subjectUnits ?? '',
      'database_course': databaseCourse ?? '',
      'subject_description': subjectDescription ?? '',
      'database_reference': databaseReference ?? '',
      'message': message ?? '',
      'database_matches': databaseMatches.map((match) => match.toExportJson()).toList(),
      'other_period_matches': otherPeriodMatches.map((match) => match.toExportJson()).toList(),
      'subject_variants': subjectVariants.map((subject) => subject.toExportJson()).toList(),
    };
  }

  GradeRow copyWithCheckResult(Map<String, dynamic> json) {
    final matches = (json['matching_grades'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(DatabaseGradeRecord.fromJson)
        .toList(growable: false);
    final otherMatches = (json['other_period_grades'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(DatabaseGradeRecord.fromJson)
        .toList(growable: false);
    final subjectVariants = (json['subject_variants'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(SubjectCatalogRecord.fromJson)
        .toList(growable: false);

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
      excelSubjectDescription: excelSubjectDescription,
      birthDate: birthDate,
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
      databaseMatches: matches,
      otherPeriodMatches: otherMatches,
      subjectVariants: subjectVariants,
    );
  }
}
