<?php
require_once __DIR__ . '/bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    json_response(['ok' => false, 'message' => 'GET request required.'], 405);
}

function normalized_semester_key(string $semester, string $periodName = ''): string
{
    $text = strtolower(trim($semester));
    $nameText = strtolower(trim($periodName));
    $compact = preg_replace('/[^a-z0-9]+/', '', $text);
    $nameCompact = preg_replace('/[^a-z0-9]+/', '', $nameText);
    $combined = $nameCompact . $compact;

    if ($compact === '' && !str_contains($combined, 'summer')) {
        return '';
    }
    if (str_contains($combined, 'summer') || str_contains($combined, 'sum')) {
        return 'summer';
    }
    if (str_contains($compact, 'trimester') || str_contains($compact, 'trimestral') || str_contains($compact, 'third') || str_contains($compact, '3rd') || $compact === '3' || $compact === 'sem3' || $compact === 'semester3') {
        return '';
    }
    if (str_contains($compact, '1st') || str_contains($compact, 'first') || $compact === '1' || $compact === 'sem1' || $compact === 'semester1') {
        return 'first';
    }
    if (str_contains($compact, '2nd') || str_contains($compact, 'second') || $compact === '2' || $compact === 'sem2' || $compact === 'semester2') {
        return 'second';
    }

    return '';
}

function period_label_from_tbl_period(array $row): string
{
    $name = trim((string) ($row['period_name'] ?? ''));
    $semester = trim((string) ($row['period_semester'] ?? ''));

    if ($name !== '' && $semester !== '') {
        return $name . ' - ' . $semester;
    }
    if ($name !== '') return $name;
    if ($semester !== '') return $semester;
    return 'Period #' . (string) ($row['period_id'] ?? '');
}

try {
    $pdo = db();
    $stmt = $pdo->query(
        "SELECT period_id, period_start_year, period_end_year, period_name, period_semester, period_status
         FROM tbl_period
         ORDER BY period_start_year DESC, period_end_year DESC, period_name DESC, period_semester ASC, period_id DESC"
    );

    $periods = [];
    foreach ($stmt->fetchAll() as $row) {
        $name = trim((string) ($row['period_name'] ?? ''));
        $semester = trim((string) ($row['period_semester'] ?? ''));
        $semesterKey = normalized_semester_key($semester, $name);

        // Only show real semester records from tbl_period: 1st, 2nd, and Summer.
        // Do not include trimesters/third trimester records.
        if ($semesterKey === '') {
            continue;
        }

        $periods[] = [
            'period_id' => (string) $row['period_id'],
            'period_name' => $name,
            'period_semester' => $semester,
            'period_status' => (string) ($row['period_status'] ?? ''),
            'label' => period_label_from_tbl_period($row),
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
