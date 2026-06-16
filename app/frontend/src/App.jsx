import React from 'react';
import { BrowserRouter, Routes, Route, NavLink } from 'react-router-dom';
import Dashboard    from './pages/Dashboard';
import Transactions from './pages/Transactions';
import Categories   from './pages/Categories';

const navStyle = { color: '#94a3b8', textDecoration: 'none', padding: '10px 16px', display: 'block', borderRadius: '8px' };
const activeStyle = { ...navStyle, background: '#6366f1', color: '#fff' };

export default function App() {
  return (
    <BrowserRouter>
      <div style={{ display: 'flex', minHeight: '100vh', background: '#0f1117', color: '#e2e8f0', fontFamily: 'Inter, sans-serif' }}>
        <nav style={{ width: 220, background: '#1a1d27', padding: '24px 12px', display: 'flex', flexDirection: 'column', gap: 4 }}>
          <div style={{ padding: '0 16px 24px', fontSize: 18, fontWeight: 700, color: '#6366f1' }}>FinCorp</div>
          <NavLink to="/"             style={({ isActive }) => isActive ? activeStyle : navStyle} end>Dashboard</NavLink>
          <NavLink to="/transactions" style={({ isActive }) => isActive ? activeStyle : navStyle}>Transactions</NavLink>
          <NavLink to="/categories"   style={({ isActive }) => isActive ? activeStyle : navStyle}>Categories</NavLink>
        </nav>
        <main style={{ flex: 1, padding: 32, overflowY: 'auto' }}>
          <Routes>
            <Route path="/"             element={<Dashboard />} />
            <Route path="/transactions" element={<Transactions />} />
            <Route path="/categories"   element={<Categories />} />
          </Routes>
        </main>
      </div>
    </BrowserRouter>
  );
}
