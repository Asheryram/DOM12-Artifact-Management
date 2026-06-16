CREATE DATABASE IF NOT EXISTS fincorpdb;
USE fincorpdb;

CREATE TABLE IF NOT EXISTS categories (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  name        VARCHAR(100) NOT NULL,
  type        ENUM('income', 'expense') NOT NULL,
  color       VARCHAR(7) DEFAULT '#6366f1',
  icon        VARCHAR(50) DEFAULT 'circle',
  created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_category_name_type (name, type)
);

CREATE TABLE IF NOT EXISTS transactions (
  id               INT AUTO_INCREMENT PRIMARY KEY,
  type             ENUM('income', 'expense') NOT NULL,
  amount           DECIMAL(12, 2) NOT NULL,
  description      VARCHAR(255),
  category_id      INT NOT NULL,
  transaction_date DATE NOT NULL DEFAULT (CURRENT_DATE),
  created_at       DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (category_id) REFERENCES categories(id)
);

INSERT IGNORE INTO categories (name, type, color) VALUES
  ('Salary',        'income',  '#22c55e'),
  ('Freelance',     'income',  '#3b82f6'),
  ('Investment',    'income',  '#a855f7'),
  ('Gift',          'income',  '#f59e0b'),
  ('Other Income',  'income',  '#6366f1'),
  ('Rent',          'expense', '#ef4444'),
  ('Food',          'expense', '#f97316'),
  ('Transport',     'expense', '#eab308'),
  ('Utilities',     'expense', '#06b6d4'),
  ('Healthcare',    'expense', '#ec4899'),
  ('Shopping',      'expense', '#8b5cf6'),
  ('Entertainment', 'expense', '#64748b'),
  ('Other Expense', 'expense', '#374151');
