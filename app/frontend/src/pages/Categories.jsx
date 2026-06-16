import React, { useState, useEffect } from 'react';
import axios from 'axios';

const API = import.meta.env.VITE_API_URL || '';
const inputStyle = { background: '#0f1117', border: '1px solid #2d3148', borderRadius: 8, padding: '8px 12px', color: '#e2e8f0', width: '100%', boxSizing: 'border-box' };
const btnStyle   = { background: '#6366f1', color: '#fff', border: 'none', borderRadius: 8, padding: '10px 20px', cursor: 'pointer', fontWeight: 600 };
const PALETTE    = ['#22c55e','#3b82f6','#a855f7','#f59e0b','#6366f1','#ef4444','#f97316','#eab308','#06b6d4','#ec4899'];

export default function Categories() {
  const [cats, setCats]   = useState([]);
  const [form, setForm]   = useState({ name: '', type: 'income', color: '#6366f1' });
  const [error, setError] = useState(null);

  const load = () => axios.get(`${API}/api/categories`).then(r => setCats(r.data.data));
  useEffect(() => { load(); }, []);

  const submit = async e => {
    e.preventDefault(); setError(null);
    try {
      await axios.post(`${API}/api/categories`, form);
      setForm({ name: '', type: form.type, color: '#6366f1' });
      load();
    } catch (err) { setError(err.response?.data?.error || err.message); }
  };

  const del = async id => {
    try { await axios.delete(`${API}/api/categories/${id}`); load(); }
    catch (err) { alert(err.response?.data?.error || err.message); }
  };

  const income  = cats.filter(c => c.type === 'income');
  const expense = cats.filter(c => c.type === 'expense');

  return (
    <div>
      <h1 style={{ marginBottom: 24, fontSize: 24, fontWeight: 700 }}>Categories</h1>

      <div style={{ background: '#1a1d27', borderRadius: 12, padding: 24, marginBottom: 24 }}>
        <h2 style={{ marginBottom: 16, fontSize: 16, fontWeight: 600 }}>Add Category</h2>
        {error && <div style={{ color: '#ef4444', marginBottom: 12, fontSize: 14 }}>{error}</div>}
        <form onSubmit={submit} style={{ display: 'flex', flexWrap: 'wrap', gap: 12, alignItems: 'flex-end' }}>
          <input style={{ ...inputStyle, width: 200 }} placeholder="Category name" value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} required />
          <div style={{ display: 'flex', gap: 8 }}>
            {['income', 'expense'].map(t => (
              <button type="button" key={t} onClick={() => setForm({ ...form, type: t })}
                style={{ ...btnStyle, background: form.type === t ? '#6366f1' : '#2d3148', padding: '8px 16px', fontSize: 13 }}>
                {t.charAt(0).toUpperCase() + t.slice(1)}
              </button>
            ))}
          </div>
          <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
            {PALETTE.map(c => (
              <div key={c} onClick={() => setForm({ ...form, color: c })}
                style={{ width: 22, height: 22, borderRadius: '50%', background: c, cursor: 'pointer',
                  outline: form.color === c ? '3px solid #fff' : 'none', outlineOffset: 2 }} />
            ))}
          </div>
          <button type="submit" style={btnStyle}>Add</button>
        </form>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 24 }}>
        {[['Income Categories', income, '#22c55e'], ['Expense Categories', expense, '#ef4444']].map(([title, list, accent]) => (
          <div key={title} style={{ background: '#1a1d27', borderRadius: 12, padding: 24 }}>
            <h2 style={{ marginBottom: 16, fontSize: 16, fontWeight: 600, color: accent }}>{title}</h2>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              {list.map(c => (
                <div key={c.id} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '10px 12px', background: '#0f1117', borderRadius: 8 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                    <div style={{ width: 14, height: 14, borderRadius: '50%', background: c.color, flexShrink: 0 }} />
                    <span style={{ fontSize: 14 }}>{c.name}</span>
                    <span style={{ fontSize: 12, color: '#64748b' }}>({c.transaction_count})</span>
                  </div>
                  <button onClick={() => del(c.id)} disabled={c.transaction_count > 0}
                    style={{ background: 'none', border: 'none', cursor: c.transaction_count > 0 ? 'not-allowed' : 'pointer',
                      color: c.transaction_count > 0 ? '#374151' : '#ef4444', fontSize: 16 }}>x</button>
                </div>
              ))}
              {list.length === 0 && <div style={{ color: '#64748b', fontSize: 14 }}>No categories yet.</div>}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
