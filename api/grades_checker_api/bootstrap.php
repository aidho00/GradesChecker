<?php
require_once __DIR__ . '/config.php';

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Accept, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

function json_response(array $payload, int $statusCode = 200): void
{
    http_response_code($statusCode);
    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function db(): PDO
{
    $dsn = sprintf('mysql:host=%s;port=%s;dbname=%s;charset=%s', DB_HOST, DB_PORT, DB_NAME, DB_CHARSET);
    return new PDO($dsn, DB_USER, DB_PASS, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]);
}

function quote_identifier(string $identifier): string
{
    if (!preg_match('/^[A-Za-z0-9_]+$/', $identifier)) {
        throw new InvalidArgumentException("Invalid SQL identifier: {$identifier}");
    }
    return '`' . $identifier . '`';
}

function normalize_value(mixed $value): string
{
    $text = trim((string) $value);
    $text = preg_replace('/\s+/', ' ', $text) ?? $text;
    return mb_strtoupper($text, 'UTF-8');
}

function normalize_grade(mixed $value): string
{
    $text = trim((string) $value);
    if ($text === '') return '';
    if (is_numeric($text)) {
        return rtrim(rtrim(number_format((float) $text, 4, '.', ''), '0'), '.');
    }
    return normalize_value($text);
}
