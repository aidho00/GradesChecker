<?php
require_once __DIR__ . '/bootstrap.php';
require_once __DIR__ . '/auth.php';
require_grade_checker_auth();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    json_response(['ok' => false, 'message' => 'POST request required.'], 405);
}

function clean_text(mixed $value): string
{
    $text = trim((string) $value);
    return preg_replace('/\s+/', ' ', $text) ?? $text;
}

function table_columns(PDO $pdo, string $table): array
{
    $stmt = $pdo->query('SHOW COLUMNS FROM ' . quote_identifier($table));
    $columns = [];
    foreach ($stmt->fetchAll() as $column) {
        $columns[(string) $column['Field']] = $column;
    }
    return $columns;
}

function add_if_column(array &$data, array $columns, string $column, mixed $value): void
{
    if (isset($columns[$column])) {
        $data[$column] = $value;
    }
}


function default_value_for_column(array $column): mixed
{
    $type = strtolower((string) ($column['Type'] ?? ''));
    if (str_contains($type, 'int') || str_contains($type, 'decimal') || str_contains($type, 'double') || str_contains($type, 'float')) {
        return 0;
    }
    if (str_contains($type, 'datetime') || str_contains($type, 'timestamp')) {
        return date('Y-m-d H:i:s');
    }
    if (preg_match('/\bdate\b/', $type)) {
        return date('Y-m-d');
    }
    return '';
}

function fill_required_legacy_defaults(array &$data, array $columns): void
{
    foreach ($columns as $field => $column) {
        if (array_key_exists($field, $data)) continue;
        $isRequired = strtoupper((string) ($column['Null'] ?? 'YES')) === 'NO';
        $hasDefault = array_key_exists('Default', $column) && $column['Default'] !== null;
        $extra = strtolower((string) ($column['Extra'] ?? ''));
        if ($isRequired && !$hasDefault && !str_contains($extra, 'auto_increment')) {
            $data[$field] = default_value_for_column($column);
        }
    }
}


function normalize_year_level_label(mixed $value): string
{
    $compact = strtolower(preg_replace('/[^a-z0-9]+/', '', trim((string) $value)));
    if (in_array($compact, ['1', '1st', 'first', '1styear', 'firstyear'], true)) return '1st Year';
    if (in_array($compact, ['2', '2nd', 'second', '2ndyear', 'secondyear'], true)) return '2nd Year';
    if (in_array($compact, ['3', '3rd', 'third', '3rdyear', 'thirdyear'], true)) return '3rd Year';
    if (in_array($compact, ['4', '4th', 'fourth', '4thyear', 'fourthyear'], true)) return '4th Year';
    return '1st Year';
}

function normalize_birthdate_value(mixed $value): ?string
{
    $raw = trim((string) $value);
    if ($raw === '') return null;
    if (is_numeric($raw)) {
        $days = (float) $raw;
        if ($days > 20000 && $days < 80000) {
            $timestamp = (int) (($days - 25569) * 86400);
            return gmdate('Y-m-d', $timestamp);
        }
    }
    $timestamp = strtotime($raw);
    return $timestamp === false ? null : date('Y-m-d', $timestamp);
}

try {
    $input = json_decode(file_get_contents('php://input'), true);
    if (!is_array($input)) {
        json_response(['ok' => false, 'message' => 'Invalid JSON body.'], 400);
    }

    $studentId = clean_text($input['student_id'] ?? '');
    $firstName = clean_text($input['first_name'] ?? '');
    $middleName = clean_text($input['middle_name'] ?? '');
    $lastName = clean_text($input['last_name'] ?? '');
    $courseIdInput = clean_text($input['course_id'] ?? '');
    $courseCode = clean_text($input['course'] ?? ($input['course_code'] ?? ''));
    $yearLevel = normalize_year_level_label($input['year_level'] ?? '');
    $gender = clean_text($input['gender'] ?? '');
    $gender = strtolower(preg_replace('/[^a-z0-9]+/', '', $gender)) === 'female' ? 'Female' : 'Male';
    $birthdate = normalize_birthdate_value($input['birthdate'] ?? ($input['birth_date'] ?? ''));

    if ($studentId === '') {
        json_response(['ok' => false, 'message' => 'Student ID is required before creating a profile.'], 400);
    }
    if ($firstName === '' || $lastName === '') {
        json_response(['ok' => false, 'message' => 'First name and last name are required before creating a profile.'], 400);
    }

    $pdo = db();
    $pdo->beginTransaction();

    $stmt = $pdo->prepare('SELECT s_id_no, s_fn, s_ln, s_mn FROM tbl_student WHERE s_id_no = ? LIMIT 1');
    $stmt->execute([$studentId]);
    $existing = $stmt->fetch();
    if ($existing) {
        $pdo->commit();
        json_response([
            'ok' => true,
            'created' => false,
            'message' => 'Student profile already exists.',
            'student' => $existing,
        ]);
    }

    $courseId = null;
    if ($courseIdInput !== '') {
        $stmt = $pdo->prepare('SELECT course_id, course_code FROM tbl_course WHERE course_id = ? LIMIT 1');
        $stmt->execute([$courseIdInput]);
        $course = $stmt->fetch();
        if ($course) {
            $courseId = $course['course_id'];
            $courseCode = (string) ($course['course_code'] ?? $courseCode);
        }
    }

    if ($courseId === null && $courseCode !== '') {
        $stmt = $pdo->prepare('SELECT course_id, course_code FROM tbl_course WHERE UPPER(TRIM(course_code)) = UPPER(TRIM(?)) OR UPPER(TRIM(course_name)) = UPPER(TRIM(?)) LIMIT 1');
        $stmt->execute([$courseCode, $courseCode]);
        $course = $stmt->fetch();
        if ($course) {
            $courseId = $course['course_id'];
            $courseCode = (string) ($course['course_code'] ?? $courseCode);
        }
    }

    $columns = table_columns($pdo, 'tbl_student');
    $data = [];

    if (isset($columns['s_id'])) {
        $nextId = (int) $pdo->query('SELECT COALESCE(MAX(CAST(s_id AS UNSIGNED)), 0) + 1 AS next_id FROM tbl_student')->fetchColumn();
        $data['s_id'] = $nextId;
    }

    add_if_column($data, $columns, 's_id_no', $studentId);
    add_if_column($data, $columns, 's_fn', $firstName);
    add_if_column($data, $columns, 's_mn', $middleName);
    add_if_column($data, $columns, 's_ln', $lastName);
    add_if_column($data, $columns, 's_course_id', $courseId);
    add_if_column($data, $columns, 's_yr_lvl', $yearLevel);
    add_if_column($data, $columns, 's_gender', $gender);
    add_if_column($data, $columns, 's_dob', $birthdate);
    add_if_column($data, $columns, 's_status', 'Active');
    add_if_column($data, $columns, 's_active_status', 'Active');
    add_if_column($data, $columns, 's_begin_date', date('Y-m-d H:i:s'));

    add_if_column($data, $columns, 's_address_prov', '');
    add_if_column($data, $columns, 's_address_citymun', '');
    add_if_column($data, $columns, 's_address_brgy', '');
    add_if_column($data, $columns, 's_contact', '');
    add_if_column($data, $columns, 's_mother_mname', '');
    add_if_column($data, $columns, 's_mother_lname', '');
    add_if_column($data, $columns, 's_father_mname', '');
    add_if_column($data, $columns, 's_father_lname', '');
    add_if_column($data, $columns, 's_shirt_size', '');
    add_if_column($data, $columns, 's_nstp_no', '');
    add_if_column($data, $columns, 's_so_date', '');
    add_if_column($data, $columns, 's_address_zipcode', '');
    add_if_column($data, $columns, 's_cred_als_cert', 0);
    add_if_column($data, $columns, 's_acad_awards', '');
    add_if_column($data, $columns, 's_ext', '');
    add_if_column($data, $columns, 's_curr_id', 0);
    add_if_column($data, $columns, 's_course_status', '');
    add_if_column($data, $columns, 's_prereg_refno', '');
    add_if_column($data, $columns, 's_otr_mode', '');
    add_if_column($data, $columns, 's_otr_remarks', '');
    add_if_column($data, $columns, 's_ext_loc', 0);
    add_if_column($data, $columns, 'sync_status', 0);
    add_if_column($data, $columns, 'sync_last_modified', date('Y-m-d H:i:s'));

    fill_required_legacy_defaults($data, $columns);

    if (empty($data['s_id_no'])) {
        json_response(['ok' => false, 'message' => 'The required student ID field was not found in the student records.'], 500);
    }

    $fieldNames = array_keys($data);
    $sql = 'INSERT INTO tbl_student (' . implode(', ', array_map('quote_identifier', $fieldNames)) . ') VALUES (' . implode(', ', array_fill(0, count($fieldNames), '?')) . ')';
    $stmt = $pdo->prepare($sql);
    $stmt->execute(array_values($data));

    $pdo->commit();

    json_response([
        'ok' => true,
        'created' => true,
        'message' => 'Student profile created. Run Check again to verify grade records.',
        'student' => [
            's_id_no' => $studentId,
            's_fn' => $firstName,
            's_mn' => $middleName,
            's_ln' => $lastName,
            's_course_id' => $courseId,
            'course_code' => $courseCode,
            's_yr_lvl' => $yearLevel,
            's_gender' => $gender,
            's_dob' => $birthdate,
        ],
    ]);
} catch (Throwable $e) {
    if (isset($pdo) && $pdo instanceof PDO && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    json_response([
        'ok' => false,
        'message' => 'Unable to save the student profile. Please check the required profile details and try again.',
        'technical_message' => $e->getMessage(),
        'hint' => 'Confirm the UNO row has a student ID, first name, and last name.',
    ], 500);
}
