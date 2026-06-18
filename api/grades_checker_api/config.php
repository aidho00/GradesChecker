<?php
/**
 * Grades Checker API configuration.
 * Works in WAMP or XAMPP. Change only the connection values if needed.
 */

const DB_HOST = '127.0.0.1';
const DB_PORT = '3306';
const DB_NAME = 'cfcissmsdb';
const DB_USER = 'root';
const DB_PASS = '';
const DB_CHARSET = 'utf8mb4';


/**
 * Simple Grades Checker access settings.
 * Leave the allowed lists empty to permit any active tbl_user_account user.
 * Add specific ua_id values or usernames to limit this module to selected users only.
 */
const GRADE_CHECKER_ALLOWED_USER_IDS = [];
const GRADE_CHECKER_ALLOWED_USERNAMES = [];
const GRADE_CHECKER_TOKEN_SECRET = 'change-this-local-secret';
const GRADE_CHECKER_TOKEN_TTL_SECONDS = 28800;

/**
 * Exact UNO/SMS table mapping used by the checker.
 * Main matching path:
 * UNO student ID or first/last name -> student records
 * UNO subject code -> subject records
 * Selected period -> tbl_period.period_id
 * Grade existence -> tbl_students_grades
 */
const STUDENT_TABLE = 'tbl_student';
const SUBJECT_TABLE = 'tbl_subject';
const COURSE_TABLE = 'tbl_course';
const PERIOD_TABLE = 'tbl_period';
const GRADES_TABLE = 'tbl_students_grades';
