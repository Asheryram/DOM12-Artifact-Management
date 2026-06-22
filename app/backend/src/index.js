require('dotenv').config();
const fs      = require('fs');
const path    = require('path');
const express = require('express');
const cors    = require('cors');
const helmet  = require('helmet');

const transactionsRouter = require('./routes/transactions');
const categoriesRouter   = require('./routes/categories');
const summaryRouter      = require('./routes/summary');
const pool               = require('./db');

const app  = express();
const PORT = process.env.PORT || 8080;

async function runMigrations() {
  const sql = fs.readFileSync(path.join(__dirname, 'migrations', 'init.sql'), 'utf8');
  const statements = sql.split(';').map(s => s.trim()).filter(Boolean);
  for (const stmt of statements) {
    await pool.query(stmt);
  }
  console.log('Migrations complete.');
}

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

runMigrations()
  .then(() => app.listen(PORT, () => console.log(`FinCorp API running on port ${PORT}`)))
  .catch(err => { console.error('Migration failed:', err); process.exit(1); });
