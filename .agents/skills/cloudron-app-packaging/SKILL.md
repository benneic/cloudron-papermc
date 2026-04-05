---
name: cloudron-app-packaging
description: Package web apps for Cloudron. Covers Dockerfile patterns, CloudronManifest.json, addons, build methods, and debugging. Use when creating, updating, or troubleshooting a Cloudron app package, or when the user mentions Cloudron packaging, Dockerfile.cloudron, CloudronManifest.json, or Cloudron addons.
---

# Cloudron App Packaging

A Cloudron app is a Docker image with a `CloudronManifest.json`. The platform provides a readonly filesystem, addon services, and a managed backup/restore lifecycle.

## Quick start

```bash
npm install -g cloudron
cloudron login my.example.com
cloudron init                    # creates CloudronManifest.json and Dockerfile
cloudron install                 # uploads source, builds on server, installs app
cloudron update                  # re-uploads, rebuilds, updates running app
```

## Key constraints

- Filesystem is **readonly** at runtime. Writable dirs: `/tmp`, `/run`, `/app/data`.
- Databases, caching, email, and auth are **addons** — env vars injected at runtime.
- `CloudronManifest.json` declares metadata, ports, and addon requirements.
- App listens on HTTP (not HTTPS). The platform handles TLS termination.
- Default memory limit is 256 MB (RAM + swap). Set `memoryLimit` in manifest to change.

## Dockerfile patterns

Name the file `Dockerfile`, `Dockerfile.cloudron`, or `cloudron/Dockerfile`.

### Typical structure

```dockerfile
FROM cloudron/base:5.0.0@sha256:04fd70dbd8ad6149c19de39e35718e024417c3e01dc9c6637eaf4a41ec4e596c

RUN mkdir -p /app/code
WORKDIR /app/code

# Install app
COPY . /app/code/

# Create symlinks for runtime config
RUN ln -sf /run/app/config.json /app/code/config.json

# Ensure start script is executable
RUN chmod +x /app/code/start.sh

CMD [ "/app/code/start.sh" ]
```

### Multi-stage builds

Multi-stage builds are acceptable for compilation, asset bundling, or any other build-time work. The only requirement is that the **final stage** must use `cloudron/base:5.0.0@sha256:04fd70dbd8ad6149c19de39e35718e024417c3e01dc9c6637eaf4a41ec4e596c`. Platform tooling such as the file manager, web terminal, and log viewer depends on utilities provided by this base image.

```dockerfile
FROM node:20 AS build
WORKDIR /build
COPY . .
RUN npm ci && npm run build

FROM cloudron/base:5.0.0@sha256:04fd70dbd8ad6149c19de39e35718e024417c3e01dc9c6637eaf4a41ec4e596c

RUN mkdir -p /app/code
WORKDIR /app/code

COPY --from=build /build/dist /app/code/dist
COPY start.sh /app/code/

RUN chmod +x /app/code/start.sh
CMD [ "/app/code/start.sh" ]
```

### start.sh conventions

- Runs as root. Use `gosu cloudron:cloudron <cmd>` to drop privileges.
- Fix ownership on every start (backups/restores can reset it):
  ```bash
  chown -R cloudron:cloudron /app/data
  ```
- Use `exec` as the last command to forward SIGTERM:
  ```bash
  exec gosu cloudron:cloudron node /app/code/server.js
  ```
- Track first-run with a marker file:
  ```bash
  if [[ ! -f /app/data/.initialized ]]; then
    # first-time setup
    touch /app/data/.initialized
  fi
  ```

### Writable directories

| Path | Persists across restarts | Backed up |
|------|--------------------------|-----------|
| `/tmp` | No | No |
| `/run` | No | No |
| `/app/data` | Yes | Yes (requires `localstorage` addon) |

Put runtime config (generated files) in `/run`. Put persistent data in `/app/data`.

### Logging

Log to stdout/stderr. The platform manages rotation and streaming.

If the app cannot log to stdout, write to `/run/<subdir>/*.log` (two levels deep). These files are autorotated.

### Multiple processes

Use `supervisor` or `pm2` when the app has multiple components. Single-process apps do not need a process manager. Configure supervisor to send output to stdout:

```ini
[program:app]
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
```

### Memory-aware worker count

```bash
if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
    memory_limit=$(cat /sys/fs/cgroup/memory.max)
    [[ "${memory_limit}" == "max" ]] && memory_limit=$((2 * 1024 * 1024 * 1024))
else
    memory_limit=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)
fi
worker_count=$((memory_limit / 1024 / 1024 / 150))
worker_count=$((worker_count > 8 ? 8 : worker_count))
worker_count=$((worker_count < 1 ? 1 : worker_count))
```

## Manifest essentials

Minimal `CloudronManifest.json`:

```json
{
  "id": "com.example.myapp",
  "title": "My App",
  "author": "Jane Developer <jane@example.com>",
  "version": "1.0.0",
  "healthCheckPath": "/",
  "httpPort": 8000,
  "addons": {
    "localstorage": {}
  },
  "manifestVersion": 2
}
```

Common fields:

| Field | Purpose |
|-------|---------|
| `httpPort` | TCP port the app listens on (HTTP only) |
| `healthCheckPath` | Path returning 2xx when app is healthy |
| `addons` | Addon requirements (see below) |
| `version` | Semver package version |
| `memoryLimit` | Max memory in bytes (default 256 MB) |
| `tcpPorts` / `udpPorts` | Non-HTTP port bindings exposed to the user |
| `httpPorts` | Additional HTTP services on secondary domains |
| `multiDomain` | Enable alias domains |
| `optionalSso` | Allow install without user management |
| `configurePath` | Admin panel path shown in dashboard |
| `postInstallMessage` | Markdown shown after install (supports `<sso>`/`<nosso>` tags) |
| `minBoxVersion` | Minimum platform version required |

For the full field reference, see [manifest-ref.md](manifest-ref.md).

## Addons overview

Declare addons in the manifest `addons` object. Env vars are injected at runtime.

| Addon | Provides | Key env var |
|-------|----------|-------------|
| `localstorage` | Writable `/app/data`, backup support, optional FTP/SQLite | — |
| `mysql` | MySQL 8.0 database | `CLOUDRON_MYSQL_URL` |
| `postgresql` | PostgreSQL 14.9 database | `CLOUDRON_POSTGRESQL_URL` |
| `mongodb` | MongoDB 8.0 database | `CLOUDRON_MONGODB_URL` |
| `redis` | Redis 8.4 cache (persistent) | `CLOUDRON_REDIS_URL` |
| `ldap` | LDAP v3 authentication | `CLOUDRON_LDAP_URL` |
| `oidc` | OpenID Connect authentication | `CLOUDRON_OIDC_DISCOVERY_URL` |
| `sendmail` | Outgoing email (SMTP relay) | `CLOUDRON_MAIL_SMTP_SERVER` |
| `recvmail` | Incoming email (IMAP) | `CLOUDRON_MAIL_IMAP_SERVER` |
| `email` | Full email (SMTP + IMAP + Sieve) | multiple |
| `proxyauth` | Authentication wall in front of app | — |
| `scheduler` | Cron-like periodic tasks | — |
| `tls` | App certificate files | `/etc/certs/tls_cert.pem` |
| `turn` | STUN/TURN service | `CLOUDRON_TURN_SERVER` |
| `docker` | Create containers (restricted) | `CLOUDRON_DOCKER_HOST` |

Read env vars at runtime on every start — values can change across restarts. Run DB migrations on each start.

For full env var lists and addon options, see [addons-ref.md](addons-ref.md).

## Build methods

### On-server (default)

`cloudron install` and `cloudron update` upload the source and build on the server. No local Docker needed. Simplest workflow but uses server CPU/RAM.

### Local Docker build

Build locally with Docker, push to a registry, install with the image:

```bash
docker login
cloudron build              # builds, tags, pushes
cloudron install             # detects the built image
cloudron build && cloudron update   # update cycle
```

Or manually: `docker build -t user/app:tag . && docker push user/app:tag && cloudron install --image user/app:tag`

Use `cloudron build reset` to clear saved repository/image info.

### Build service

Offload builds to a remote [Docker Builder App](https://docs.cloudron.io/packages/docker-builder/):

```bash
cloudron build login         # authenticate with build service
cloudron build               # source sent to remote builder
```

## Debugging

```bash
cloudron logs                # view app logs
cloudron logs -f             # follow logs in real time
cloudron exec                # shell into running app
cloudron debug               # pause app (read-write filesystem)
cloudron debug --disable     # exit debug mode
```

## Stack-specific notes

**Apache** — Disable default sites, set `Listen 8000`, log errors to stderr, start with `exec /usr/sbin/apache2 -DFOREGROUND`.

**Nginx** — Use `/run/` for temp paths (`client_body_temp_path`, `proxy_temp_path`, etc.). Run with supervisor alongside the app.

**PHP** — Move sessions from `/var/lib/php/sessions` to `/run/php/sessions` via symlink.

**Java** — Read cgroup memory limit and set `-XX:MaxRAM` accordingly.

## Examples

All published Cloudron apps are open source: https://git.cloudron.io/packages

Browse by framework:
[PHP](https://git.cloudron.io/explore/projects?tag=php) ·
[Node](https://git.cloudron.io/explore/projects?tag=node) ·
[Python](https://git.cloudron.io/explore/projects?tag=python) ·
[Ruby/Rails](https://git.cloudron.io/explore/projects?tag=rails) ·
[Java](https://git.cloudron.io/explore/projects?tag=java) ·
[Go](https://git.cloudron.io/explore/projects?tag=go) ·
[Rust](https://git.cloudron.io/explore/projects?tag=rust)

## Additional resources

- For the full manifest field reference, see [manifest-ref.md](manifest-ref.md).
- For addon env vars and options, see [addons-ref.md](addons-ref.md).
- Ask questions: [App Packaging & Development forum](https://forum.cloudron.io/category/96/app-packaging-development)
