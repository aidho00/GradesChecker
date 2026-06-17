<?php
require_once __DIR__ . '/bootstrap.php';

try {
    $pdo = db();
    $tables = ['tbl_period', 'tbl_student', 'tbl_course', 'tbl_students_grades', 'tbl_subject'];
    $schema = [];

    $stmt = $pdo->prepare(
        'SELECT TABLE_NAME, COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_KEY
         FROM INFORMATION_SCHEMA.COLUMNS
         WHERE TABLE_SCHEMA = :schema AND TABLE_NAME = :table
         ORDER BY ORDINAL_POSITION'
    );

    foreach ($tables as $table) {
        $stmt->execute(['schema' => DB_NAME, 'table' => $table]);
        $schema[$table] = $stmt->fetchAll();
    }

    json_response([
        'ok' => true,
        'database' => DB_NAME,
        'schema' => $schema,
    ]);
} catch (Throwable $e) {
    json_response([
        'ok' => false,
        'message' => $e->getMessage(),
    ], 500);
}
