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
 * Exact HEMIS table mapping used by the checker.
 * Main matching path:
 * Excel student ID or first/last name -> tbl_student
 * Excel subject code -> tbl_subject
 * Selected period -> tbl_period.period_id
 * Grade existence -> tbl_students_grades
 */
const STUDENT_TABLE = 'tbl_student';
const SUBJECT_TABLE = 'tbl_subject';
const COURSE_TABLE = 'tbl_course';
const PERIOD_TABLE = 'tbl_period';
const GRADES_TABLE = 'tbl_students_grades';
