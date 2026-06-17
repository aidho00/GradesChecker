<?php
require_once __DIR__ . '/bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    json_response(['ok' => false, 'message' => 'POST request required.'], 405);
}

set_time_limit(0);
ini_set('memory_limit', '768M');

function xls_text(mixed $value): string
{
    $text = trim((string) $value);
    return htmlspecialchars($text, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function xls_class_for_status(string $status): string
{
    $status = strtolower($status);
    if (str_contains($status, 'student not found')) return 'student-missing';
    if (str_contains($status, 'subject not found')) return 'subject-missing';
    if (str_contains($status, 'missing')) return 'missing';
    if (str_contains($status, 'grade') && str_contains($status, 'differ')) return 'grade-diff';
    if (str_contains($status, 'units') && str_contains($status, 'differ')) return 'units-diff';
    if (str_contains($status, 'exists')) return 'exists';
    return 'unchecked';
}

function xls_download_name(string $sourceFile, string $periodLabel): string
{
    $base = pathinfo($sourceFile, PATHINFO_FILENAME);
    if ($base === '') $base = 'grades_checker_export';
    $period = preg_replace('/[^A-Za-z0-9\-]+/', '_', $periodLabel) ?: 'period';
    $base = preg_replace('/[^A-Za-z0-9_\-]+/', '_', $base) ?: 'grades_checker_export';
    return $base . '_checked_' . $period . '.xls';
}

try {
    $input = json_decode(file_get_contents('php://input'), true);
    if (!is_array($input)) {
        json_response(['ok' => false, 'message' => 'Invalid JSON body.'], 400);
    }

    $students = $input['students'] ?? [];
    if (!is_array($students)) {
        json_response(['ok' => false, 'message' => 'Missing students array.'], 400);
    }

    $summary = is_array($input['summary'] ?? null) ? $input['summary'] : [];
    $periodLabel = (string) ($input['period_label'] ?? '');
    $sourceFile = (string) ($input['source_file'] ?? 'grades.xlsx');
    $interpretation = (string) ($input['interpretation'] ?? '');
    $downloadName = xls_download_name($sourceFile, $periodLabel);

    ob_start();
    echo "<!DOCTYPE html><html><head><meta charset=\"UTF-8\">";
    echo "<style>";
    echo "body{font-family:Calibri,Arial,sans-serif;font-size:11pt;color:#0f172a;}";
    echo "table{border-collapse:collapse;}";
    echo "td,th{border:1px solid #cbd5e1;padding:5px 7px;vertical-align:top;mso-number-format:'\\@';}";
    echo ".title{font-size:18pt;font-weight:700;background:#1d4ed8;color:white;}";
    echo ".subtitle{background:#dbeafe;color:#1e3a8a;font-weight:700;}";
    echo ".summary-label{background:#f1f5f9;font-weight:700;}";
    echo ".summary-value{font-weight:700;text-align:center;}";
    echo ".header{background:#334155;color:white;font-weight:700;text-align:center;}";
    echo ".exists{background:#dcfce7;color:#166534;font-weight:700;}";
    echo ".missing{background:#fee2e2;color:#991b1b;font-weight:700;}";
    echo ".grade-diff{background:#fef3c7;color:#92400e;font-weight:700;}";
    echo ".units-diff{background:#cffafe;color:#155e75;font-weight:700;}";
    echo ".student-missing{background:#ffe4e6;color:#9f1239;font-weight:700;}";
    echo ".subject-missing{background:#ffedd5;color:#9a3412;font-weight:700;}";
    echo ".unchecked{background:#e2e8f0;color:#475569;font-weight:700;}";
    echo ".small{font-size:9pt;color:#475569;}";
    echo "</style></head><body>";

    echo "<table>";
    echo "<tr><td colspan=\"66\" class=\"title\">UNO to SMS Grade Checker Export</td></tr>";
    echo "<tr><td colspan=\"66\" class=\"subtitle\">Source: " . xls_text($sourceFile) . " &nbsp;&nbsp; Period: " . xls_text($periodLabel) . " &nbsp;&nbsp; Generated: " . date('Y-m-d H:i:s') . "</td></tr>";
    echo "<tr>";
    $summaryItems = [
        'Students' => $summary['students'] ?? count($students),
        'Subject Records' => $summary['subject_records'] ?? '',
        'Checked' => $summary['checked'] ?? '',
        'Existing' => $summary['existing'] ?? '',
        'Missing' => $summary['missing'] ?? '',
        'Grade Differs' => $summary['grade_differs'] ?? '',
        'Units Differs' => $summary['units_differs'] ?? '',
        'Student Not Found' => $summary['student_not_found'] ?? '',
        'Subject Not Found' => $summary['subject_not_found'] ?? '',
    ];
    foreach ($summaryItems as $label => $value) {
        echo "<td class=\"summary-label\">" . xls_text($label) . "</td><td class=\"summary-value\">" . xls_text($value) . "</td>";
    }
    echo "</tr>";
    if ($interpretation !== '') {
        echo "<tr><td colspan=\"66\" class=\"subtitle\">Overall Interpretation</td></tr>";
        echo "<tr><td colspan=\"66\">" . nl2br(xls_text($interpretation)) . "</td></tr>";
    }
    echo "<tr><td colspan=\"66\"></td></tr>";

    echo "<tr>";
    $baseHeaders = ['ID', 'LAST NAME', 'FIRST NAME', 'MIDDLE NAME', 'COURSE', 'YEARLEVEL'];
    foreach ($baseHeaders as $header) echo "<th class=\"header\">" . xls_text($header) . "</th>";
    for ($i = 1; $i <= 10; $i++) {
        foreach (["SUBJECT$i", "UNITS$i", "GRADE$i", "STATUS$i", "DB_GRADE$i", "DB_UNITS$i"] as $header) {
            echo "<th class=\"header\">" . xls_text($header) . "</th>";
        }
    }
    echo "</tr>";

    foreach ($students as $student) {
        if (!is_array($student)) continue;
        echo "<tr>";
        echo "<td>" . xls_text($student['student_id'] ?? '') . "</td>";
        echo "<td>" . xls_text($student['last_name'] ?? '') . "</td>";
        echo "<td>" . xls_text($student['first_name'] ?? '') . "</td>";
        echo "<td>" . xls_text($student['middle_name'] ?? '') . "</td>";
        echo "<td>" . xls_text($student['course'] ?? '') . "</td>";
        echo "<td>" . xls_text($student['year_level'] ?? '') . "</td>";

        $subjects = is_array($student['subjects'] ?? null) ? $student['subjects'] : [];
        for ($i = 1; $i <= 10; $i++) {
            $subject = is_array($subjects[(string) $i] ?? null) ? $subjects[(string) $i] : [];
            $status = (string) ($subject['status'] ?? '');
            $class = xls_class_for_status($status);
            echo "<td class=\"$class\">" . xls_text($subject['subject_code'] ?? '') . "</td>";
            echo "<td>" . xls_text($subject['units'] ?? '') . "</td>";
            echo "<td>" . xls_text($subject['excel_grade'] ?? '') . "</td>";
            echo "<td class=\"$class\">" . xls_text($status) . "</td>";
            echo "<td>" . xls_text($subject['database_grade'] ?? '') . "</td>";
            echo "<td>" . xls_text($subject['database_credits'] ?? '') . "</td>";
        }
        echo "</tr>";
    }

    echo "</table></body></html>";
    $content = ob_get_clean();

    header('Content-Type: application/vnd.ms-excel; charset=UTF-8');
    header('Content-Disposition: attachment; filename="' . $downloadName . '"');
    header('Cache-Control: max-age=0');
    echo $content;
} catch (Throwable $e) {
    if (ob_get_level() > 0) ob_end_clean();
    json_response(['ok' => false, 'message' => $e->getMessage()], 500);
}
