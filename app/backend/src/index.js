require('dotenv').config();
const express = require('express');
const cors    = require('cors');
const helmet  = require('helmet');

const transactionsRouter = require('./routes/transactions');
const categoriesRouter   = require('./routes/categories');
const summaryRouter      = require('./routes/summary');
const pool               = require('./db');

const app  = express();
const PORT = process.env.PORT || 8080;

app.use(helmet());
app.use(cors({ origin: process.env.FRONTEND_URL || '*' }));
app.use(express.json());

app.get('/api/health', async (req, res) => {
  try {
    const [rows] = await pool.query('SELECT 1 AS ok');
    res.json({ success: true, data: { status: 'healthy', db: rows[0].ok === 1 } });
  } catch (err) {
    res.status(503).json({ success: false, error: 'Database unreachable', detail: err.message });
  }
});

app.use('/api/transactions', transactionsRouter);
app.use('/api/categories',   categoriesRouter);
app.use('/api/summary',      summaryRouter);

app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ success: false, error: 'Internal server error' });
});

app.listen(PORT, () => console.log(`FinCorp API running on port ${PORT}`));
