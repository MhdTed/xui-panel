#!/usr/bin/env bash
# =============================================================
#  Full Automatic Installer for a Lightweight x-ui‑like Panel
#  Backend: Express + SQLite
#  Frontend: React (built & served statically by Express)
#  Service: systemd – starts at boot, restarts on failure
# -------------------------------------------------------------
#  How to use (on any Debian/Ubuntu‑based distro):
#     1)  curl -fsSL https://raw.githubusercontent.com/yourrepo/xui‑panel/main/install.sh -o install.sh
#     2)  sudo bash install.sh
#  The script installs all dependencies, builds the frontend,
#  writes service files, and enables+starts the panel on port 80.
# =============================================================

# ----- early exit on error -----
set -euo pipefail
IFS=$'\n\t'

# GLOBALS ------------------------------------------------------
PANEL_DIR="/opt/xui-panel"
NODE_VERSION="18"                # LTS suitable for 2025
PANEL_PORT=80                     # change if port 80 is occupied

# 1) Ensure Node.js ------------------------------------------------
if ! command -v node >/dev/null 2>&1; then
  echo "📦 Installing Node.js ${NODE_VERSION}.x ..."
  curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -
  apt-get install -y nodejs build-essential
else
  echo "✅ Node.js already present: $(node -v)"
fi

# 2) Create application skeleton ----------------------------------
if [[ -d "${PANEL_DIR}" ]]; then
  echo "🗑 Removing previous installation (backup at /opt/xui-panel.bak)"
  rm -rf /opt/xui-panel.bak || true
  mv "${PANEL_DIR}" /opt/xui-panel.bak
fi

mkdir -p "${PANEL_DIR}/server" "${PANEL_DIR}/client/src"
cd "${PANEL_DIR}"

# 3) ---------- Backend -------------------------------------------
cat > server/package.json <<'PKG'
{
  "name": "xui-panel-server",
  "version": "1.0.0",
  "type": "module",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "cors": "^2.8.5",
    "express": "^4.19.2",
    "sqlite3": "^5.1.6"
  }
}
PKG

cat > server/server.js <<'NODE'
import express from 'express';
import cors from 'cors';
import sqlite3 from 'sqlite3';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname  = path.dirname(__filename);

const app  = express();
const db   = new sqlite3.Database(path.join(__dirname, 'db.sqlite'));
const PORT = process.env.PORT || ${PANEL_PORT};

app.use(cors());
app.use(express.json());

// ---------- DB initialisation ----------
db.serialize(() => {
  db.run(`CREATE TABLE IF NOT EXISTS configs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    protocol TEXT NOT NULL,
    address TEXT NOT NULL,
    port INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  )`);
});

// ---------- REST API ----------
app.get('/api/configs', (req, res) => {
  db.all('SELECT * FROM configs', [], (err, rows) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json(rows);
  });
});

app.post('/api/configs', (req, res) => {
  const { name, protocol, address, port } = req.body;
  if (!name || !protocol || !address || !port)
    return res.status(400).json({ error: 'Missing fields' });
  db.run(`INSERT INTO configs (name, protocol, address, port) VALUES (?, ?, ?, ?)`,
    [name, protocol, address, port], function (err) {
      if (err) return res.status(500).json({ error: err.message });
      res.json({ id: this.lastID });
    });
});

app.delete('/api/configs/:id', (req, res) => {
  db.run('DELETE FROM configs WHERE id = ?', req.params.id, function (err) {
    if (err) return res.status(500).json({ error: err.message });
    res.json({ success: this.changes > 0 });
  });
});

// ---------- Serve React build ----------
const reactBuild = path.join(__dirname, 'public');
app.use(express.static(reactBuild));

app.get('*', (_, res) => {
  res.sendFile(path.join(reactBuild, 'index.html'));
});

app.listen(PORT, () => console.log(`🚀 xui‑panel running on port ${PORT}`));
NODE

# 4) ---------- Frontend (React) ----------------------------------
cat > client/package.json <<'PKG2'
{
  "name": "xui-panel-client",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "axios": "^1.8.0",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-scripts": "5.0.1"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build",
    "test": "react-scripts test --env=jsdom",
    "eject": "react-scripts eject"
  }
}
PKG2

# entrypoint index.html
mkdir -p client/public
cat > client/public/index.html <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <link rel="icon" href="favicon.ico" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>xui‑Panel</title>
  <script defer="defer" src="/static/js/bundle.js"></script>
  <link href="https://cdn.jsdelivr.net/npm/tailwindcss@3.4.1/dist/tailwind.min.css" rel="stylesheet">
</head>
<body class="bg-gray-100">
  <div id="root"></div>
</body>
</html>
HTML

# React App.jsx
cat > client/src/App.jsx <<'REACT'
import React, { useState, useEffect } from 'react';
import axios from 'axios';

export default function App() {
  const [configs, setConfigs] = useState([]);
  const [form, setForm]   = useState({ name:'', protocol:'VLESS', address:'', port:'' });

  const load = async () => {
    const { data } = await axios.get('/api/configs');
    setConfigs(data);
  };
  useEffect(() => { load(); }, []);

  const submit = async (e) => {
    e.preventDefault();
    await axios.post('/api/configs', form);
    setForm({ name:'', protocol:'VLESS', address:'', port:'' });
    load();
  };

  const del = async (id) => {
    await axios.delete(`/api/configs/${id}`);
    load();
  };

  return (
    <div className="container mx-auto p-6 max-w-xl">
      <h1 className="text-2xl font-bold mb-6">xui‑Panel</h1>
      <form onSubmit={submit} className="grid gap-3 mb-8">
        <input className="border p-2 rounded" placeholder="Name" value={form.name} onChange={e=>setForm({...form,name:e.target.value})} required />
        <select className="border p-2 rounded" value={form.protocol} onChange={e=>setForm({...form,protocol:e.target.value})}>
          {['VLESS','VMess','Trojan'].map(p=>(<option key={p}>{p}</option>))}
        </select>
        <input className="border p-2 rounded" placeholder="Address" value={form.address} onChange={e=>setForm({...form,address:e.target.value})} required />
        <input className="border p-2 rounded" placeholder="Port" type="number" value={form.port} onChange={e=>setForm({...form,port:e.target.value})} required />
        <button className="bg-blue-600 text-white py-2 rounded" type="submit">Add</button>
      </form>

      <ul className="space-y-2">
        {configs.map(cfg => (
          <li key={cfg.id} className="flex justify-between items-center bg-white shadow p-3 rounded">
            <span className="font-mono text-sm">{cfg.name}@{cfg.address}:{cfg.port} ({cfg.protocol})</span>
            <button onClick={()=>del(cfg.id)} className="text-red-600">Delete</button>
          </li>
        ))}
        {configs.length===0 && <p className="text-gray-500">No configs yet.</p>}
      </ul>
    </div>
  );
}
REACT

# React index.js
cat > client/src/index.js <<'IDX'
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<App />);
IDX

# 5) ---------- Install dependencies & build ----------------------
cd "${PANEL_DIR}/server"
npm install --omit=dev
cd "${PANEL_DIR}/client"
npm install --omit=dev
npm run build
# move build to server/public
rm -rf "${PANEL_DIR}/server/public"
cp -r build "${PANEL_DIR}/server/public"

# 6) ---------- systemd service ----------------------------------
cat > /etc/systemd/system/xui-panel.service <<SERVICE
[Unit]
Description=Lightweight xui‑like Panel (Express + React)
After=network.target

[Service]
ExecStart=/usr/bin/node ${PANEL_DIR}/server/server.js
Restart=on-failure
Environment=NODE_ENV=production
WorkingDirectory=${PANEL_DIR}/server
User=root
Group=root

[Install]
WantedBy=multi-user.target
SERVICE

# 7) ---------- Enable & start service ----------------------------
systemctl daemon-reload
systemctl enable --now xui-panel.service

# 8) ---------- Finish --------------------------------------------
echo "✅ Installation complete!"
echo "🔗 Open http://<SERVER-IP> (port ${PANEL_PORT}) in your browser."
echo "📂 Source located at ${PANEL_DIR} (remove /opt/xui-panel.bak if old data is no longer needed)."
