<?php
require_once __DIR__ . '/bootstrap.php';
require_once __DIR__ . '/auth.php';
require_grade_checker_auth();

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    json_response(['ok' => false, 'message' => 'GET request required.'], 405);
}

try {
    $pdo = db();
    $stmt = $pdo->query(
        "SELECT course_id, course_code, course_name, course_major, course_status
         FROM tbl_course
         ORDER BY course_code ASC, course_name ASC"
    );
    json_response(['ok' => true, 'courses' => $stmt->fetchAll()]);
} catch (Throwable $e) {
    json_response([
        'ok' => false,
        'message' => $e->getMessage(),
        'hint' => 'Check config.php and confirm tbl_course exists.',
    ], 500);
}
