<?php
require_once __DIR__ . '/bootstrap.php';

try {
    $pdo = db();
    $stmt = $pdo->query(
        'SELECT period_id, period_name, period_semester, period_status,
                CONCAT(period_name, "-", period_semester) AS period_label
         FROM tbl_period
         ORDER BY period_name DESC, period_semester ASC, period_id DESC'
    );

    json_response([
        'ok' => true,
        'periods' => $stmt->fetchAll(),
    ]);
} catch (Throwable $e) {
    json_response([
        'ok' => false,
        'message' => $e->getMessage(),
    ], 500);
}
