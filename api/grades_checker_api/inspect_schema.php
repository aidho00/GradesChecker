<?php
require_once __DIR__ . '/bootstrap.php';
require_once __DIR__ . '/auth.php';
require_grade_checker_auth();

try {
    $pdo = db();
    $stmt = $pdo->prepare(
        'SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_KEY
         FROM INFORMATION_SCHEMA.COLUMNS
         WHERE TABLE_SCHEMA = :db
         ORDER BY TABLE_NAME, ORDINAL_POSITION'
    );
    $stmt->execute(['db' => DB_NAME]);

    $tables = [];
    foreach ($stmt->fetchAll() as $column) {
        $tableName = $column['TABLE_NAME'];
        if (!isset($tables[$tableName])) {
            $tables[$tableName] = [];
        }
        $tables[$tableName][] = [
            'name' => $column['COLUMN_NAME'],
            'type' => $column['DATA_TYPE'],
            'nullable' => $column['IS_NULLABLE'],
            'key' => $column['COLUMN_KEY'],
        ];
    }

    json_response([
        'ok' => true,
        'database' => DB_NAME,
        'tables' => $tables,
    ]);
} catch (Throwable $e) {
    json_response([
        'ok' => false,
        'message' => $e->getMessage(),
    ], 500);
}
