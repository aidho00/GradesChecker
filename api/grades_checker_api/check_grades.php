<?php
require_once __DIR__ . '/bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    json_response(['ok' => false, 'message' => 'POST request required.'], 405);
}

function clean_key(mixed $value): string
{
    return normalize_value($value);
}

function first_non_empty(array $values): string
{
    foreach ($values as $value) {
        $text = trim((string) $value);
        if ($text !== '') return $text;
    }
    return '';
}

function placeholders(int $count): string
{
    return implode(',', array_fill(0, $count, '?'));
}


function grade_records_payload(array $grades): array
{
    $out = [];
    foreach ($grades as $grade) {
        if (!is_array($grade)) continue;
        $out[] = [
            'reference' => $grade['sg_id'] ?? '',
            'grade' => $grade['sg_grade'] ?? '',
            'credits' => $grade['sg_credits'] ?? '',
            'subject_units' => $grade['subject_units'] ?? '',
            'course_code' => $grade['course_code'] ?? '',
            'subject_description' => $grade['subject_description'] ?? '',
            'grade_status' => $grade['sg_grade_status'] ?? '',
            'class_id' => $grade['sg_class_id'] ?? '',
            'period_id' => $grade['sg_period_id'] ?? '',
            'period_label' => trim((string) ($grade['period_label'] ?? '')),
        ];
    }
    return $out;
}

function choose_best_grade(array $grades, string $excelGrade): ?array
{
    if (empty($grades)) return null;
    $excelNorm = normalize_grade($excelGrade);
    if ($excelNorm !== '') {
        foreach ($grades as $grade) {
            if (normalize_grade($grade['sg_grade'] ?? '') === $excelNorm) return $grade;
        }
    }
    return $grades[0];
}
function unique_non_empty(array $values): array
{
    $seen = [];
    $out = [];
    foreach ($values as $value) {
        $text = trim((string) $value);
        if ($text === '') continue;
        $key = clean_key($text);
        if (isset($seen[$key])) continue;
        $seen[$key] = true;
        $out[] = $text;
    }
    return $out;
}

try {
    $input = json_decode(file_get_contents('php://input'), true);
    if (!is_array($input)) {
        json_response(['ok' => false, 'message' => 'Invalid JSON body.'], 400);
    }

    $periodId = trim((string) ($input['period_id'] ?? ''));
    $rows = $input['rows'] ?? null;
    if (!is_array($rows)) {
        json_response(['ok' => false, 'message' => 'Missing rows array.'], 400);
    }
    if ($periodId === '' && isset($rows[0]['period_id'])) {
        $periodId = trim((string) $rows[0]['period_id']);
    }
    if ($periodId === '') {
        json_response(['ok' => false, 'message' => 'Missing selected period_id.'], 400);
    }

    // Keep each request bounded. Flutter sends large workbooks in batches.
    if (count($rows) > 1000) {
        json_response(['ok' => false, 'message' => 'Too many rows in one request. Use client-side batching of 1000 rows or less.'], 413);
    }

    $pdo = db();

    $studentIds = [];
    $nameKeys = [];
    $subjectKeys = [];
    foreach ($rows as $row) {
        if (!is_array($row)) continue;
        $studentId = trim((string) ($row['student_id'] ?? ''));
        $firstName = trim((string) ($row['first_name'] ?? ''));
        $lastName = trim((string) ($row['last_name'] ?? ''));
        $subjectCode = trim((string) ($row['subject_code'] ?? ''));

        if ($studentId !== '') $studentIds[] = $studentId;
        if ($firstName !== '' && $lastName !== '') $nameKeys[] = clean_key($firstName . '|' . $lastName);
        if ($subjectCode !== '') $subjectKeys[] = clean_key($subjectCode);
    }

    $studentIds = unique_non_empty($studentIds);
    $subjectKeys = array_values(array_unique($subjectKeys));
    $nameKeys = array_values(array_unique($nameKeys));

    $studentsById = [];
    if (!empty($studentIds)) {
        $sql = "SELECT st.s_id_no, st.s_fn, st.s_ln, st.s_mn, st.s_course_id, st.s_yr_lvl, co.course_code
                FROM tbl_student st
                LEFT JOIN tbl_course co ON co.course_id = st.s_course_id
                WHERE st.s_id_no IN (" . placeholders(count($studentIds)) . ")";
        $stmt = $pdo->prepare($sql);
        $stmt->execute($studentIds);
        foreach ($stmt->fetchAll() as $student) {
            $studentsById[clean_key($student['s_id_no'] ?? '')] = $student;
        }
    }

    $studentsByName = [];
    if (!empty($nameKeys)) {
        $sql = "SELECT st.s_id_no, st.s_fn, st.s_ln, st.s_mn, st.s_course_id, st.s_yr_lvl, co.course_code,
                       CONCAT(UPPER(TRIM(st.s_fn)), '|', UPPER(TRIM(st.s_ln))) AS name_key
                FROM tbl_student st
                LEFT JOIN tbl_course co ON co.course_id = st.s_course_id
                WHERE CONCAT(UPPER(TRIM(st.s_fn)), '|', UPPER(TRIM(st.s_ln))) IN (" . placeholders(count($nameKeys)) . ")";
        $stmt = $pdo->prepare($sql);
        $stmt->execute($nameKeys);
        $temp = [];
        foreach ($stmt->fetchAll() as $student) {
            $key = clean_key($student['name_key'] ?? '');
            $temp[$key][] = $student;
        }
        foreach ($temp as $key => $matches) {
            // Use name fallback only when it points to exactly one student.
            if (count($matches) === 1) $studentsByName[$key] = $matches[0];
        }
    }

    $subjectsByCode = [];
    if (!empty($subjectKeys)) {
        $sql = "SELECT subject_id, subject_code, subject_description, subject_units
                FROM tbl_subject
                WHERE UPPER(TRIM(subject_code)) IN (" . placeholders(count($subjectKeys)) . ")";
        $stmt = $pdo->prepare($sql);
        $stmt->execute($subjectKeys);
        foreach ($stmt->fetchAll() as $subject) {
            $key = clean_key($subject['subject_code'] ?? '');
            if (!isset($subjectsByCode[$key])) $subjectsByCode[$key] = $subject;
        }
    }

    $resolvedRows = [];
    $resolvedStudentIds = [];
    $resolvedSubjectIds = [];
    foreach ($rows as $index => $row) {
        if (!is_array($row)) {
            $resolvedRows[$index] = ['row' => $row, 'student' => null, 'subject' => null, 'invalid' => true];
            continue;
        }

        $studentId = trim((string) ($row['student_id'] ?? ''));
        $firstName = trim((string) ($row['first_name'] ?? ''));
        $lastName = trim((string) ($row['last_name'] ?? ''));
        $subjectCode = trim((string) ($row['subject_code'] ?? ''));

        $student = null;
        if ($studentId !== '') {
            $student = $studentsById[clean_key($studentId)] ?? null;
        }
        if (!$student && $firstName !== '' && $lastName !== '') {
            $student = $studentsByName[clean_key($firstName . '|' . $lastName)] ?? null;
        }

        $subject = $subjectsByCode[clean_key($subjectCode)] ?? null;
        $resolvedRows[$index] = ['row' => $row, 'student' => $student, 'subject' => $subject, 'invalid' => false];

        if ($student && $subject) {
            $resolvedStudentIds[] = (string) $student['s_id_no'];
            $resolvedSubjectIds[] = (string) $subject['subject_id'];
        }
    }

    $resolvedStudentIds = unique_non_empty($resolvedStudentIds);
    $resolvedSubjectIds = unique_non_empty($resolvedSubjectIds);

    $gradesByKey = [];
    if (!empty($resolvedStudentIds) && !empty($resolvedSubjectIds)) {
        $sql = "SELECT sg.sg_id, sg.sg_student_id, sg.sg_subject_id, sg.sg_period_id,
                       sg.sg_grade, sg.sg_credits, sg.sg_grade_status, sg.sg_course_id, sg.sg_class_id,
                       co.course_code, subj.subject_units, subj.subject_description,
                       CONCAT(COALESCE(p.period_name, ''), ' - ', COALESCE(p.period_semester, '')) AS period_label
                FROM tbl_students_grades sg
                LEFT JOIN tbl_course co ON co.course_id = sg.sg_course_id
                LEFT JOIN tbl_subject subj ON subj.subject_id = sg.sg_subject_id
                LEFT JOIN tbl_period p ON p.period_id = sg.sg_period_id
                WHERE sg.sg_period_id = ?
                  AND sg.sg_student_id IN (" . placeholders(count($resolvedStudentIds)) . ")
                  AND sg.sg_subject_id IN (" . placeholders(count($resolvedSubjectIds)) . ")";
        $params = array_merge([$periodId], $resolvedStudentIds, $resolvedSubjectIds);
        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);
        foreach ($stmt->fetchAll() as $grade) {
            $key = clean_key(($grade['sg_student_id'] ?? '') . '|' . ($grade['sg_subject_id'] ?? '') . '|' . $periodId);
            $gradesByKey[$key][] = $grade;
        }
    }


    $otherGradesByKey = [];
    if (!empty($resolvedStudentIds) && !empty($resolvedSubjectIds)) {
        $sql = "SELECT sg.sg_id, sg.sg_student_id, sg.sg_subject_id, sg.sg_period_id,
                       sg.sg_grade, sg.sg_credits, sg.sg_grade_status, sg.sg_course_id, sg.sg_class_id,
                       co.course_code, subj.subject_units, subj.subject_description,
                       CONCAT(COALESCE(p.period_name, ''), ' - ', COALESCE(p.period_semester, '')) AS period_label
                FROM tbl_students_grades sg
                LEFT JOIN tbl_course co ON co.course_id = sg.sg_course_id
                LEFT JOIN tbl_subject subj ON subj.subject_id = sg.sg_subject_id
                LEFT JOIN tbl_period p ON p.period_id = sg.sg_period_id
                WHERE sg.sg_period_id <> ?
                  AND sg.sg_student_id IN (" . placeholders(count($resolvedStudentIds)) . ")
                  AND sg.sg_subject_id IN (" . placeholders(count($resolvedSubjectIds)) . ")
                ORDER BY sg.sg_period_id DESC, sg.sg_id DESC";
        $params = array_merge([$periodId], $resolvedStudentIds, $resolvedSubjectIds);
        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);
        foreach ($stmt->fetchAll() as $grade) {
            $key = clean_key(($grade['sg_student_id'] ?? '') . '|' . ($grade['sg_subject_id'] ?? ''));
            $otherGradesByKey[$key][] = $grade;
        }
    }

    $results = [];
    foreach ($resolvedRows as $resolved) {
        if (($resolved['invalid'] ?? false) === true) {
            $results[] = [
                'exists' => false,
                'student_found' => false,
                'subject_found' => false,
                'grade_matches' => null,
                'units_match' => null,
                'message' => 'Invalid row payload.',
                'matching_grades' => [],
                'other_period_grades' => [],
            ];
            continue;
        }

        $row = $resolved['row'];
        $student = $resolved['student'];
        $subject = $resolved['subject'];
        $excelGrade = trim((string) ($row['excel_grade'] ?? ''));
        $excelUnits = trim((string) ($row['units'] ?? ''));

        if (!$student) {
            $results[] = [
                'exists' => false,
                'student_found' => false,
                'subject_found' => null,
                'grade_matches' => null,
                'units_match' => null,
                'database_grade' => null,
                'database_credits' => null,
                'subject_units' => null,
                'database_course' => null,
                'database_reference' => null,
                'message' => 'No student matched by ID or first/last name.',
                'matching_grades' => [],
                'other_period_grades' => [],
            ];
            continue;
        }

        if (!$subject) {
            $results[] = [
                'exists' => false,
                'student_found' => true,
                'subject_found' => false,
                'grade_matches' => null,
                'units_match' => null,
                'database_grade' => null,
                'database_credits' => null,
                'subject_units' => null,
                'database_course' => $student['course_code'] ?? null,
                'database_reference' => null,
                'message' => 'Student found, but subject code was not found in tbl_subject.',
                'matching_grades' => [],
                'other_period_grades' => [],
            ];
            continue;
        }

        $otherKey = clean_key(($student['s_id_no'] ?? '') . '|' . ($subject['subject_id'] ?? ''));
        $otherGradeMatchesList = $otherGradesByKey[$otherKey] ?? [];
        $gradeKey = clean_key(($student['s_id_no'] ?? '') . '|' . ($subject['subject_id'] ?? '') . '|' . $periodId);
        $gradeMatchesList = $gradesByKey[$gradeKey] ?? [];
        $grade = choose_best_grade($gradeMatchesList, $excelGrade);
        if (!$grade) {
            $results[] = [
                'exists' => false,
                'student_found' => true,
                'subject_found' => true,
                'grade_matches' => null,
                'units_match' => null,
                'database_grade' => null,
                'database_credits' => null,
                'subject_units' => $subject['subject_units'] ?? null,
                'database_course' => $student['course_code'] ?? null,
                'subject_description' => $subject['subject_description'] ?? null,
                'database_reference' => null,
                'message' => 'Student and subject exist, but no grade record exists for the selected period.' . (count($otherGradeMatchesList) > 0 ? ' Grade record exists in other period(s).' : ''),
                'matching_grades' => [],
                'other_period_grades' => grade_records_payload($otherGradeMatchesList),
            ];
            continue;
        }

        $databaseGrade = $grade['sg_grade'] ?? '';
        $databaseCredits = $grade['sg_credits'] ?? '';
        $subjectUnits = first_non_empty([$grade['subject_units'] ?? '', $subject['subject_units'] ?? '']);
        $gradeMatches = $excelGrade === '' ? null : normalize_grade($databaseGrade) === normalize_grade($excelGrade);

        $unitsMatches = null;
        $excelUnitsNorm = normalize_grade($excelUnits);
        if ($excelUnitsNorm !== '') {
            $dbCreditsNorm = normalize_grade($databaseCredits);
            $subjectUnitsNorm = normalize_grade($subjectUnits);
            if ($dbCreditsNorm !== '') {
                $unitsMatches = $excelUnitsNorm === $dbCreditsNorm;
            }
            if ($subjectUnitsNorm !== '' && $unitsMatches !== false) {
                $unitsMatches = $excelUnitsNorm === $subjectUnitsNorm;
            }
        }

        $messages = [];
        if ($gradeMatches === false) $messages[] = 'Grade differs';
        if ($unitsMatches === false) $messages[] = 'Units differ';
        if (empty($messages)) $messages[] = 'Record found';

        $results[] = [
            'exists' => true,
            'student_found' => true,
            'subject_found' => true,
            'grade_matches' => $gradeMatches,
            'units_match' => $unitsMatches,
            'database_grade' => $databaseGrade,
            'database_credits' => $databaseCredits,
            'subject_units' => $subjectUnits,
            'database_course' => $grade['course_code'] ?? ($student['course_code'] ?? null),
            'subject_description' => $grade['subject_description'] ?? ($subject['subject_description'] ?? null),
            'database_reference' => $grade['sg_id'] ?? null,
            'message' => implode(' and ', $messages) . (count($gradeMatchesList) > 1 ? ' Multiple grade records found for this subject.' : '.') . (count($otherGradeMatchesList) > 0 ? ' Other-period grade record(s) also exist.' : ''),
            'matching_grades' => grade_records_payload($gradeMatchesList),
            'other_period_grades' => grade_records_payload($otherGradeMatchesList),
        ];
    }

    json_response([
        'ok' => true,
        'period_id' => $periodId,
        'count' => count($results),
        'results' => $results,
        'batch_optimized' => true,
    ]);
} catch (Throwable $e) {
    json_response([
        'ok' => false,
        'message' => $e->getMessage(),
        'hint' => 'Check config.php credentials and confirm tbl_student, tbl_subject, tbl_period, tbl_course, and tbl_students_grades exist.',
    ], 500);
}
