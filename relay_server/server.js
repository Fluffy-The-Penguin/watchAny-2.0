'use strict';

const WebSocket = require('ws');
const http = require('http');

// HTTP Server
const httpServer = http.createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', uptime: Math.round(process.uptime()), rooms: rooms.size, connections: wss.clients.size }));
    return;
  }
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('WatchAny Watch Together Relay');
});

const wss = new WebSocket.Server({ server: httpServer });

// State
const rooms = new Map();    // roomCode -> Set<WebSocket>
const clientMeta = new Map(); // WebSocket -> { roomCode, senderId, senderName, isHost }

function broadcastToRoom(roomCode, payload, excludeWs) {
  const roomSet = rooms.get(roomCode);
  if (!roomSet) return;
  const json = JSON.stringify(payload);
  for (const ws of roomSet) {
    if (ws !== excludeWs && ws.readyState === WebSocket.OPEN) {
      try { ws.send(json); } catch (_) {}
    }
  }
}

function sendToClient(ws, payload) {
  if (ws.readyState === WebSocket.OPEN) {
    try { ws.send(JSON.stringify(payload)); } catch (_) {}
  }
}

function removeClient(ws) {
  const info = clientMeta.get(ws);
  if (!info) return;
  clientMeta.delete(ws);
  const roomSet = rooms.get(info.roomCode);
  if (!roomSet) return;
  roomSet.delete(ws);
  if (roomSet.size === 0) {
    rooms.delete(info.roomCode);
    console.log('[Relay] Room ' + info.roomCode + ' closed (empty).');
  } else {
    broadcastToRoom(info.roomCode, { type: 'PEER_LEFT', roomCode: info.roomCode, senderId: info.senderId, senderName: info.senderName, timestamp: Date.now() });
    console.log('[Relay] ' + info.senderName + ' left room ' + info.roomCode + '. (' + roomSet.size + ' remaining)');
  }
}

wss.on('connection', (ws, req) => {
  const ip = (req.headers['x-forwarded-for'] || req.socket.remoteAddress || 'unknown').toString();
  console.log('[Relay] New connection from ' + ip);
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });

  ws.on('message', (rawData) => {
    let msg;
    try { msg = JSON.parse(rawData.toString()); } catch { return; }
    const { type, roomCode, senderId, senderName } = msg;
    if (!type || !roomCode || !senderId) return;

    if (type === 'JOIN_ROOM') {
      removeClient(ws);
      if (!rooms.has(roomCode)) rooms.set(roomCode, new Set());
      const roomSet = rooms.get(roomCode);
      roomSet.add(ws);
      clientMeta.set(ws, { roomCode, senderId, senderName: senderName || 'Guest', isHost: msg.isHost === true });
      broadcastToRoom(roomCode, msg, ws);
      sendToClient(ws, { type: 'ROOM_ACK', roomCode, participantCount: roomSet.size, timestamp: Date.now() });
      console.log('[Relay] ' + senderName + ' joined room ' + roomCode + '. (' + roomSet.size + ' total)');
      return;
    }

    const info = clientMeta.get(ws);
    if (info && info.roomCode === roomCode) {
      broadcastToRoom(roomCode, msg, ws);
    }
  });

  ws.on('close', () => removeClient(ws));
  ws.on('error', (err) => { console.error('[Relay] Error: ' + err.message); try { ws.terminate(); } catch (_) {} });
});

// Heartbeat: kill dead connections every 25s
const pingInterval = setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) { removeClient(ws); ws.terminate(); continue; }
    ws.isAlive = false;
    try { ws.ping(); } catch (_) {}
  }
}, 25000);

wss.on('close', () => clearInterval(pingInterval));

const PORT = parseInt(process.env.PORT || '8080', 10);
httpServer.listen(PORT, () => {
  console.log('[Relay] WatchAny Watch Together relay running on port ' + PORT);
});
