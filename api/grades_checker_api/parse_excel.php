<?php
require_once __DIR__ . '/bootstrap.php';
require_once __DIR__ . '/auth.php';
require_grade_checker_auth();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    json_response(['ok' => false, 'message' => 'POST request required.'], 405);
}

set_time_limit(0);
ini_set('memory_limit', '768M');

function xlsx_normalize_header(string $value): string
{
    return preg_replace('/[^A-Z0-9]/', '', strtoupper(trim($value))) ?? '';
}

function xlsx_clean_value(mixed $value): string
{
    $text = trim((string) $value);
    $text = preg_replace('/\s+/', ' ', $text) ?? $text;
    if (preg_match('/^-?\d+\.0$/', $text)) return substr($text, 0, -2);
    return $text;
}

function xlsx_col_index(string $cellRef): int
{
    preg_match('/^[A-Z]+/i', $cellRef, $match);
    $letters = strtoupper($match[0] ?? '');
    $index = 0;
    for ($i = 0; $i < strlen($letters); $i++) $index = ($index * 26) + (ord($letters[$i]) - 64);
    return max(0, $index - 1);
}

function zip_read_entries(string $filePath): array
{
    $data = file_get_contents($filePath);
    if ($data === false || strlen($data) < 22) throw new RuntimeException('Unable to read uploaded XLSX file.');

    $eocdPos = strrpos($data, "PK\x05\x06");
    if ($eocdPos === false) throw new RuntimeException('Invalid XLSX/ZIP file: end of central directory not found.');

    $eocd = unpack('Vsig/vdisk/vcdDisk/vdiskEntries/ventries/VcdSize/VcdOffset/vcommentLen', substr($data, $eocdPos, 22));
    $pos = (int) $eocd['cdOffset'];
    $entries = [];

    for ($i = 0; $i < (int) $eocd['entries']; $i++) {
        if (substr($data, $pos, 4) !== "PK\x01\x02") break;
        $header = unpack(
            'Vsig/vverMade/vverNeed/vflag/vmethod/vmtime/vmdate/Vcrc/Vcsize/Vusize/vnlen/velen/vclen/vdisk/vint/Vext/Voffset',
            substr($data, $pos, 46)
        );
        $nameLen = (int) $header['nlen'];
        $extraLen = (int) $header['elen'];
        $commentLen = (int) $header['clen'];
        $name = substr($data, $pos + 46, $nameLen);
        $entries[$name] = [
            'method' => (int) $header['method'],
            'compressed_size' => (int) $header['csize'],
            'offset' => (int) $header['offset'],
            '_zip_data' => $data,
        ];
        $pos += 46 + $nameLen + $extraLen + $commentLen;
    }
    return $entries;
}

function zip_get_entry(array $entries, string $name): string|false
{
    if (!isset($entries[$name])) return false;
    $entry = $entries[$name];
    $data = $entry['_zip_data'];
    $offset = $entry['offset'];
    if (substr($data, $offset, 4) !== "PK\x03\x04") return false;

    $local = unpack('Vsig/vver/vflag/vmethod/vmtime/vmdate/Vcrc/Vcsize/Vusize/vnlen/velen', substr($data, $offset, 30));
    $dataStart = $offset + 30 + (int) $local['nlen'] + (int) $local['elen'];
    $compressed = substr($data, $dataStart, (int) $entry['compressed_size']);

    if ((int) $entry['method'] === 0) return $compressed;
    if ((int) $entry['method'] === 8) {
        $inflated = @gzinflate($compressed);
        return $inflated === false ? false : $inflated;
    }
    throw new RuntimeException('Unsupported ZIP compression method: ' . $entry['method']);
}

function xml_decode_text(string $value): string
{
    return html_entity_decode(strip_tags($value), ENT_QUOTES | ENT_XML1, 'UTF-8');
}

function xml_attrs(string $tag): array
{
    $attrs = [];
    if (preg_match_all('/([A-Za-z_:][A-Za-z0-9_:.-]*)="([^"]*)"/', $tag, $matches, PREG_SET_ORDER)) {
        foreach ($matches as $match) $attrs[$match[1]] = html_entity_decode($match[2], ENT_QUOTES | ENT_XML1, 'UTF-8');
    }
    return $attrs;
}

function xml_join_text_nodes(string $xml): string
{
    $text = '';
    if (preg_match_all('/<[^:>]*:?t\b[^>]*>(.*?)<\/[^:>]*:?t>/is', $xml, $matches)) {
        foreach ($matches[1] as $part) $text .= xml_decode_text($part);
    }
    return xlsx_clean_value($text);
}

function xlsx_shared_strings(array $zipEntries): array
{
    $xml = zip_get_entry($zipEntries, 'xl/sharedStrings.xml');
    if ($xml === false || trim($xml) === '') return [];

    $strings = [];
    if (preg_match_all('/<si\b[^>]*>(.*?)<\/si>/is', $xml, $matches)) {
        foreach ($matches[1] as $siXml) $strings[] = xml_join_text_nodes($siXml);
    }
    return $strings;
}

function xlsx_first_sheet_path(array $zipEntries): string
{
    $workbookXml = zip_get_entry($zipEntries, 'xl/workbook.xml');
    $relsXml = zip_get_entry($zipEntries, 'xl/_rels/workbook.xml.rels');
    if ($workbookXml === false || $relsXml === false) return 'xl/worksheets/sheet1.xml';

    $rid = '';
    if (preg_match('/<sheet\b([^>]*)>/i', $workbookXml, $match)) {
        $attrs = xml_attrs($match[1]);
        $rid = $attrs['r:id'] ?? $attrs['id'] ?? '';
    }
    if ($rid === '') return 'xl/worksheets/sheet1.xml';

    if (preg_match_all('/<Relationship\b([^>]*)\/>/i', $relsXml, $matches)) {
        foreach ($matches[1] as $relTag) {
            $attrs = xml_attrs($relTag);
            if (($attrs['Id'] ?? '') === $rid) {
                $target = $attrs['Target'] ?? '';
                if ($target === '') break;
                if (str_starts_with($target, '/')) return ltrim($target, '/');
                if (str_starts_with($target, 'xl/')) return $target;
                return 'xl/' . ltrim($target, '/');
            }
        }
    }
    return 'xl/worksheets/sheet1.xml';
}

function xlsx_cell_value_from_xml(string $cellTag, string $cellBody, array $sharedStrings): string
{
    $attrs = xml_attrs($cellTag);
    $type = $attrs['t'] ?? '';
    if ($type === 'inlineStr') return xml_join_text_nodes($cellBody);

    $value = '';
    if (preg_match('/<v\b[^>]*>(.*?)<\/v>/is', $cellBody, $match)) $value = xml_decode_text($match[1]);
    if ($type === 's') return $sharedStrings[(int) $value] ?? '';
    return xlsx_clean_value($value);
}

function xlsx_row_values_from_xml(string $rowBody, array $sharedStrings): array
{
    $values = [];
    if (preg_match_all('/<c\b([^>]*)>(.*?)<\/c>/is', $rowBody, $matches, PREG_SET_ORDER)) {
        foreach ($matches as $match) {
            $attrs = xml_attrs($match[1]);
            $ref = $attrs['r'] ?? '';
            if ($ref === '') continue;
            $values[xlsx_col_index($ref)] = xlsx_cell_value_from_xml($match[1], $match[2], $sharedStrings);
        }
    }
    if (!empty($values)) ksort($values);
    return $values;
}

function xlsx_from_index(array $row, ?int $index): string
{
    if ($index === null || $index < 0) return '';
    return xlsx_clean_value($row[$index] ?? '');
}

function xlsx_birthdate_from_index(array $row, ?int $index): string
{
    $raw = xlsx_from_index($row, $index);
    if ($raw === '') return '';

    if (is_numeric($raw)) {
        $days = (float) $raw;
        if ($days > 20000 && $days < 80000) {
            $timestamp = (int) (($days - 25569) * 86400);
            return gmdate('Y-m-d', $timestamp);
        }
    }

    $timestamp = strtotime($raw);
    if ($timestamp !== false) {
        return date('Y-m-d', $timestamp);
    }

    return $raw;
}

try {
    if (!isset($_FILES['excel']) || !is_uploaded_file($_FILES['excel']['tmp_name'])) {
        json_response(['ok' => false, 'message' => 'Missing uploaded UNO file field named excel.'], 400);
    }

    $periodId = trim((string) ($_POST['period_id'] ?? ''));
    $schoolYear = trim((string) ($_POST['school_year'] ?? ''));
    $semester = trim((string) ($_POST['semester'] ?? ''));
    $fileName = (string) ($_FILES['excel']['name'] ?? 'uploaded.xlsx');
    $tmpPath = $_FILES['excel']['tmp_name'];

    if (!preg_match('/\.xlsx$/i', $fileName)) {
        json_response([
            'ok' => false,
            'message' => 'Invalid file type. Please upload the original UNO promotional-list UNO file in .xlsx format.',
        ], 400);
    }

    $zipEntries = zip_read_entries($tmpPath);
    $sharedStrings = xlsx_shared_strings($zipEntries);
    $sheetPath = xlsx_first_sheet_path($zipEntries);
    $sheetXml = zip_get_entry($zipEntries, $sheetPath);
    if ($sheetXml === false) json_response(['ok' => false, 'message' => 'Unable to locate the first worksheet inside the XLSX file.'], 400);

    if (!preg_match_all('/<row\b([^>]*)>(.*?)<\/row>/is', $sheetXml, $rowMatches, PREG_SET_ORDER)) {
        json_response(['ok' => false, 'message' => 'The first worksheet has no readable rows.'], 400);
    }

    $headers = [];
    $headerRead = false;
    $parsed = [];
    $studentRows = 0;
    $subjectSlots = [];
    $idIndex = $lastNameIndex = $firstNameIndex = $middleNameIndex = $courseIndex = $yearLevelIndex = null;

    foreach ($rowMatches as $rowMatch) {
        $rowAttrs = xml_attrs($rowMatch[1]);
        $physicalRow = (int) ($rowAttrs['r'] ?? '0');
        $values = xlsx_row_values_from_xml($rowMatch[2], $sharedStrings);
        if (empty($values)) continue;

        if (!$headerRead) {
            foreach ($values as $index => $value) {
                $key = xlsx_normalize_header($value);
                if ($key !== '') $headers[$key] = (int) $index;
            }
            $idIndex = $headers[xlsx_normalize_header('ID')] ?? null;
            $lastNameIndex = $headers[xlsx_normalize_header('LAST NAME')] ?? null;
            $firstNameIndex = $headers[xlsx_normalize_header('FIRST NAME')] ?? null;
            $middleNameIndex = $headers[xlsx_normalize_header('MIDDLE NAME')] ?? null;
            $courseIndex = $headers[xlsx_normalize_header('COURSE')] ?? null;
            $yearLevelIndex = $headers[xlsx_normalize_header('YEARLEVEL')] ?? ($headers[xlsx_normalize_header('YEAR LEVEL')] ?? null);
            $birthDateIndex = $headers[xlsx_normalize_header('BIRTHDATE')] ?? ($headers[xlsx_normalize_header('BIRTH DATE')] ?? ($headers[xlsx_normalize_header('DOB')] ?? null));
            for ($i = 1; $i <= 10; $i++) {
                $subjectSlots[] = [
                    'subject_no' => $i,
                    'subject_index' => $headers[xlsx_normalize_header('SUBJECT' . $i)] ?? null,
                    'description_index' => $headers[xlsx_normalize_header('SUBJECTDESC' . $i)] ?? ($headers[xlsx_normalize_header('SUBJECT DESCRIPTION' . $i)] ?? null),
                    'units_index' => $headers[xlsx_normalize_header('UNITS' . $i)] ?? null,
                    'grade_index' => $headers[xlsx_normalize_header('GRADE' . $i)] ?? null,
                ];
            }

            $missingHeaders = [];
            if ($idIndex === null) $missingHeaders[] = 'ID';
            if ($lastNameIndex === null) $missingHeaders[] = 'LAST NAME';
            if ($firstNameIndex === null) $missingHeaders[] = 'FIRST NAME';
            if ($courseIndex === null) $missingHeaders[] = 'COURSE';
            if ($yearLevelIndex === null) $missingHeaders[] = 'YEARLEVEL';

            $completeSubjectSlots = 0;
            foreach ($subjectSlots as $slot) {
                if ($slot['subject_index'] !== null && $slot['units_index'] !== null && $slot['grade_index'] !== null) {
                    $completeSubjectSlots++;
                }
            }
            if ($completeSubjectSlots === 0) {
                $missingHeaders[] = 'SUBJECT1 / UNITS1 / GRADE1';
            }

            if (!empty($missingHeaders)) {
                json_response([
                    'ok' => false,
                    'message' => 'The uploaded UNO file does not look like the UNO promotional-list format. Missing required column(s): ' . implode(', ', $missingHeaders) . '.',
                    'expected_format' => 'ID, LAST NAME, FIRST NAME, COURSE, YEARLEVEL, optional BIRTHDATE, then SUBJECT1/SUBJECTDESC1/UNITS1/GRADE1 up to SUBJECT10/SUBJECTDESC10/UNITS10/GRADE10.',
                ], 400);
            }

            $headerRead = true;
            continue;
        }

        $studentId = xlsx_from_index($values, $idIndex);
        if (trim($studentId) === '') continue;

        $studentRows++;
        $lastName = xlsx_from_index($values, $lastNameIndex);
        $firstName = xlsx_from_index($values, $firstNameIndex);
        $middleName = xlsx_from_index($values, $middleNameIndex);
        $course = xlsx_from_index($values, $courseIndex);
        $yearLevel = xlsx_from_index($values, $yearLevelIndex);
        $birthDate = xlsx_birthdate_from_index($values, $birthDateIndex);

        foreach ($subjectSlots as $slot) {
            $subject = xlsx_from_index($values, $slot['subject_index']);
            if (trim($subject) === '') continue;
            $parsed[] = [
                'excel_row_number' => $physicalRow,
                'subject_no' => $slot['subject_no'],
                'student_id' => $studentId,
                'last_name' => $lastName,
                'first_name' => $firstName,
                'middle_name' => $middleName,
                'course' => $course,
                'year_level' => $yearLevel,
                'birthdate' => $birthDate,
                'subject_code' => $subject,
                'subject_description' => xlsx_from_index($values, $slot['description_index']),
                'units' => xlsx_from_index($values, $slot['units_index']),
                'excel_grade' => xlsx_from_index($values, $slot['grade_index']),
                'school_year' => $schoolYear,
                'semester' => $semester,
                'period_id' => $periodId,
            ];
        }
    }

    if ($studentRows === 0 || count($parsed) === 0) {
        json_response([
            'ok' => false,
            'message' => 'The UNO file was opened, but no UNO student subject-grade rows were found. Please verify that the first worksheet is the promotional list and that it contains ID and SUBJECT/UNITS/GRADE columns.',
        ], 400);
    }

    json_response([
        'ok' => true,
        'file_name' => $fileName,
        'student_rows' => $studentRows,
        'record_count' => count($parsed),
        'validated_format' => 'uno_promotional_list',
        'rows' => $parsed,
        'parser' => 'server_pure_php_zip_xml',
    ]);
} catch (Throwable $e) {
    json_response([
        'ok' => false,
        'message' => $e->getMessage(),
        'hint' => 'This parser reads the first XLSX worksheet using pure PHP ZIP/XML text parsing, so no Composer package or PHP ZipArchive extension is required.',
    ], 500);
}
