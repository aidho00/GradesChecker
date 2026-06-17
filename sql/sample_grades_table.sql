-- Optional sample table only.
-- Use this if you want to test the checker before mapping it to your real cfcissmsdb grade table.

CREATE TABLE IF NOT EXISTS grades (
  id INT AUTO_INCREMENT PRIMARY KEY,
  student_id VARCHAR(50) NOT NULL,
  subject_code VARCHAR(50) NOT NULL,
  school_year VARCHAR(20) NOT NULL,
  semester VARCHAR(20) NOT NULL,
  grading_period VARCHAR(50) NOT NULL,
  grade VARCHAR(20) NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_grade_lookup (student_id, subject_code, school_year, semester, grading_period)
);

INSERT INTO grades (student_id, subject_code, school_year, semester, grading_period, grade) VALUES
('1802085', 'CA 1', '2019-2020', '1ST SEM', 'FINAL', '1.2'),
('1802085', 'CRIMTICS 3', '2019-2020', '1ST SEM', 'FINAL', '1.2'),
('1900101', 'CC101', '2019-2020', '1ST SEM', 'FINAL', '1.1');
