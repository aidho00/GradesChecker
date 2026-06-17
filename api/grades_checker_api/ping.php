<?php
require_once __DIR__ . '/bootstrap.php';

try {
    $pdo = db();
    $pdo->query('SELECT 1');
    json_response([
        'ok' => true,
        'message' => 'Database connection successful.',
        'database' => DB_NAME,
    ]);
} catch (Throwable $e) {
    json_response([
        'ok' => false,
        'message' => $e->getMessage(),
    ], 500);
}
