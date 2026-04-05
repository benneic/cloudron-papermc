# cloudron-papermc

Cloudron app package for [PaperMC](https://papermc.io/) — a high-performance Minecraft server.

## Features

- **PaperMC Server** with automatic updates via the [Fill v3 API](https://docs.papermc.io/misc/downloads-service/)
- **Lightweight Web Console** — live log streaming, server status, and build info
- **Cloudron SSO** — OIDC-based authentication for the web panel
- **Kid-Friendly Defaults** — creative mode, peaceful difficulty, PvP off, whitelist enabled
- **Minecraft TCP Port** — exposed via Cloudron's `tcpPorts` manifest (configurable in the UI)
- **Persistent Data** — worlds, configs, and plugins stored in `/app/data/server/` (backed up by Cloudron)

## Installation

### From source (development)

```bash
cd cloudron-papermc
cloudron install
```

### From Docker image

```bash
cloudron build
cloudron install --image <your-registry>/cloudron-papermc:latest
```

## Configuration

After installation, server files can be edited via the **Cloudron File Manager** at `/app/data/server/`:

| File | Purpose |
|------|---------|
| `server.properties` | Main server configuration |
| `whitelist.json` | Allowed players |
| `ops.json` | Server operators |
| `spigot.yml` | Spigot-layer settings |
| `bukkit.yml` | Bukkit-layer settings |

## Default Settings (Kid-Friendly)

| Setting | Value |
|---------|-------|
| Game Mode | Creative |
| Difficulty | Peaceful |
| PvP | Disabled |
| Whitelist | Enabled |
| Max Players | 10 |
| Spawn Protection | 16 blocks |
| Online Mode | Enabled |
| Max World Size | 10,000 blocks |
| Player Idle Timeout | 30 minutes |

## Auto-Updates

A cron job runs every 6 hours to check for new PaperMC builds via the Fill v3 API. When a new stable build is found:

1. The new jar is downloaded
2. The Minecraft server is gracefully stopped
3. The jar is swapped
4. The server restarts automatically

Update logs are available at `/tmp/papermc-update.log`.

## Architecture

```
┌─────────────────────────────────────────┐
│  Cloudron Container                     │
│                                         │
│  ┌──────────────┐  ┌────────────────┐  │
│  │ Web Panel     │  │ PaperMC Server │  │
│  │ (Node.js)     │  │ (Java 21)      │  │
│  │ Port 3000     │  │ Port 25565     │  │
│  │ ─ SSO/OIDC    │  │ ─ Minecraft    │  │
│  │ ─ Log viewer  │  │   protocol     │  │
│  │ ─ Status API  │  │                │  │
│  └──────┬───────┘  └───────┬────────┘  │
│         │  WebSocket        │           │
│         │  (tail logs)      │           │
│         └──────────┬────────┘           │
│                    │                    │
│         ┌──────────┴────────┐           │
│         │  /app/data/server │           │
│         │  (localstorage)   │           │
│         └───────────────────┘           │
└─────────────────────────────────────────┘
```

## License

MIT
