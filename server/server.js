const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const path = require('path');
const fs = require('fs');

const PORT = process.env.PORT || 21204;
const JWT_SECRET = process.env.JWT_SECRET || 'watchany_cloud_secret_key_2026_x89a';

const app = express();

// Middleware
app.use(cors());
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ limit: '50mb', extended: true }));

// --- SQLite Database Engine ---
// Uses Node 22.5+ built-in `node:sqlite` (Zero npm native script issues)
let dbMode = 'sqlite_built_in';
let nodeSqliteDb = null;
let sqlite3Db = null;

// JSON fallback state
const jsonDbPath = path.join(__dirname, 'database.json');
let jsonDb = { users: [], userSync: {}, nextUserId: 1 };

const sqlitePath = path.join(__dirname, 'database.sqlite');

try {
  // 1. Try Node.js 22.5+ built-in node:sqlite
  const { DatabaseSync } = require('node:sqlite');
  nodeSqliteDb = new DatabaseSync(sqlitePath);

  nodeSqliteDb.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT UNIQUE NOT NULL,
      email TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS user_sync (
      user_id INTEGER PRIMARY KEY,
      sync_data TEXT NOT NULL,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    );
  `);

  dbMode = 'sqlite_built_in';
  console.log(`[Database] ✅ Using Node.js built-in SQLite engine: ${sqlitePath}`);
} catch (e1) {
  try {
    // 2. Try npm sqlite3 if available
    const sqlite3 = require('sqlite3').verbose();
    sqlite3Db = new sqlite3.Database(sqlitePath);
    sqlite3Db.serialize(() => {
      sqlite3Db.run(`
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          username TEXT UNIQUE NOT NULL,
          email TEXT UNIQUE NOT NULL,
          password_hash TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      `);
      sqlite3Db.run(`
        CREATE TABLE IF NOT EXISTS user_sync (
          user_id INTEGER PRIMARY KEY,
          sync_data TEXT NOT NULL,
          updated_at INTEGER NOT NULL,
          FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        )
      `);
    });
    dbMode = 'sqlite3_npm';
    console.log(`[Database] ✅ Using npm sqlite3 engine: ${sqlitePath}`);
  } catch (e2) {
    // 3. Pure JS fallback
    dbMode = 'json_fallback';
    console.log('[Database] ℹ️ Using fallback JSON database: database.json');
    loadJsonDatabase();
  }
}

function loadJsonDatabase() {
  try {
    if (fs.existsSync(jsonDbPath)) {
      const raw = fs.readFileSync(jsonDbPath, 'utf8');
      const parsed = JSON.parse(raw);
      jsonDb = {
        users: parsed.users || [],
        userSync: parsed.userSync || {},
        nextUserId: parsed.nextUserId || (parsed.users ? parsed.users.length + 1 : 1)
      };
    } else {
      saveJsonDatabase();
    }
  } catch (err) {
    console.error('[Database] Failed to load database.json:', err);
  }
}

function saveJsonDatabase() {
  try {
    const tmpPath = jsonDbPath + '.tmp';
    fs.writeFileSync(tmpPath, JSON.stringify(jsonDb, null, 2), 'utf8');
    fs.renameSync(tmpPath, jsonDbPath);
  } catch (err) {
    console.error('[Database] Failed to save database.json:', err);
  }
}

// --- Unified DB Query Handlers ---

async function findUserByQuery(query) {
  const clean = query.trim().toLowerCase();

  if (dbMode === 'sqlite_built_in') {
    const stmt = nodeSqliteDb.prepare(
      'SELECT * FROM users WHERE LOWER(username) = ? OR LOWER(email) = ?'
    );
    return stmt.get(clean, clean) || null;
  } else if (dbMode === 'sqlite3_npm') {
    return new Promise((resolve, reject) => {
      sqlite3Db.get(
        'SELECT * FROM users WHERE LOWER(username) = ? OR LOWER(email) = ?',
        [clean, clean],
        (err, row) => (err ? reject(err) : resolve(row || null))
      );
    });
  } else {
    return jsonDb.users.find(
      u => u.username.toLowerCase() === clean || u.email.toLowerCase() === clean
    ) || null;
  }
}

async function createUser(username, email, passwordHash) {
  const now = Date.now();

  if (dbMode === 'sqlite_built_in') {
    const stmt = nodeSqliteDb.prepare(
      'INSERT INTO users (username, email, password_hash, created_at, updated_at) VALUES (?, ?, ?, ?, ?)'
    );
    const info = stmt.run(username, email, passwordHash, now, now);
    return { id: Number(info.lastInsertRowid), username, email, password_hash: passwordHash };
  } else if (dbMode === 'sqlite3_npm') {
    return new Promise((resolve, reject) => {
      sqlite3Db.run(
        'INSERT INTO users (username, email, password_hash, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
        [username, email, passwordHash, now, now],
        function (err) {
          if (err) reject(err);
          else resolve({ id: this.lastID, username, email, password_hash: passwordHash });
        }
      );
    });
  } else {
    const newUser = {
      id: jsonDb.nextUserId++,
      username,
      email,
      password_hash: passwordHash,
      created_at: now,
      updated_at: now
    };
    jsonDb.users.push(newUser);
    saveJsonDatabase();
    return newUser;
  }
}

async function setUserSync(userId, payload) {
  const now = Date.now();
  const payloadString = typeof payload === 'string' ? payload : JSON.stringify(payload);

  if (dbMode === 'sqlite_built_in') {
    const stmt = nodeSqliteDb.prepare(
      `INSERT INTO user_sync (user_id, sync_data, updated_at)
       VALUES (?, ?, ?)
       ON CONFLICT(user_id) DO UPDATE SET sync_data = excluded.sync_data, updated_at = excluded.updated_at`
    );
    stmt.run(userId, payloadString, now);
    return now;
  } else if (dbMode === 'sqlite3_npm') {
    return new Promise((resolve, reject) => {
      sqlite3Db.run(
        `INSERT INTO user_sync (user_id, sync_data, updated_at)
         VALUES (?, ?, ?)
         ON CONFLICT(user_id) DO UPDATE SET sync_data = excluded.sync_data, updated_at = excluded.updated_at`,
        [userId, payloadString, now],
        function (err) {
          if (err) reject(err);
          else resolve(now);
        }
      );
    });
  } else {
    jsonDb.userSync[userId] = {
      syncPayload: payload,
      updatedAt: now
    };
    saveJsonDatabase();
    return now;
  }
}

async function getUserSync(userId) {
  if (dbMode === 'sqlite_built_in') {
    const stmt = nodeSqliteDb.prepare('SELECT sync_data, updated_at FROM user_sync WHERE user_id = ?');
    const row = stmt.get(userId);
    if (!row) return null;
    let payload = row.sync_data;
    try { payload = JSON.parse(row.sync_data); } catch (_) {}
    return { syncPayload: payload, updatedAt: Number(row.updated_at) };
  } else if (dbMode === 'sqlite3_npm') {
    return new Promise((resolve, reject) => {
      sqlite3Db.get('SELECT sync_data, updated_at FROM user_sync WHERE user_id = ?', [userId], (err, row) => {
        if (err) reject(err);
        else if (!row) resolve(null);
        else {
          let payload = row.sync_data;
          try { payload = JSON.parse(row.sync_data); } catch (_) {}
          resolve({ syncPayload: payload, updatedAt: row.updated_at });
        }
      });
    });
  } else {
    const record = jsonDb.userSync[userId];
    if (!record) return null;
    return { syncPayload: record.syncPayload, updatedAt: record.updatedAt };
  }
}

// Authentication Middleware
function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ error: 'Authentication token missing' });
  }

  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) {
      return res.status(403).json({ error: 'Invalid or expired token' });
    }
    req.user = user;
    next();
  });
}

// --- Routes ---

// Health Check
app.get('/api/health', (req, res) => {
  res.json({
    status: 'ok',
    server: 'watchAny Cloud Sync Server',
    version: '2.0.0',
    dbMode,
    timestamp: Date.now()
  });
});

// Register
app.post('/api/auth/register', async (req, res) => {
  try {
    const { username, email, password } = req.body;

    if (!username || !email || !password) {
      return res.status(400).json({ error: 'Username, email, and password are required' });
    }

    if (username.trim().length < 3) {
      return res.status(400).json({ error: 'Username must be at least 3 characters long' });
    }

    if (password.length < 6) {
      return res.status(400).json({ error: 'Password must be at least 6 characters long' });
    }

    const cleanUsername = username.trim();
    const cleanEmail = email.trim().toLowerCase();

    const existing = await findUserByQuery(cleanUsername) || await findUserByQuery(cleanEmail);
    if (existing) {
      return res.status(409).json({ error: 'Username or Email already registered' });
    }

    const salt = await bcrypt.genSalt(10);
    const passwordHash = await bcrypt.hash(password, salt);

    const user = await createUser(cleanUsername, cleanEmail, passwordHash);

    const token = jwt.sign(
      { userId: user.id, username: user.username, email: user.email },
      JWT_SECRET,
      { expiresIn: '365d' }
    );

    res.status(201).json({
      message: 'Account created successfully',
      token,
      user: {
        id: user.id,
        username: user.username,
        email: user.email
      }
    });
  } catch (err) {
    console.error('Register error:', err);
    res.status(500).json({ error: 'Server error during registration' });
  }
});

// Login
app.post('/api/auth/login', async (req, res) => {
  try {
    const { emailOrUsername, password } = req.body;

    if (!emailOrUsername || !password) {
      return res.status(400).json({ error: 'Email/Username and password are required' });
    }

    const user = await findUserByQuery(emailOrUsername);
    if (!user) {
      return res.status(401).json({ error: 'Invalid username/email or password' });
    }

    const validPassword = await bcrypt.compare(password, user.password_hash);
    if (!validPassword) {
      return res.status(401).json({ error: 'Invalid username/email or password' });
    }

    const token = jwt.sign(
      { userId: user.id, username: user.username, email: user.email },
      JWT_SECRET,
      { expiresIn: '365d' }
    );

    res.json({
      message: 'Logged in successfully',
      token,
      user: {
        id: user.id,
        username: user.username,
        email: user.email
      }
    });
  } catch (err) {
    console.error('Login error:', err);
    res.status(500).json({ error: 'Server error during authentication' });
  }
});

// Push Sync Data
app.post('/api/sync/push', authenticateToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const { syncPayload } = req.body;

    if (!syncPayload) {
      return res.status(400).json({ error: 'Sync payload is required' });
    }

    const updatedAt = await setUserSync(userId, syncPayload);

    res.json({
      success: true,
      message: 'Sync data pushed to cloud successfully',
      timestamp: updatedAt
    });
  } catch (err) {
    console.error('Push error:', err);
    res.status(500).json({ error: 'Failed to save sync data to cloud' });
  }
});

// Pull Sync Data
app.get('/api/sync/pull', authenticateToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const record = await getUserSync(userId);

    if (!record) {
      return res.json({
        exists: false,
        message: 'No cloud sync data found for this account',
        timestamp: 0
      });
    }

    res.json({
      exists: true,
      syncPayload: record.syncPayload,
      timestamp: record.updatedAt
    });
  } catch (err) {
    console.error('Pull error:', err);
    res.status(500).json({ error: 'Failed to retrieve sync data from cloud' });
  }
});

// Start Server
app.listen(PORT, '0.0.0.0', () => {
  console.log(`====================================================`);
  console.log(`🚀 watchAny Cloud Sync Server running on port ${PORT}`);
  console.log(`🌐 Address: http://0.0.0.0:${PORT}`);
  console.log(`🗄️ Database Engine: ${dbMode}`);
  console.log(`====================================================`);
});
