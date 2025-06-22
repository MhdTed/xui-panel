ممنون که روشن کردی!
پس می‌خوای فایل `install.sh` که اول فرستادی رو با این پنل کامل ادغام کنم طوری که:

* همچنان نصب x-ui-panel رو انجام بده
* بعدش این پنل جدید (React+Node API) رو بسازه، نصب کنه و اجرا کنه
* و یک سرویس systemd برای پنل جدید بسازه

درسته؟

اگر اینطوره، من کل اسکریپت رو آماده می‌کنم و می‌فرستم که بتونی مستقیم جایگزین فایل `install.sh` خودت کنی.
همه کارها رو انجام میده: نصب وابستگی‌ها، دانلود x-ui-panel اصلی، نصب، و سپس ساخت و راه‌اندازی پنل جدید برای مدیریت اکانت‌ها.

---

### نسخه ادغام شده `install.sh` با پنل خودکار:

```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# تنظیم متغیرها
XUI_DIR="/etc/x-ui"
PANEL_DIR="/opt/xui-auto-panel"
NODE_VERSION="18"
PANEL_PORT=8080

echo "Installing dependencies..."
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -
  apt-get install -y nodejs build-essential
else
  echo "Node.js already installed: $(node -v)"
fi

echo "Installing x-ui-panel..."

# دانلود و نصب x-ui اصلی (همونی که فرستادی اول)
if [[ ! -d "${XUI_DIR}" ]]; then
  mkdir -p "${XUI_DIR}"
fi
cd "${XUI_DIR}"

# دانلود آخرین نسخه x-ui-panel از گیت‌هاب
curl -L -o x-ui-linux.zip https://github.com/MhdTed/xui-panel/releases/latest/download/x-ui-linux.zip
unzip -o x-ui-linux.zip
chmod +x x-ui
./x-ui install

systemctl enable x-ui
systemctl restart x-ui

echo "x-ui-panel installed and service started."

echo "Setting up custom auto account panel at ${PANEL_DIR}..."

# بکاپ در صورت وجود
if [[ -d "${PANEL_DIR}" ]]; then
  mv "${PANEL_DIR}" "${PANEL_DIR}.bak-$(date +%s)"
fi

mkdir -p "${PANEL_DIR}/server" "${PANEL_DIR}/client/src"
cd "${PANEL_DIR}"

# Backend package.json
cat > server/package.json <<'EOF'
{
  "name": "xui-auto-panel-server",
  "version": "1.0.0",
  "type": "module",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "cors": "^2.8.5",
    "express": "^4.19.2",
    "sqlite3": "^5.1.6",
    "uuid": "^9.0.0"
  }
}
EOF

# Backend server.js
cat > server/server.js <<EOF
import express from 'express';
import cors from 'cors';
import sqlite3 from 'sqlite3';
import { open } from 'sqlite';
import { v4 as uuidv4 } from 'uuid';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname  = path.dirname(__filename);
const app = express();
const PORT = process.env.PORT || ${PANEL_PORT};

app.use(cors());
app.use(express.json());

let db;
(async () => {
  db = await open({
    filename: path.join(__dirname, 'db.sqlite'),
    driver: sqlite3.Database
  });

  await db.run(\`CREATE TABLE IF NOT EXISTS accounts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    uuid TEXT NOT NULL,
    protocol TEXT NOT NULL,
    address TEXT NOT NULL,
    port INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  )\`);
})();

app.get('/api/accounts', async (req, res) => {
  const accounts = await db.all('SELECT * FROM accounts');
  res.json(accounts);
});

app.post('/api/accounts', async (req, res) => {
  const { name, protocol, address, port } = req.body;
  if (!name || !protocol || !address || !port) {
    return res.status(400).json({ error: 'Missing fields' });
  }

  const newUUID = uuidv4();

  await db.run(
    'INSERT INTO accounts (name, uuid, protocol, address, port) VALUES (?, ?, ?, ?, ?)',
    [name, newUUID, protocol, address, port]
  );

  const link = \`\${protocol.toLowerCase()}://\${newUUID}@\${address}:\${port}?security=tls&type=tcp#\${encodeURIComponent(name)}\`;

  res.json({ uuid: newUUID, link });
});

app.delete('/api/accounts/:id', async (req, res) => {
  const { id } = req.params;
  const result = await db.run('DELETE FROM accounts WHERE id = ?', id);
  res.json({ success: result.changes > 0 });
});

const reactBuild = path.join(__dirname, 'public');
app.use(express.static(reactBuild));
app.get('*', (_, res) => {
  res.sendFile(path.join(reactBuild, 'index.html'));
});

app.listen(PORT, () => {
  console.log(\`🚀 xui-auto-panel running on port \${PORT}\`);
});
EOF

# Frontend package.json
cat > client/package.json <<'EOF'
{
  "name": "xui-auto-panel-client",
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
EOF

mkdir -p client/public
cat > client/public/index.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <link rel="icon" href="favicon.ico" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>xui-auto-panel</title>
  <link href="https://cdn.jsdelivr.net/npm/tailwindcss@3.4.1/dist/tailwind.min.css" rel="stylesheet" />
</head>
<body class="bg-gray-100">
  <div id="root"></div>
</body>
</html>
EOF

cat > client/src/App.jsx <<'EOF'
import React, { useState, useEffect } from "react";
import axios from "axios";

export default function App() {
  const [accounts, setAccounts] = useState([]);
  const [form, setForm] = useState({
    name: "",
    protocol: "vless",
    address: "",
    port: "",
  });
  const [lastLink, setLastLink] = useState("");

  const load = async () => {
    const { data } = await axios.get("/api/accounts");
    setAccounts(data);
  };

  useEffect(() => {
    load();
  }, []);

  const submit = async (e) => {
    e.preventDefault();
    const { data } = await axios.post("/api/accounts", form);
    setLastLink(data.link);
    setForm({ name: "", protocol: "vless", address: "", port: "" });
    load();
  };

  const del = async (id) => {
    await axios.delete(\`/api/accounts/\${id}\`);
    load();
  };

  return (
    <div className="container mx-auto max-w-xl p-6">
      <h1 className="text-2xl font-bold mb-6">xui-auto-panel</h1>
      <form onSubmit={submit} className="grid gap-3 mb-4">
        <input
          className="border p-2 rounded"
          placeholder="Name"
          value={form.name}
          onChange={(e) => setForm({ ...form, name: e.target.value })}
          required
        />
        <select
          className="border p-2 rounded"
          value={form.protocol}
          onChange={(e) =>
            setForm({ ...form, protocol: e.target.value.toLowerCase() })
          }
        >
          <option value="vless">VLESS</option>
          <option value="vmess">VMess</option>
          <option value="trojan">Trojan</option>
        </select>
        <input
          className="border p-2 rounded"
          placeholder="Address"
          value={form.address}
          onChange={(e) => setForm({ ...form, address: e.target.value })}
          required
        />
        <input
          className="border p-2 rounded"
          placeholder="Port"
          type="number"
          value={form.port}
          onChange={(e) => setForm({ ...form, port: e.target.value })}
          required
        />
        <button
          className="bg-blue-600 text-white py-2 rounded"
          type="submit"
        >
          Add Account
        </button>
      </form>

      {lastLink && (
        <div className="mb-4 p-3 bg-green-100 text-green-900 rounded break-words">
          <strong>Last generated link:</strong>
          <br />
          <code>{lastLink}</code>
        </div>
      )}

      <ul className="space-y-2">
        {accounts.map((acc) => (
          <li
            key={acc.id}
            className="flex justify-between items-center bg-white shadow p-3 rounded"
          >
            <span className="font-mono text-sm">
              {acc.name} - {acc.protocol.toUpperCase()} - {acc.address}:
              {acc.port}
            </span>
            <button
              onClick={() => del(acc.id)}
              className="text-red-600 hover:underline"
            >
              Delete
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}
EOF

cat > client/src/index.js <<'EOF'
import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";

const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(<App />);
EOF

echo "Installing Node.js dependencies for backend and frontend..."
cd server && npm install --production
cd ../client && npm install
npm run build --prefix client

echo "Moving frontend build to backend public folder..."
rm -rf server/public
mv client/build server/public

echo "Creating systemd service for xui-auto-panel server..."

cat > /etc/systemd/system/xui-auto-panel.service <<EOF
[Unit]
Description=xui-auto-panel backend server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${PANEL_DIR}/server
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "Reloading systemd and starting service..."
systemctl daemon-reload
systemctl enable xui-auto-panel
systemctl start xui-auto-panel

echo "Installation complete!"
echo "x-ui-panel main panel is running."
echo "Your custom account panel is running on port ${PANEL_PORT}."
echo "Visit
```
