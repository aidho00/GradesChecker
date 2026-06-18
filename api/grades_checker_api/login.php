<?php
require_once __DIR__ . '/bootstrap.php';
require_once __DIR__ . '/auth.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    json_response(['ok' => false, 'message' => 'POST request required.'], 405);
}

try {
    $raw = file_get_contents('php://input') ?: '';
    $body = json_decode($raw, true);
    if (!is_array($body)) {
        json_response(['ok' => false, 'message' => 'Invalid JSON request body.'], 400);
    }

    $username = trim((string) ($body['username'] ?? ''));
    $password = (string) ($body['password'] ?? '');

    if ($username === '' || $password === '') {
        json_response(['ok' => false, 'message' => 'Username and password are required.'], 400);
    }

    $pdo = db();
    $stmt = $pdo->prepare(
        'SELECT ua_id, ua_user_name, ua_password, ua_first_name, ua_middle_name, ua_last_name, ua_status, ua_account_type
         FROM tbl_user_account
         WHERE ua_user_name = :username
         LIMIT 1'
    );
    $stmt->execute([':username' => $username]);
    $user = $stmt->fetch();

    if (!$user || !password_matches_sms_user($password, (string) ($user['ua_password'] ?? ''))) {
        json_response(['ok' => false, 'message' => 'Invalid username or password.'], 401);
    }

    if (!is_active_sms_user($user)) {
        json_response(['ok' => false, 'message' => 'This SMS user account is not active.'], 403);
    }

    if (!is_allowed_grade_checker_user($user)) {
        json_response(['ok' => false, 'message' => 'This account is not allowed to access Grades Checker.'], 403);
    }

    $token = create_grade_checker_token($user);
    json_response([
        'ok' => true,
        'token' => $token,
        'user' => [
            'ua_id' => (int) $user['ua_id'],
            'username' => (string) $user['ua_user_name'],
            'display_name' => display_name_from_user($user),
            'role' => trim((string) ($user['ua_account_type'] ?? '')) ?: 'user',
        ],
    ]);
} catch (Throwable $e) {
    json_response(['ok' => false, 'message' => $e->getMessage()], 500);
}
