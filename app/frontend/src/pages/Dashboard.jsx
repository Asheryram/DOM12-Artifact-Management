import React, { useState, useEffect } from 'react';
import { BarChart, Bar, XAxis, YAxis, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import axios from 'axios';

const API = import.meta.env.VITE_API_URL || '';
const card = { background: '#1a1d27', borderRadius: 12, padding: 24 };

export default function Dashboard() {
  const [summary, setSummary] = useState(null);
  const [recent, setRecent]   = useState([]);
  const [error, setError]     = useState(null);

  useEffect(() => {
    Promise.all([
      axios.get(`${API}/api/summary`),
      axios.get(`${API}/api/transactions?limit=10`)
    ]).then(([s, t]) => {
      setSummary(s.data.data);
      setRecent(t.data.data);
    }).catch(err => setError(err.message));
  }, []);

  if (error)    return <div style={{ color: '#ef4444' }}>Error: {error}</div>;
  if (!summary) return <div style={{ color: '#94a3b8' }}>Loading...</div>;

  const { allTime, thisMonth, monthly } = summary;
  const fmt = n => '$' + parseFloat(n || 0).toLocaleString('en-US', { minimumFractionDigits: 2 });

  return (
    <div>
      <h1 style={{ marginBottom: 24, fontSize: 24, fontWeight: 700 }}>Dashboard</h1>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4,1fr)', gap: 16, marginBottom: 32 }}>
        <div style={card}>
          <div style={{ color: '#94a3b8', marginBottom: 8, fontSize: 13 }}>Total Income</div>
          <div style={{ fontSize: 24, fontWeight: 700, color: '#22c55e' }}>{fmt(allTime.total_income)}</div>
        </div>
        <div style={card}>
          <div style={{ color: '#94a3b8', marginBottom: 8, fontSize: 13 }}>Total Expenses</div>
          <div style={{ fontSize: 24, fontWeight: 700, color: '#ef4444' }}>{fmt(allTime.total_expense)}</div>
        </div>
        <div style={card}>
          <div style={{ color: '#94a3b8', marginBottom: 8, fontSize: 13 }}>Net Balance</div>
          <div style={{ fontSize: 24, fontWeight: 700, color: parseFloat(allTime.net_balance) >= 0 ? '#22c55e' : '#ef4444' }}>
            {fmt(allTime.net_balance)}
          </div>
        </div>
        <div style={card}>
          <div style={{ color: '#94a3b8', marginBottom: 8, fontSize: 13 }}>This Month Txns</div>
          <div style={{ fontSize: 24, fontWeight: 700, color: '#6366f1' }}>{thisMonth.month_transactions}</div>
        </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 24 }}>
        <div style={card}>
          <h2 style={{ marginBottom: 16, fontSize: 16, fontWeight: 600 }}>Monthly Income vs Expense</h2>
          <ResponsiveContainer width="100%" height={220}>
            <BarChart data={monthly}>
              <XAxis dataKey="month" tick={{ fill: '#94a3b8', fontSize: 12 }} />
              <YAxis tick={{ fill: '#94a3b8', fontSize: 12 }} />
              <Tooltip contentStyle={{ background: '#1a1d27', border: 'none', color: '#e2e8f0' }} />
              <Legend />
              <Bar dataKey="income"  fill="#22c55e" name="Income" />
              <Bar dataKey="expense" fill="#ef4444" name="Expense" />
            </BarChart>
          </ResponsiveContainer>
        </div>

        <div style={card}>
          <h2 style={{ marginBottom: 16, fontSize: 16, fontWeight: 600 }}>Recent Transactions</h2>
          {recent.map(t => (
            <div key={t.id} style={{ display: 'flex', justifyContent: 'space-between', padding: '8px 0', borderBottom: '1px solid #2d3148' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <div style={{ width: 10, height: 10, borderRadius: '50%', background: t.category_color }} />
                <div>
                  <div style={{ fontSize: 14 }}>{t.description || t.category_name}</div>
                  <div style={{ fontSize: 12, color: '#64748b' }}>{t.transaction_date}</div>
                </div>
              </div>
              <div style={{ color: t.type === 'income' ? '#22c55e' : '#ef4444', fontWeight: 600 }}>
                {t.type === 'income' ? '+' : '-'}{fmt(t.amount)}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
