<?php
require_once __DIR__ . '/bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    json_response(['ok' => false, 'message' => 'GET request required.'], 405);
}

try {
    $pdo = db();
    $stmt = $pdo->query(
        "SELECT period_id, period_name, period_semester, period_status
         FROM tbl_period
         ORDER BY period_start_year DESC, period_end_year DESC, period_semester ASC, period_id DESC"
    );

    $periods = [];
    foreach ($stmt->fetchAll() as $row) {
        $name = trim((string) ($row['period_name'] ?? ''));
        $semester = trim((string) ($row['period_semester'] ?? ''));
        $periods[] = [
            'period_id' => (string) $row['period_id'],
            'period_name' => $name,
            'period_semester' => $semester,
            'period_status' => (string) ($row['period_status'] ?? ''),
            'label' => trim($name . ($semester !== '' ? ' - ' . $semester : '')),
        ];
    }

    json_response([
        'ok' => true,
        'count' => count($periods),
        'periods' => $periods,
    ]);
} catch (Throwable $e) {
    json_response([
        'ok' => false,
        'message' => $e->getMessage(),
        'hint' => 'Check config.php, import cfcissmsdb, then verify tbl_period exists.',
    ], 500);
}
