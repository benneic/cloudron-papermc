const express = require('express');
const session = require('express-session');
const { Issuer, generators } = require('openid-client');
const http = require('http');
const WebSocket = require('ws');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server, path: '/ws' });

const PORT = 3000;
const SERVER_DIR = '/app/data/server';
const LOG_FILE = path.join(SERVER_DIR, 'logs', 'latest.log');

// ============================================================
// Session setup
// ============================================================
const sessionSecret = process.env.SESSION_SECRET || crypto.randomBytes(32).toString('hex');
const sessionMiddleware = session({
    secret: sessionSecret,
    resave: false,
    saveUninitialized: false,
    cookie: { secure: false, httpOnly: true, maxAge: 24 * 60 * 60 * 1000 }
});
app.use(sessionMiddleware);
app.use(express.json());

// ============================================================
// OIDC setup (Cloudron SSO)
// ============================================================
let oidcClient = null;
const OIDC_ISSUER = process.env.CLOUDRON_OIDC_ISSUER;
const OIDC_CLIENT_ID = process.env.CLOUDRON_OIDC_CLIENT_ID;
const OIDC_CLIENT_SECRET = process.env.CLOUDRON_OIDC_CLIENT_SECRET;
const APP_ORIGIN = process.env.CLOUDRON_APP_ORIGIN || `http://localhost:${PORT}`;
const SSO_ENABLED = !!(OIDC_ISSUER && OIDC_CLIENT_ID && OIDC_CLIENT_SECRET);

async function setupOIDC() {
    if (!SSO_ENABLED) {
        console.log('[web] SSO not configured, running without authentication');
        return;
    }
    try {
        const issuer = await Issuer.discover(OIDC_ISSUER);
        oidcClient = new issuer.Client({
            client_id: OIDC_CLIENT_ID,
            client_secret: OIDC_CLIENT_SECRET,
            redirect_uris: [`${APP_ORIGIN}/auth/callback`],
            response_types: ['code'],
            token_endpoint_auth_method: 'client_secret_post'
        });
        console.log('[web] OIDC configured successfully');
    } catch (err) {
        console.error('[web] OIDC setup failed:', err.message);
    }
}

// ============================================================
// Auth middleware
// ============================================================
function requireAuth(req, res, next) {
    if (!SSO_ENABLED) return next();
    if (req.session && req.session.user) return next();
    // Store original URL for post-login redirect
    req.session.returnTo = req.originalUrl;
    res.redirect('/auth/login');
}

// ============================================================
// Auth routes
// ============================================================
app.get('/auth/login', (req, res) => {
    if (!oidcClient) return res.status(503).send('SSO not configured');
    const nonce = generators.nonce();
    const state = generators.state();
    req.session.oidcNonce = nonce;
    req.session.oidcState = state;
    const authUrl = oidcClient.authorizationUrl({
        scope: 'openid profile email',
        nonce,
        state
    });
    res.redirect(authUrl);
});

app.get('/auth/callback', async (req, res) => {
    if (!oidcClient) return res.status(503).send('SSO not configured');
    try {
        const params = oidcClient.callbackParams(req);
        const tokenSet = await oidcClient.callback(
            `${APP_ORIGIN}/auth/callback`,
            params,
            { nonce: req.session.oidcNonce, state: req.session.oidcState }
        );
        const userinfo = await oidcClient.userinfo(tokenSet.access_token);
        req.session.user = {
            id: userinfo.sub,
            username: userinfo.preferred_username || userinfo.sub,
            email: userinfo.email,
            name: userinfo.name || userinfo.preferred_username || userinfo.sub
        };
        delete req.session.oidcNonce;
        delete req.session.oidcState;
        const returnTo = req.session.returnTo || '/';
        delete req.session.returnTo;
        res.redirect(returnTo);
    } catch (err) {
        console.error('[web] OIDC callback error:', err.message);
        res.status(500).send('Authentication failed. <a href="/auth/login">Try again</a>');
    }
});

app.get('/auth/logout', (req, res) => {
    req.session.destroy(() => {
        res.redirect('/');
    });
});

// ============================================================
// Health check (no auth required for Cloudron)
// ============================================================
app.get('/', (req, res, next) => {
    // If this is a Cloudron health check (no session/browser), just return 200
    const ua = req.headers['user-agent'] || '';
    if (ua.includes('Cloudron') || !req.headers.accept || !req.headers.accept.includes('text/html')) {
        return res.status(200).send('OK');
    }
    next();
});

// ============================================================
// Main UI
// ============================================================
app.get('/', requireAuth, (req, res) => {
    const user = req.session?.user;
    const userName = user ? user.name : 'Admin';
    res.send(getHTML(userName));
});

// ============================================================
// API routes
// ============================================================
app.get('/api/status', requireAuth, (req, res) => {
    const status = getServerStatus();
    res.json(status);
});

app.get('/api/build', requireAuth, (req, res) => {
    const buildFile = path.join(SERVER_DIR, '.paper-build');
    let build = 'unknown';
    try { build = fs.readFileSync(buildFile, 'utf8').trim(); } catch (e) {}
    res.json({ build });
});

app.post('/api/command', requireAuth, (req, res) => {
    // We don't have direct stdin to the MC process in this architecture,
    // so we use RCON or screen. For simplicity, we'll note this is view-only.
    res.json({ error: 'Console commands not supported in this version. Use in-game /op or edit configs via File Manager.' });
});

// ============================================================
// WebSocket — stream log file
// ============================================================
wss.on('connection', (ws, req) => {
    // Parse session from upgrade request
    // For simplicity, allow WS connections (they're behind Cloudron's auth proxy anyway)
    let tailProc = null;

    try {
        if (fs.existsSync(LOG_FILE)) {
            // Send last 100 lines
            const lines = fs.readFileSync(LOG_FILE, 'utf8').split('\n').slice(-100);
            ws.send(JSON.stringify({ type: 'history', lines }));
        }

        // Tail the log
        tailProc = spawn('tail', ['-n', '0', '-F', LOG_FILE]);
        tailProc.stdout.on('data', (data) => {
            if (ws.readyState === WebSocket.OPEN) {
                const lines = data.toString().split('\n').filter(l => l.trim());
                for (const line of lines) {
                    ws.send(JSON.stringify({ type: 'log', line }));
                }
            }
        });
        tailProc.stderr.on('data', () => {}); // ignore
    } catch (e) {
        ws.send(JSON.stringify({ type: 'error', message: 'Could not read log file' }));
    }

    ws.on('close', () => {
        if (tailProc) tailProc.kill();
    });

    ws.on('error', () => {
        if (tailProc) tailProc.kill();
    });
});

// ============================================================
// Server status helper
// ============================================================
function getServerStatus() {
    const propsFile = path.join(SERVER_DIR, 'server.properties');
    let props = {};
    try {
        const content = fs.readFileSync(propsFile, 'utf8');
        for (const line of content.split('\n')) {
            if (line.startsWith('#') || !line.includes('=')) continue;
            const [key, ...val] = line.split('=');
            props[key.trim()] = val.join('=').trim();
        }
    } catch (e) {}

    // Check if Java MC process is running
    let running = false;
    try {
        const result = require('child_process').execSync('pgrep -f "java.*paper.jar"', { timeout: 3000 });
        running = result.toString().trim().length > 0;
    } catch (e) {}

    const buildFile = path.join(SERVER_DIR, '.paper-build');
    let build = 'unknown';
    try { build = fs.readFileSync(buildFile, 'utf8').trim(); } catch (e) {}

    return {
        running,
        build,
        gamemode: props['gamemode'] || 'unknown',
        difficulty: props['difficulty'] || 'unknown',
        maxPlayers: props['max-players'] || '?',
        motd: props['motd'] || '',
        whitelistEnabled: props['white-list'] === 'true',
        pvp: props['pvp'] === 'true',
        port: process.env.MINECRAFT_PORT || props['server-port'] || '25565'
    };
}

// ============================================================
// HTML template
// ============================================================
function getHTML(userName) {
    const ssoEnabled = SSO_ENABLED;
    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PaperMC — Server Console</title>
<style>
  :root {
    --bg: #1a1b26; --surface: #24283b; --border: #414868;
    --text: #c0caf5; --text-dim: #565f89; --accent: #7aa2f7;
    --green: #9ece6a; --red: #f7768e; --yellow: #e0af68;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: var(--bg); color: var(--text); min-height: 100vh; }
  .header { display: flex; align-items: center; justify-content: space-between; padding: 16px 24px; background: var(--surface); border-bottom: 1px solid var(--border); }
  .header h1 { font-size: 18px; font-weight: 600; display: flex; align-items: center; gap: 8px; }
  .header h1 .icon { font-size: 24px; }
  .header .user { display: flex; align-items: center; gap: 12px; font-size: 13px; color: var(--text-dim); }
  .header .user a { color: var(--accent); text-decoration: none; }
  .status-bar { display: flex; flex-wrap: wrap; gap: 16px; padding: 16px 24px; background: var(--surface); border-bottom: 1px solid var(--border); }
  .status-item { display: flex; align-items: center; gap: 6px; font-size: 13px; }
  .status-item .label { color: var(--text-dim); }
  .status-item .value { font-weight: 500; }
  .status-dot { width: 8px; height: 8px; border-radius: 50%; display: inline-block; }
  .status-dot.online { background: var(--green); box-shadow: 0 0 6px var(--green); }
  .status-dot.offline { background: var(--red); box-shadow: 0 0 6px var(--red); }
  .console-container { padding: 24px; flex: 1; display: flex; flex-direction: column; height: calc(100vh - 130px); }
  .console-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; }
  .console-header h2 { font-size: 14px; font-weight: 600; color: var(--text-dim); text-transform: uppercase; letter-spacing: 0.5px; }
  .console-header .actions { display: flex; gap: 8px; }
  .btn { padding: 6px 12px; border: 1px solid var(--border); background: var(--surface); color: var(--text); border-radius: 6px; cursor: pointer; font-size: 12px; transition: all 0.15s; }
  .btn:hover { border-color: var(--accent); color: var(--accent); }
  #console { flex: 1; background: #0f0f14; border: 1px solid var(--border); border-radius: 8px; padding: 12px; overflow-y: auto; font-family: 'JetBrains Mono', 'Fira Code', 'Cascadia Code', monospace; font-size: 12px; line-height: 1.6; color: #a9b1d6; }
  #console .line { white-space: pre-wrap; word-break: break-all; }
  #console .line.info { color: var(--green); }
  #console .line.warn { color: var(--yellow); }
  #console .line.error { color: var(--red); }
  .note { padding: 12px 24px; font-size: 12px; color: var(--text-dim); border-top: 1px solid var(--border); background: var(--surface); }
  .note a { color: var(--accent); text-decoration: none; }
  @media (max-width: 600px) {
    .status-bar { flex-direction: column; gap: 8px; }
    .header { flex-direction: column; gap: 8px; align-items: flex-start; }
  }
</style>
</head>
<body>
<div class="header">
  <h1><span class="icon">⛏️</span> PaperMC Server</h1>
  <div class="user">
    ${ssoEnabled ? `Signed in as <strong>${userName}</strong> &middot; <a href="/auth/logout">Sign out</a>` : ''}
  </div>
</div>
<div class="status-bar" id="status-bar">
  <div class="status-item"><span class="label">Status:</span> <span class="status-dot offline" id="status-dot"></span> <span class="value" id="status-text">Loading...</span></div>
  <div class="status-item"><span class="label">Build:</span> <span class="value" id="build-text">—</span></div>
  <div class="status-item"><span class="label">Mode:</span> <span class="value" id="mode-text">—</span></div>
  <div class="status-item"><span class="label">Players:</span> <span class="value" id="players-text">—</span></div>
  <div class="status-item"><span class="label">Port:</span> <span class="value" id="port-text">—</span></div>
  <div class="status-item"><span class="label">PvP:</span> <span class="value" id="pvp-text">—</span></div>
  <div class="status-item"><span class="label">Whitelist:</span> <span class="value" id="whitelist-text">—</span></div>
</div>
<div class="console-container">
  <div class="console-header">
    <h2>Server Console</h2>
    <div class="actions">
      <button class="btn" onclick="clearConsole()">Clear</button>
      <button class="btn" id="scroll-btn" onclick="toggleAutoScroll()">Auto-scroll: ON</button>
    </div>
  </div>
  <div id="console"></div>
</div>
<div class="note">
  Server configs can be edited via the Cloudron <a href="#">File Manager</a> in <code>/app/data/server/</code>.
  The server auto-checks for PaperMC updates every 6 hours.
</div>
<script>
let autoScroll = true;
const consoleEl = document.getElementById('console');
const MAX_LINES = 1000;

function addLine(text) {
  const div = document.createElement('div');
  div.className = 'line';
  if (/\\bWARN\\b/i.test(text)) div.classList.add('warn');
  else if (/\\bERROR\\b|\\bFATAL\\b/i.test(text)) div.classList.add('error');
  else if (/\\bINFO\\b/i.test(text)) div.classList.add('info');
  div.textContent = text;
  consoleEl.appendChild(div);
  // Trim old lines
  while (consoleEl.children.length > MAX_LINES) consoleEl.removeChild(consoleEl.firstChild);
  if (autoScroll) consoleEl.scrollTop = consoleEl.scrollHeight;
}

function clearConsole() { consoleEl.innerHTML = ''; }

function toggleAutoScroll() {
  autoScroll = !autoScroll;
  document.getElementById('scroll-btn').textContent = 'Auto-scroll: ' + (autoScroll ? 'ON' : 'OFF');
  if (autoScroll) consoleEl.scrollTop = consoleEl.scrollHeight;
}

// WebSocket connection
function connectWS() {
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  const ws = new WebSocket(proto + '://' + location.host + '/ws');
  ws.onmessage = (evt) => {
    try {
      const msg = JSON.parse(evt.data);
      if (msg.type === 'history' && msg.lines) {
        msg.lines.forEach(l => { if (l.trim()) addLine(l); });
      } else if (msg.type === 'log' && msg.line) {
        addLine(msg.line);
      }
    } catch (e) {}
  };
  ws.onclose = () => { setTimeout(connectWS, 3000); };
  ws.onerror = () => { ws.close(); };
}
connectWS();

// Status polling
async function fetchStatus() {
  try {
    const res = await fetch('/api/status');
    const s = await res.json();
    document.getElementById('status-dot').className = 'status-dot ' + (s.running ? 'online' : 'offline');
    document.getElementById('status-text').textContent = s.running ? 'Online' : 'Offline';
    document.getElementById('build-text').textContent = s.build || '—';
    document.getElementById('mode-text').textContent = s.gamemode || '—';
    document.getElementById('players-text').textContent = '0 / ' + (s.maxPlayers || '?');
    document.getElementById('port-text').textContent = s.port || '—';
    document.getElementById('pvp-text').textContent = s.pvp ? 'On' : 'Off';
    document.getElementById('whitelist-text').textContent = s.whitelistEnabled ? 'On' : 'Off';
  } catch (e) {}
}
fetchStatus();
setInterval(fetchStatus, 10000);
</script>
</body>
</html>`;
}

// ============================================================
// Boot
// ============================================================
(async () => {
    await setupOIDC();
    server.listen(PORT, '0.0.0.0', () => {
        console.log(`[web] Panel listening on port ${PORT}`);
    });
})();
