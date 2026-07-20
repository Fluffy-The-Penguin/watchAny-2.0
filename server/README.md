# watchAny Cloud Sync Server

Self-hosted Node.js + SQLite backend server for `watchAny 2.0` cloud accounts and multi-device sync.

---

## 🚀 Easy Deployment on Bot-Hosting.net

1. **Upload Files**:
   - Upload `package.json`, `server.js` into your container root directory on **Bot-Hosting.net**.

2. **Startup Command**:
   - Set Startup Command in Bot-Hosting panel to:
     ```bash
     npm install && node server.js
     ```

3. **Port & Address**:
   - The server listens on `process.env.PORT` or `21204`.
   - Your endpoint address will be:
     `http://fi10.bot-hosting.net:21204`

---

## 🛠️ API Endpoints Summary

- `GET /api/health` - Health check.
- `POST /api/auth/register` - Create account (`{ username, email, password }`).
- `POST /api/auth/login` - Authenticate (`{ emailOrUsername, password }`).
- `POST /api/sync/push` - Push full client sync payload (`Authorization: Bearer <token>`).
- `GET /api/sync/pull` - Pull cloud sync payload (`Authorization: Bearer <token>`).
