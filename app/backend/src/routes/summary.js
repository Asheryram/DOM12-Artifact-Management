const express = require('express');
const router  = express.Router();
const pool    = require('../db');

router.get('/', async (req, res) => {
  try {
    const [[allTime]] = await pool.query(`
      SELECT
        SUM(CASE WHEN type='income'  THEN amount ELSE 0 END) AS total_income,
        SUM(CASE WHEN type='expense' THEN amount ELSE 0 END) AS total_expense,
        SUM(CASE WHEN type='income'  THEN amount ELSE -amount END) AS net_balance,
        COUNT(*) AS total_transactions
      FROM transactions
    `);

    const [[thisMonth]] = await pool.query(`
      SELECT
        SUM(CASE WHEN type='income'  THEN amount ELSE 0 END) AS month_income,
        SUM(CASE WHEN type='expense' THEN amount ELSE 0 END) AS month_expense,
        COUNT(*) AS month_transactions
      FROM transactions
      WHERE YEAR(transaction_date) = YEAR(CURDATE())
        AND MONTH(transaction_date) = MONTH(CURDATE())
    `);

    const [monthly] = await pool.query(`
      SELECT
        DATE_FORMAT(transaction_date, '%Y-%m') AS month,
        SUM(CASE WHEN type='income'  THEN amount ELSE 0 END) AS income,
        SUM(CASE WHEN type='expense' THEN amount ELSE 0 END) AS expense
      FROM transactions
      WHERE transaction_date >= DATE_SUB(CURDATE(), INTERVAL 6 MONTH)
      GROUP BY DATE_FORMAT(transaction_date, '%Y-%m')
      ORDER BY month ASC
    `);

    res.json({ success: true, data: { allTime, thisMonth, monthly } });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
