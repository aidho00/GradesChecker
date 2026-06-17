<?php
/**
 * Grades Checker API configuration.
 *
 * This folder works in BOTH:
 * - WAMP:  C:\wamp64\www\grades_checker_api
 * - XAMPP: C:\xampp\htdocs\grades_checker_api
 *
 * Flutter Web should never connect directly to MySQL because browser apps would expose
 * database credentials. Keep credentials here in PHP and let Flutter call this API.
 */

const DB_HOST = '127.0.0.1';
const DB_PORT = '3306';
const DB_NAME = 'cfcissmsdb';
const DB_USER = 'root';
const DB_PASS = '';
const DB_CHARSET = 'utf8mb4';

/**
 * Student matching options:
 * - 'id_or_name'  = first tries Excel ID, then FIRST NAME + LAST NAME
 * - 'name_only'   = ignores Excel ID and matches FIRST NAME + LAST NAME
 * - 'id_only'     = uses Excel ID only
 *
 * For your current plan, id_or_name is a safe default because it supports the Excel ID
 * while still honoring your first-name/last-name cross-check idea.
 */
const STUDENT_MATCH_MODE = 'id_or_name';

/**
 * Period matching options:
 * - If Flutter sends period_id, that is used first.
 * - Otherwise the API uses academic_year + semester text against tbl_period.period_name
 *   and tbl_period.period_semester, including combined labels like 2019-2020-1ST SEM.
 */
const ALLOW_PERIOD_TEXT_FALLBACK = true;

/**
 * Optional: require the course from Excel to match tbl_course.
 * Usually keep false because the Excel COURSE is a long name while tbl_course also has
 * short course_code values.
 */
const REQUIRE_COURSE_MATCH = false;
