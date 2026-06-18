<?php
/**
 * Lightweight access-only authentication for Grades Checker.
 * Uses existing tbl_user_account credentials and a signed bearer token.
 */

function base64url_encode(string $data): string
{
    return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
}

function base64url_decode(string $data): string|false
{
    $padding = strlen($data) % 4;
    if ($padding > 0) {
        $data .= str_repeat('=', 4 - $padding);
    }
    return base64_decode(strtr($data, '-_', '+/'), true);
}

function grade_checker_secret(): string
{
    $secret = defined('GRADE_CHECKER_TOKEN_SECRET') ? (string) GRADE_CHECKER_TOKEN_SECRET : '';
    if ($secret === '' || $secret === 'change-this-local-secret') {
        // Stable local fallback so the app still works after copy/paste setup.
        // For production/intranet use, set GRADE_CHECKER_TOKEN_SECRET in config.php.
        $secret = hash('sha256', DB_NAME . '|' . DB_USER . '|grades-checker-local-token');
    }
    return $secret;
}

function grade_checker_sign(string $payload): string
{
    return base64url_encode(hash_hmac('sha256', $payload, grade_checker_secret(), true));
}

function create_grade_checker_token(array $user): string
{
    $ttl = defined('GRADE_CHECKER_TOKEN_TTL_SECONDS') ? (int) GRADE_CHECKER_TOKEN_TTL_SECONDS : 28800;
    if ($ttl < 900) $ttl = 900;

    $payload = [
        'ua_id' => (int) $user['ua_id'],
        'username' => (string) $user['ua_user_name'],
        'display_name' => display_name_from_user($user),
        'role' => trim((string) ($user['ua_account_type'] ?? '')) ?: 'user',
        'iat' => time(),
        'exp' => time() + $ttl,
    ];

    $encoded = base64url_encode(json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
    return $encoded . '.' . grade_checker_sign($encoded);
}

function read_bearer_token(): string
{
    $header = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
    if ($header === '' && function_exists('apache_request_headers')) {
        $headers = apache_request_headers();
        foreach ($headers as $name => $value) {
            if (strcasecmp((string) $name, 'Authorization') === 0) {
                $header = (string) $value;
                break;
            }
        }
    }

    if (preg_match('/Bearer\s+(.+)/i', $header, $matches)) {
        return trim($matches[1]);
    }
    return '';
}

function verify_grade_checker_token(?string $token = null): ?array
{
    $token = $token ?? read_bearer_token();
    if ($token === '' || !str_contains($token, '.')) return null;

    [$payloadPart, $signature] = explode('.', $token, 2);
    $expected = grade_checker_sign($payloadPart);
    if (!hash_equals($expected, $signature)) return null;

    $json = base64url_decode($payloadPart);
    if ($json === false) return null;

    $payload = json_decode($json, true);
    if (!is_array($payload)) return null;
    if ((int) ($payload['exp'] ?? 0) < time()) return null;

    return $payload;
}

function require_grade_checker_auth(): array
{
    $payload = verify_grade_checker_token();
    if ($payload === null) {
        json_response(['ok' => false, 'message' => 'Login required. Please sign in again.'], 401);
    }
    return $payload;
}

function display_name_from_user(array $user): string
{
    $parts = [
        trim((string) ($user['ua_first_name'] ?? '')),
        trim((string) ($user['ua_middle_name'] ?? '')),
        trim((string) ($user['ua_last_name'] ?? '')),
    ];
    $name = trim(preg_replace('/\s+/', ' ', implode(' ', array_filter($parts))) ?? '');
    return $name !== '' ? $name : (string) ($user['ua_user_name'] ?? 'User');
}

function is_allowed_grade_checker_user(array $user): bool
{
    $allowedIds = defined('GRADE_CHECKER_ALLOWED_USER_IDS') ? GRADE_CHECKER_ALLOWED_USER_IDS : [];
    $allowedNames = defined('GRADE_CHECKER_ALLOWED_USERNAMES') ? GRADE_CHECKER_ALLOWED_USERNAMES : [];

    $allowedIds = is_array($allowedIds) ? array_map('strval', $allowedIds) : [];
    $allowedNames = is_array($allowedNames) ? array_map('strtolower', array_map('strval', $allowedNames)) : [];

    // Empty allow-lists mean any active tbl_user_account user can sign in.
    if (empty($allowedIds) && empty($allowedNames)) return true;

    $uaId = (string) ($user['ua_id'] ?? '');
    $username = strtolower((string) ($user['ua_user_name'] ?? ''));

    return in_array($uaId, $allowedIds, true) || in_array($username, $allowedNames, true);
}

function is_active_sms_user(array $user): bool
{
    $status = strtolower(trim((string) ($user['ua_status'] ?? '')));
    return $status === '' || $status === 'active' || $status === 'open' || $status === 'enabled';
}

function password_matches_sms_user(string $password, string $stored): bool
{
    $stored = trim($stored);
    if ($stored === '') return false;

    if (password_get_info($stored)['algo'] !== 0 && password_verify($password, $stored)) {
        return true;
    }

    // Compatibility for older SMS password storage. Prefer password_hash() later.
    if (hash_equals($stored, $password)) return true;
    if (strlen($stored) === 32 && hash_equals(strtolower($stored), md5($password))) return true;
    if (strlen($stored) === 40 && hash_equals(strtolower($stored), sha1($password))) return true;

    return false;
}
