<?php
require_once __DIR__ . '/bootstrap.php';

try {
    $pdo = db();
    $version = $pdo->query('SELECT VERSION() AS version')->fetch();
    json_response([
        'ok' => true,
        'message' => 'PHP API and MySQL connection are working.',
        'database' => DB_NAME,
        'mysql_version' => $version['version'] ?? null,
    ]);
} catch (Throwable $e) {
    json_response([
        'ok' => false,
        'message' => $e->getMessage(),
    ], 500);
}
