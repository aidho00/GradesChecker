<?php
require_once __DIR__ . '/bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    json_response(['ok' => false, 'message' => 'POST request required.'], 405);
}

function find_subject(PDO $pdo, array $row): ?array
{
    static $stmt = null;
    if ($stmt === null) {
        $stmt = $pdo->prepare(
            'SELECT subject_id, subject_code, subject_description, subject_units
             FROM tbl_subject
             WHERE ' . sql_norm('subject_code') . ' = :subject_code
             LIMIT 1'
        );
    }
    $stmt->execute(['subject_code' => normalize_text($row['subject_code'] ?? '')]);
    $subject = $stmt->fetch();
    return $subject ?: null;
}

function find_student(PDO $pdo, array $row): ?array
{
    $studentId = trim((string)($row['student_id'] ?? ''));
    $firstName = normalize_text($row['first_name'] ?? '');
    $lastName = normalize_text($row['last_name'] ?? '');

    if (STUDENT_MATCH_MODE !== 'name_only' && $studentId !== '') {
        static $byId = null;
        if ($byId === null) {
            $byId = $pdo->prepare(
                'SELECT s.s_id_no, s.s_fn, s.s_mn, s.s_ln, s.s_course_id,
                        c.course_code, c.course_name
                 FROM tbl_student s
                 LEFT JOIN tbl_course c ON c.course_id = s.s_course_id
                 WHERE s.s_id_no = :student_id
                 LIMIT 1'
            );
        }
        $byId->execute(['student_id' => $studentId]);
        $student = $byId->fetch();
        if ($student) return $student;
    }

    if (STUDENT_MATCH_MODE !== 'id_only' && $firstName !== '' && $lastName !== '') {
        static $byName = null;
        if ($byName === null) {
            $byName = $pdo->prepare(
                'SELECT s.s_id_no, s.s_fn, s.s_mn, s.s_ln, s.s_course_id,
                        c.course_code, c.course_name
                 FROM tbl_student s
                 LEFT JOIN tbl_course c ON c.course_id = s.s_course_id
                 WHERE ' . sql_norm('s.s_fn') . ' = :first_name
                   AND ' . sql_norm('s.s_ln') . ' = :last_name
                 LIMIT 2'
            );
        }
        $byName->execute(['first_name' => $firstName, 'last_name' => $lastName]);
        $students = $byName->fetchAll();
        if (count($students) === 1) return $students[0];
        if (count($students) > 1) {
            $students[0]['_ambiguous'] = true;
            return $students[0];
        }
    }

    return null;
}

function period_where_and_params(array $row): array
{
    $periodId = trim((string)($row['period_id'] ?? ''));
    $academicYear = normalize_text($row['school_year'] ?? '');
    $semester = normalize_text($row['semester'] ?? '');
    $combinedA = normalize_text($academicYear . '-' . $semester);
    $combinedB = normalize_text($academicYear . ' ' . $semester);

    if ($periodId !== '') {
        return [
            ' AND g.sg_period_id = :period_id ',
            ['period_id' => $periodId],
            'Period ID: ' . $periodId,
        ];
    }

    if (!ALLOW_PERIOD_TEXT_FALLBACK || ($academicYear === '' && $semester === '')) {
        return ['', [], 'No period filter'];
    }

    return [
        ' AND (
              (' . sql_norm('p.period_name') . ' = :academic_year AND ' . sql_norm('p.period_semester') . ' = :semester)
              OR ' . sql_norm("CONCAT(p.period_name, '-', p.period_semester)") . ' = :combined_a
              OR ' . sql_norm("CONCAT(p.period_name, ' ', p.period_semester)") . ' = :combined_b
          ) ',
        [
            'academic_year' => $academicYear,
            'semester' => $semester,
            'combined_a' => $combinedA,
            'combined_b' => $combinedB,
        ],
        'Period text: ' . trim(($row['school_year'] ?? '') . ' ' . ($row['semester'] ?? '')),
    ];
}

function check_one_row(PDO $pdo, array $row): array
{
    $subject = find_subject($pdo, $row);
    $student = find_student($pdo, $row);
    $excelGrade = $row['excel_grade'] ?? '';
    $excelUnits = $row['units'] ?? '';

    if (!$student) {
        return [
            'exists' => false,
            'grade_matches' => null,
            'units_match_database' => null,
            'units_match_subject_master' => $subject ? bool_or_null(normalize_units($excelUnits) === normalize_units($subject['subject_units'] ?? ''), $excelUnits !== '') : null,
            'database_grade' => null,
            'database_units' => null,
            'subject_units' => $subject['subject_units'] ?? null,
            'database_reference' => null,
            'database_student_id' => null,
            'database_subject_id' => $subject['subject_id'] ?? null,
            'period_label' => null,
            'message' => 'Student not found by configured match mode.',
        ];
    }

    if (($student['_ambiguous'] ?? false) === true) {
        return [
            'exists' => false,
            'grade_matches' => null,
            'units_match_database' => null,
            'units_match_subject_master' => $subject ? bool_or_null(normalize_units($excelUnits) === normalize_units($subject['subject_units'] ?? ''), $excelUnits !== '') : null,
            'database_grade' => null,
            'database_units' => null,
            'subject_units' => $subject['subject_units'] ?? null,
            'database_reference' => null,
            'database_student_id' => $student['s_id_no'] ?? null,
            'database_subject_id' => $subject['subject_id'] ?? null,
            'period_label' => null,
            'message' => 'Multiple students have the same first name and last name. Use Student ID or set STUDENT_MATCH_MODE=id_or_name.',
        ];
    }

    if (!$subject) {
        return [
            'exists' => false,
            'grade_matches' => null,
            'units_match_database' => null,
            'units_match_subject_master' => null,
            'database_grade' => null,
            'database_units' => null,
            'subject_units' => null,
            'database_reference' => null,
            'database_student_id' => $student['s_id_no'] ?? null,
            'database_subject_id' => null,
            'period_label' => null,
            'message' => 'Subject code not found in tbl_subject.',
        ];
    }

    [$periodWhere, $periodParams] = period_where_and_params($row);

    $courseWhere = '';
    $courseParams = [];
    if (REQUIRE_COURSE_MATCH) {
        $courseText = normalize_text($row['course'] ?? '');
        if ($courseText !== '') {
            $courseWhere = ' AND (' . sql_norm('c.course_code') . ' = :course_text_code OR ' . sql_norm('c.course_name') . ' = :course_text_name) ';
            $courseParams['course_text_code'] = $courseText;
            $courseParams['course_text_name'] = $courseText;
        }
    }

    $sql = '
        SELECT
            g.sg_id AS database_reference,
            g.sg_student_id,
            g.sg_subject_id,
            g.sg_period_id,
            g.sg_grade AS database_grade,
            g.sg_credits AS database_units,
            g.sg_grade_status,
            s.s_id_no,
            s.s_fn,
            s.s_mn,
            s.s_ln,
            c.course_code,
            c.course_name,
            sub.subject_code,
            sub.subject_units,
            p.period_id,
            CONCAT(p.period_name, "-", p.period_semester) AS period_label
        FROM tbl_students_grades g
        INNER JOIN tbl_student s ON s.s_id_no = g.sg_student_id
        INNER JOIN tbl_subject sub ON sub.subject_id = g.sg_subject_id
        INNER JOIN tbl_period p ON p.period_id = g.sg_period_id
        LEFT JOIN tbl_course c ON c.course_id = s.s_course_id
        WHERE g.sg_student_id = :student_id
          AND g.sg_subject_id = :subject_id
          ' . $periodWhere . '
          ' . $courseWhere . '
        ORDER BY g.sg_id DESC
        LIMIT 5';

    $stmt = $pdo->prepare($sql);
    $params = array_merge([
        'student_id' => $student['s_id_no'],
        'subject_id' => $subject['subject_id'],
    ], $periodParams, $courseParams);
    $stmt->execute($params);
    $matches = $stmt->fetchAll();

    if (count($matches) === 0) {
        return [
            'exists' => false,
            'grade_matches' => false,
            'units_match_database' => null,
            'units_match_subject_master' => bool_or_null(normalize_units($excelUnits) === normalize_units($subject['subject_units'] ?? ''), $excelUnits !== ''),
            'database_grade' => null,
            'database_units' => null,
            'subject_units' => $subject['subject_units'] ?? null,
            'database_reference' => null,
            'database_student_id' => $student['s_id_no'] ?? null,
            'database_subject_id' => $subject['subject_id'] ?? null,
            'period_label' => null,
            'message' => 'Student and subject exist, but no grade record found for this period.',
        ];
    }

    $match = $matches[0];
    $gradeMatches = null;
    if (trim((string)$excelGrade) !== '') {
        $gradeMatches = normalize_grade($excelGrade) === normalize_grade($match['database_grade'] ?? '');
    }

    $unitsMatchDatabase = null;
    if (trim((string)$excelUnits) !== '') {
        $unitsMatchDatabase = normalize_units($excelUnits) === normalize_units($match['database_units'] ?? '');
    }

    $unitsMatchSubject = null;
    if (trim((string)$excelUnits) !== '') {
        $unitsMatchSubject = normalize_units($excelUnits) === normalize_units($match['subject_units'] ?? '');
    }

    $messages = [];
    if (count($matches) > 1) $messages[] = 'Multiple grade records found; latest sg_id shown.';
    if ($gradeMatches === false) $messages[] = 'Grade differs.';
    if ($unitsMatchDatabase === false) $messages[] = 'Units differ from tbl_students_grades.sg_credits.';
    if ($unitsMatchSubject === false) $messages[] = 'Units differ from tbl_subject.subject_units.';
    if (empty($messages)) $messages[] = 'Record found.';

    return [
        'exists' => true,
        'grade_matches' => $gradeMatches,
        'units_match_database' => $unitsMatchDatabase,
        'units_match_subject_master' => $unitsMatchSubject,
        'database_grade' => $match['database_grade'] ?? null,
        'database_units' => $match['database_units'] ?? null,
        'subject_units' => $match['subject_units'] ?? null,
        'database_reference' => $match['database_reference'] ?? null,
        'database_student_id' => $match['sg_student_id'] ?? null,
        'database_subject_id' => $match['sg_subject_id'] ?? null,
        'period_label' => $match['period_label'] ?? null,
        'message' => implode(' ', $messages),
    ];
}

try {
    $input = json_decode(file_get_contents('php://input'), true);
    if (!is_array($input)) {
        json_response(['ok' => false, 'message' => 'Invalid JSON body.'], 400);
    }

    $rows = $input['rows'] ?? null;
    if (!is_array($rows)) {
        json_response(['ok' => false, 'message' => 'Missing rows array.'], 400);
    }

    $pdo = db();
    $results = [];
    foreach ($rows as $row) {
        if (!is_array($row)) {
            $results[] = [
                'exists' => false,
                'grade_matches' => null,
                'units_match_database' => null,
                'units_match_subject_master' => null,
                'message' => 'Invalid row payload.',
            ];
            continue;
        }
        $results[] = check_one_row($pdo, $row);
    }

    json_response([
        'ok' => true,
        'count' => count($results),
        'results' => $results,
    ]);
} catch (Throwable $e) {
    json_response([
        'ok' => false,
        'message' => $e->getMessage(),
        'hint' => 'Check config.php DB connection and make sure cfcissmsdb with tbl_period/tbl_student/tbl_course/tbl_students_grades/tbl_subject is imported.',
    ], 500);
}
