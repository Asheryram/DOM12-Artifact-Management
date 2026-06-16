import React, { useState, useEffect } from 'react';
import axios from 'axios';

const API = import.meta.env.VITE_API_URL || '';
const inputStyle = { background: '#0f1117', border: '1px solid #2d3148', borderRadius: 8, padding: '8px 12px', color: '#e2e8f0', width: '100%', boxSizing: 'border-box' };
const btnStyle   = { background: '#6366f1', color: '#fff', border: 'none', borderRadius: 8, padding: '10px 20px', cursor: 'pointer', fontWeight: 600 };

export default function Transactions() {
  const [txns, setTxns]     = useState([]);
  const [cats, setCats]     = useState([]);
  const [filter, setFilter] = useState('all');
  const [form, setForm]     = useState({ type: 'expense', amount: '', description: '', category_id: '', transaction_date: new Date().toISOString().slice(0, 10) });
  const [error, setError]   = useState(null);

  const load = async () => {
    const q = filter !== 'all' ? `?type=${filter}` : '';
    const [t, c] = await Promise.all([
      axios.get(`${API}/api/transactions${q}`),
      axios.get(`${API}/api/categories`)
    ]);
    setTxns(t.data.data);
    setCats(c.data.data);
  };

  useEffect(() => { load(); }, [filter]);

  const submit = async e => {
    e.preventDefault(); setError(null);
    try {
      await axios.post(`${API}/api/transactions`, form);
      setForm({ ...form, amount: '', description: '' });
      load();
    } catch (err) { setError(err.response?.data?.error || err.message); }
  };

  const del = async id => {
    if (!confirm('Delete this transaction?')) return;
    await axios.delete(`${API}/api/transactions/${id}`);
    load();
  };

  const filteredCats = cats.filter(c => c.type === form.type);
  const fmt = n => '$' + parseFloat(n).toLocaleString('en-US', { minimumFractionDigits: 2 });

  return (
    <div>
      <h1 style={{ marginBottom: 24, fontSize: 24, fontWeight: 700 }}>Transactions</h1>
      <div style={{ display: 'grid', gridTemplateColumns: '340px 1fr', gap: 24 }}>
        <div style={{ background: '#1a1d27', borderRadius: 12, padding: 24 }}>
          <h2 style={{ marginBottom: 16, fontSize: 16, fontWeight: 600 }}>Add Transaction</h2>
          {error && <div style={{ color: '#ef4444', marginBottom: 12, fontSize: 14 }}>{error}</div>}
          <form onSubmit={submit} style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            <div style={{ display: 'flex', gap: 8 }}>
              {['income', 'expense'].map(t => (
                <button type="button" key={t} onClick={() => setForm({ ...form, type: t, category_id: '' })}
                  style={{ ...btnStyle, flex: 1, background: form.type === t ? '#6366f1' : '#2d3148' }}>
                  {t.charAt(0).toUpperCase() + t.slice(1)}
                </button>
              ))}
            </div>
            <input style={inputStyle} type="number" step="0.01" min="0.01" placeholder="Amount" value={form.amount} onChange={e => setForm({ ...form, amount: e.target.value })} required />
            <input style={inputStyle} type="text" placeholder="Description (optional)" value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} />
            <select style={inputStyle} value={form.category_id} onChange={e => setForm({ ...form, category_id: e.target.value })} required>
              <option value="">Select category</option>
              {filteredCats.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
            <input style={inputStyle} type="date" value={form.transaction_date} onChange={e => setForm({ ...form, transaction_date: e.target.value })} required />
            <button type="submit" style={btnStyle}>Add Transaction</button>
          </form>
        </div>

        <div style={{ background: '#1a1d27', borderRadius: 12, padding: 24 }}>
          <div style={{ display: 'flex', gap: 8, marginBottom: 16 }}>
            {['all', 'income', 'expense'].map(f => (
              <button key={f} onClick={() => setFilter(f)}
                style={{ ...btnStyle, background: filter === f ? '#6366f1' : '#2d3148', padding: '6px 16px', fontSize: 13 }}>
                {f.charAt(0).toUpperCase() + f.slice(1)}
              </button>
            ))}
          </div>
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 14 }}>
            <thead>
              <tr style={{ color: '#64748b', borderBottom: '1px solid #2d3148' }}>
                <th style={{ textAlign: 'left', padding: '8px 0' }}>Date</th>
                <th style={{ textAlign: 'left', padding: '8px 0' }}>Category</th>
                <th style={{ textAlign: 'left', padding: '8px 0' }}>Description</th>
                <th style={{ textAlign: 'right', padding: '8px 0' }}>Amount</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {txns.map(t => (
                <tr key={t.id} style={{ borderBottom: '1px solid #2d3148' }}>
                  <td style={{ padding: '10px 0', color: '#94a3b8' }}>{t.transaction_date}</td>
                  <td style={{ padding: '10px 0' }}>
                    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
                      <span style={{ width: 8, height: 8, borderRadius: '50%', background: t.category_color, flexShrink: 0 }} />
                      {t.category_name}
                    </span>
                  </td>
                  <td style={{ padding: '10px 0', color: '#64748b' }}>{t.description}</td>
                  <td style={{ padding: '10px 0', textAlign: 'right', color: t.type === 'income' ? '#22c55e' : '#ef4444', fontWeight: 600 }}>
                    {t.type === 'income' ? '+' : '-'}{fmt(t.amount)}
                  </td>
                  <td style={{ padding: '10px 0', textAlign: 'right' }}>
                    <button onClick={() => del(t.id)} style={{ background: 'none', border: 'none', color: '#ef4444', cursor: 'pointer', fontSize: 16 }}>x</button>
                  </td>
                </tr>
              ))}
              {txns.length === 0 && (
                <tr><td colSpan="5" style={{ padding: '20px 0', color: '#64748b', textAlign: 'center' }}>No transactions found.</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
