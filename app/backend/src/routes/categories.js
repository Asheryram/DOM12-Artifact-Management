const express = require('express');
const router  = express.Router();
const pool    = require('../db');

router.get('/', async (req, res) => {
  try {
    const { type } = req.query;
    let sql = 'SELECT c.*, COUNT(t.id) AS transaction_count FROM categories c LEFT JOIN transactions t ON c.id = t.category_id';
    const params = [];
    if (type) { sql += ' WHERE c.type = ?'; params.push(type); }
    sql += ' GROUP BY c.id ORDER BY c.type, c.name';
    const [rows] = await pool.query(sql, params);
    res.json({ success: true, data: rows });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

router.post('/', async (req, res) => {
  try {
    const { name, type, color = '#6366f1', icon = 'circle' } = req.body;
    if (!name || !type) return res.status(400).json({ success: false, error: 'name and type are required' });
    const [result] = await pool.query(
      'INSERT INTO categories (name, type, color, icon) VALUES (?, ?, ?, ?)',
      [name, type, color, icon]
    );
    const [rows] = await pool.query('SELECT * FROM categories WHERE id = ?', [result.insertId]);
    res.status(201).json({ success: true, data: rows[0] });
  } catch (err) {
    if (err.code === 'ER_DUP_ENTRY') return res.status(409).json({ success: false, error: 'Category already exists' });
    res.status(500).json({ success: false, error: err.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    const [txns] = await pool.query('SELECT COUNT(*) AS cnt FROM transactions WHERE category_id = ?', [req.params.id]);
    if (txns[0].cnt > 0) return res.status(409).json({ success: false, error: 'Cannot delete category with existing transactions' });
    const [result] = await pool.query('DELETE FROM categories WHERE id = ?', [req.params.id]);
    if (result.affectedRows === 0) return res.status(404).json({ success: false, error: 'Category not found' });
    res.json({ success: true, data: { deleted: true } });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
