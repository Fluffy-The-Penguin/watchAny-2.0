# WatchAny Watch Together Relay Server

A simple, reliable WebSocket relay for the WatchAny Watch Together feature.

## Deploy to Railway (Free, Recommended)

1. Install Railway CLI: `npm install -g @railway/cli`
2. Login: `railway login`
3. From the `relay_server/` folder:
   ```
   railway init
   railway up
   ```
4. Copy the deployment URL (e.g. `watchany-relay.up.railway.app`)
5. In `lib/services/watch_together_service.dart`, update:
   ```dart
   static const String _kRelayUrl = 'wss://YOUR_URL_HERE';
   ```

## Deploy to Render (Free)

1. Create account at render.com
2. New → Web Service → connect repo
3. Root Directory: `relay_server`
4. Build Command: `npm install`
5. Start Command: `node server.js`
6. Copy URL and update `_kRelayUrl` in the Dart service file.

## Health Check

`GET /health` returns JSON with uptime, room count, and connection count.

## Local Testing

```bash
cd relay_server
npm install
npm start
```

Then set `_kRelayUrl = 'ws://localhost:8080'` in the Dart service.
