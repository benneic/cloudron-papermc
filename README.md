# cloudron-papermc

Cloudron app package for [PaperMC](https://papermc.io/) — a high-performance Minecraft server.

## Features

- **PaperMC** — pinned by default to a stable Minecraft line compatible with bundled Bedrock plugins (see [Paper version](#paper-version) below); updates use the [Fill v3 API](https://docs.papermc.io/misc/downloads-service/)
- **Geyser + Floodgate** — [Geyser](https://geysermc.org/) lets **Bedrock** clients join the same world as **Java** players; [Floodgate](https://wiki.geysermc.org/floodgate/) allows Bedrock logins without a separate Java/Microsoft account (see [Bedrock (Geyser)](#bedrock-geyser))
- **Lightweight web console** — live log streaming, server status, and build info
- **Cloudron SSO** — OIDC-based authentication for the web panel (`optionalSso`)
- **Kid-friendly defaults** — creative mode, peaceful difficulty, PvP off, whitelist enabled
- **Ports** — Java Edition **TCP** (`MINECRAFT_PORT` → container `25565`) and Bedrock **UDP** (`GEYSER_PORT` → container `19132`) via the Cloudron manifest
- **Persistent data** — worlds, configs, and plugins under `/app/data/server/` (Cloudron `localstorage` backups)

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

### Files (File Manager: `/app/data/server/`)

| Path | Purpose |
|------|---------|
| `server.properties` | Main server configuration |
| `whitelist.json` | Allowed players |
| `ops.json` | Server operators |
| `spigot.yml` | Spigot-layer settings |
| `bukkit.yml` | Bukkit-layer settings |
| `plugins/Geyser-Spigot/config.yml` | Geyser (Bedrock) — port, MOTD, `auth-type`, etc. |

Additional plugins and jars can be added under `plugins/` like any Paper server.

### Environment variables (Cloudron app settings)

| Variable | Purpose |
|----------|---------|
| `PAPER_MC_VERSION` | Minecraft version string for Paper (default **`1.21.11`**, set in the Dockerfile). The updater and six-hour scheduler only fetch builds for this line. Override if you intentionally want another Paper branch (for example when Bedrock plugins support a newer line). |

Cloudron also injects `MINECRAFT_PORT`, `GEYSER_PORT`, and OIDC-related variables as defined in `CloudronManifest.json`.

### Paper version

Paper’s API lists multiple major lines (for example **26.x** and **1.21.x**). This package **does not** follow “whatever is first in the API”, because **Geyser/Floodgate** often lag the newest Paper builds. The default pin matches `upstreamVersion` in the manifest. To move to a newer Minecraft line later, set `PAPER_MC_VERSION` to that version and confirm [Geyser](https://geysermc.org/download) supports it.

### Bedrock (Geyser)

On first start, the app installs **Geyser-Spigot** and **floodgate-spigot** from the official download API (see [`scripts/install-plugins.sh`](scripts/install-plugins.sh)). Those jars are **refreshed** when the Paper build id in `/app/data/server/.paper-build` changes (for example after an update), so they stay aligned with the server.

Default Geyser config uses **`auth-type: floodgate`** so Bedrock players can join via Floodgate; Java players still use normal online-mode authentication as in `server.properties`. Expose **UDP** for Bedrock in the Cloudron app (manifest `GEYSER_PORT`); the container listens on **19132** inside the network namespace.

## Default settings (kid-friendly)

| Setting | Value |
|---------|-------|
| Game mode | Creative |
| Difficulty | Peaceful |
| PvP | Disabled |
| Whitelist | Enabled |
| Max players | 10 |
| Spawn protection | 16 blocks |
| Online mode | Enabled (Java) |
| Max world size | 10,000 blocks |
| Player idle timeout | 30 minutes |

## Auto-updates

The Cloudron **scheduler** addon runs [`scripts/auto-update.sh`](scripts/auto-update.sh) every six hours. It checks Fill for a **new stable build of `PAPER_MC_VERSION`**, then:

1. Downloads the new jar  
2. Stops the Minecraft process gracefully  
3. Swaps the jar and updates `.paper-build`  
4. Re-runs plugin install logic so Geyser/Floodgate stay in sync  
5. Restarts the Minecraft process  

Logs: `/app/data/papermc-update.log` and the app’s Cloudron logs.

## Runtime stack

- **Java:** Eclipse Temurin **25** JRE (Paper and recent builds may require a current class file version).  
- **Web panel:** Node.js (see `Dockerfile`).  
- **Processes:** `start.sh` brings up the web panel first (for Cloudron health checks), then ensures plugins, then starts Paper.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Cloudron container                                          │
│                                                              │
│  ┌────────────────┐  ┌─────────────────────────────────┐  │
│  │ Web panel       │  │ PaperMC + plugins               │  │
│  │ Node.js :3000   │  │ Java 25 — Geyser + Floodgate    │  │
│  │ SSO / logs /    │  │ TCP :25565 — Minecraft Java     │  │
│  │ status API      │  │ UDP :19132 — Minecraft Bedrock  │  │
│  └────────┬───────┘  └──────────────────┬──────────────┘  │
│           │                             │                  │
│           └──────────────┬──────────────┘                  │
│                          │                                 │
│                ┌─────────▼─────────┐                       │
│                │ /app/data/server  │                       │
│                │ (localstorage)    │                       │
│                └───────────────────┘                       │
└──────────────────────────────────────────────────────────────┘
```

## License

MIT
