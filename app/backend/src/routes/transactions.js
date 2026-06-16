const express = require('express');
const router  = express.Router();
const pool    = require('../db');

router.get('/', async (req, res) => {
  try {
    const { type, limit = 50, offset = 0 } = req.query;
    let sql = `
      SELECT t.id, t.type, t.amount, t.description, t.transaction_date, t.created_at,
             c.name AS category_name, c.color AS category_color, c.icon AS category_icon
      FROM transactions t
      JOIN categories c ON t.category_id = c.id
    `;
    const params = [];
    if (type) { sql += ' WHERE t.type = ?'; params.push(type); }
    sql += ' ORDER BY t.transaction_date DESC, t.created_at DESC LIMIT ? OFFSET ?';
    params.push(parseInt(limit), parseInt(offset));
    const [rows] = await pool.query(sql, params);
    res.json({ success: true, data: rows });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

router.post('/', async (req, res) => {
  try {
    const { type, amount, description, category_id, transaction_date } = req.body;
    if (!type || !amount || !category_id) {
      return res.status(400).json({ success: false, error: 'type, amount and category_id are required' });
    }
    const [result] = await pool.query(
      'INSERT INTO transactions (type, amount, description, category_id, transaction_date) VALUES (?, ?, ?, ?, ?)',
      [type, amount, description || null, category_id, transaction_date || new Date().toISOString().slice(0, 10)]
    );
    const [rows] = await pool.query('SELECT * FROM transactions WHERE id = ?', [result.insertId]);
    res.status(201).json({ success: true, data: rows[0] });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    const [result] = await pool.query('DELETE FROM transactions WHERE id = ?', [req.params.id]);
    if (result.affectedRows === 0) return res.status(404).json({ success: false, error: 'Transaction not found' });
    res.json({ success: true, data: { deleted: true } });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
