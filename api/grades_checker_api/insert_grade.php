<?php
require_once __DIR__ . '/bootstrap.php';
require_once __DIR__ . '/auth.php';
$user = require_grade_checker_auth();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    json_response(['ok' => false, 'message' => 'POST request required.'], 405);
}

function clean_text_insert_grade(mixed $value): string
{
    $text = trim((string) $value);
    return preg_replace('/\s+/', ' ', $text) ?? $text;
}

function table_columns_insert_grade(PDO $pdo, string $table): array
{
    $stmt = $pdo->query('SHOW COLUMNS FROM ' . quote_identifier($table));
    $columns = [];
    foreach ($stmt->fetchAll() as $column) {
        $columns[(string) $column['Field']] = $column;
    }
    return $columns;
}

function add_if_column_insert_grade(array &$data, array $columns, string $column, mixed $value): void
{
    if (isset($columns[$column])) {
        $data[$column] = $value;
    }
}

try {
    $input = json_decode(file_get_contents('php://input'), true);
    if (!is_array($input)) {
        json_response(['ok' => false, 'message' => 'Invalid JSON body.'], 400);
    }

    $studentId = clean_text_insert_grade($input['student_id'] ?? '');
    $subjectId = clean_text_insert_grade($input['subject_id'] ?? '');
    $periodId = clean_text_insert_grade($input['period_id'] ?? '');
    $grade = clean_text_insert_grade($input['grade'] ?? '');
    $credits = clean_text_insert_grade($input['credits'] ?? '');
    $courseCode = clean_text_insert_grade($input['course'] ?? '');
    $yearLevel = clean_text_insert_grade($input['year_level'] ?? '');
    $sequence = (int) ($input['subject_no'] ?? 0);

    if ($studentId === '' || $subjectId === '' || $periodId === '') {
        json_response(['ok' => false, 'message' => 'Student, subject, and academic year are required.'], 400);
    }
    if ($grade === '') {
        json_response(['ok' => false, 'message' => 'Grade is required before inserting to SMS.'], 400);
    }

    $pdo = db();

    $stmt = $pdo->prepare('SELECT s_id_no, s_course_id, s_yr_lvl FROM tbl_student WHERE s_id_no = ? LIMIT 1');
    $stmt->execute([$studentId]);
    $student = $stmt->fetch();
    if (!$student) {
        json_response(['ok' => false, 'message' => 'Student profile must exist before inserting a grade.'], 404);
    }

    $stmt = $pdo->prepare('SELECT subject_id, subject_code, subject_description, subject_units FROM tbl_subject WHERE subject_id = ? LIMIT 1');
    $stmt->execute([$subjectId]);
    $subject = $stmt->fetch();
    if (!$subject) {
        json_response(['ok' => false, 'message' => 'Selected subject was not found in SMS.'], 404);
    }

    $stmt = $pdo->prepare('SELECT period_id, period_name, period_semester FROM tbl_period WHERE period_id = ? LIMIT 1');
    $stmt->execute([$periodId]);
    $period = $stmt->fetch();
    if (!$period) {
        json_response(['ok' => false, 'message' => 'Selected academic year was not found in SMS.'], 404);
    }

    $stmt = $pdo->prepare('SELECT sg_id FROM tbl_students_grades WHERE sg_student_id = ? AND sg_subject_id = ? AND sg_period_id = ? LIMIT 1');
    $stmt->execute([$studentId, $subjectId, $periodId]);
    $existing = $stmt->fetch();
    $existingId = $existing['sg_id'] ?? null;

    $courseId = $student['s_course_id'] ?? null;
    if (($courseId === null || $courseId === '' || (string) $courseId === '0') && $courseCode !== '') {
        $stmt = $pdo->prepare('SELECT course_id FROM tbl_course WHERE UPPER(TRIM(course_code)) = UPPER(TRIM(?)) OR UPPER(TRIM(course_name)) = UPPER(TRIM(?)) LIMIT 1');
        $stmt->execute([$courseCode, $courseCode]);
        $course = $stmt->fetch();
        if ($course) $courseId = $course['course_id'];
    }
    if ($courseId === null || $courseId === '') $courseId = 0;
    if ($credits === '') $credits = clean_text_insert_grade($subject['subject_units'] ?? '');
    if ($yearLevel === '') $yearLevel = clean_text_insert_grade($student['s_yr_lvl'] ?? '');
    if ($sequence <= 0) $sequence = 0;

    $columns = table_columns_insert_grade($pdo, 'tbl_students_grades');
    $data = [];
    add_if_column_insert_grade($data, $columns, 'sg_student_id', $studentId);
    add_if_column_insert_grade($data, $columns, 'sg_course_id', $courseId);
    add_if_column_insert_grade($data, $columns, 'sg_period_id', $periodId);
    add_if_column_insert_grade($data, $columns, 'sg_class_id', 0);
    add_if_column_insert_grade($data, $columns, 'sg_subject_id', $subjectId);
    add_if_column_insert_grade($data, $columns, 'sg_grade', $grade);
    add_if_column_insert_grade($data, $columns, 'sg_grade_prelim', 0);
    add_if_column_insert_grade($data, $columns, 'sg_grade_midterm', 0);
    add_if_column_insert_grade($data, $columns, 'sg_grade_semi', 0);
    add_if_column_insert_grade($data, $columns, 'sg_grade_final', 0);
    add_if_column_insert_grade($data, $columns, 'sg_grade_avg', $grade);
    add_if_column_insert_grade($data, $columns, 'sg_credits', $credits);
    add_if_column_insert_grade($data, $columns, 'sg_school_id', 0);
    add_if_column_insert_grade($data, $columns, 'sg_sequence', $sequence);
    add_if_column_insert_grade($data, $columns, 'sg_yearlevel', $yearLevel);
    add_if_column_insert_grade($data, $columns, 'sg_grade_status', $existingId ? 'Updated' : 'Imported');
    add_if_column_insert_grade($data, $columns, 'sg_grade_remarks', $existingId ? 'Updated from Grades Checker' : 'Inserted from Grades Checker');
    add_if_column_insert_grade($data, $columns, 'sg_grade_addedby', (int) ($user['ua_id'] ?? 0));
    add_if_column_insert_grade($data, $columns, 'sg_grade_dateadded', date('Y-m-d'));
    add_if_column_insert_grade($data, $columns, 'sg_grade_visibility', 0);
    add_if_column_insert_grade($data, $columns, 'sg_prev_grade', '');
    add_if_column_insert_grade($data, $columns, 'sg_prev_grade_avg', 0);
    add_if_column_insert_grade($data, $columns, 'sg_prev_grade_addedby', 0);
    add_if_column_insert_grade($data, $columns, 'sg_prev_grade_dateadded', null);
    add_if_column_insert_grade($data, $columns, 'sg_added', date('Y-m-d'));
    add_if_column_insert_grade($data, $columns, 'sync_status', 0);
    add_if_column_insert_grade($data, $columns, 'sync_last_modified', date('Y-m-d H:i:s'));

    $fieldNames = array_keys($data);

    if ($existingId) {
        $assignments = implode(', ', array_map(fn($field) => quote_identifier($field) . ' = ?', $fieldNames));
        $sql = 'UPDATE tbl_students_grades SET ' . $assignments . ' WHERE sg_id = ? LIMIT 1';
        $stmt = $pdo->prepare($sql);
        $params = array_values($data);
        $params[] = $existingId;
        $stmt->execute($params);

        json_response([
            'ok' => true,
            'created' => false,
            'message' => 'Grade updated in SMS for the selected subject and academic year.',
            'sg_id' => $existingId,
        ]);
    }

    $sql = 'INSERT INTO tbl_students_grades (' . implode(', ', array_map('quote_identifier', $fieldNames)) . ') VALUES (' . implode(', ', array_fill(0, count($fieldNames), '?')) . ')';
    $stmt = $pdo->prepare($sql);
    $stmt->execute(array_values($data));

    json_response([
        'ok' => true,
        'created' => true,
        'message' => 'Grade inserted to SMS for the selected subject and academic year.',
        'sg_id' => $pdo->lastInsertId(),
    ]);
} catch (Throwable $e) {
    json_response([
        'ok' => false,
        'message' => $e->getMessage(),
        'hint' => 'Confirm student profile, subject, and academic year exist before inserting a grade.',
    ], 500);
}
