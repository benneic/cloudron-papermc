---
name: cloudron-server-ops
description: Manage apps on a Cloudron server using the cloudron CLI. Covers authentication, listing, logs, exec, sync/push/pull, backups, env vars, start/stop/restart, and CI/CD integration. Use when the user wants to manage, debug, or operate installed Cloudron apps, or mentions cloudron CLI commands like cloudron logs, cloudron exec, cloudron sync, cloudron backup, or cloudron env.
---

# Cloudron Server Operations

The `cloudron` CLI manages apps on a Cloudron server. All commands operate on apps, not the server itself.

## Setup

```bash
sudo npm install -g cloudron      # install on your PC/Mac, NOT on the server
cloudron login my.example.com     # opens browser for authentication
```

Token is stored in `~/.cloudron.json`.

For self-signed certificates: `cloudron login my.example.com --allow-selfsigned`

## App targeting

Most commands require `--app` to specify which app:

```bash
cloudron logs --app blog.example.com              # by FQDN
cloudron logs --app blog                           # by subdomain/location
cloudron logs --app 52aae895-5b7d-4625-8d4c-...   # by app ID
```

When run from a directory with `CloudronManifest.json` and a previously installed app, the CLI auto-detects the app (stored as `appId` in the per-directory config).

## Commands

### Listing and inspection

```bash
cloudron list                  # all installed apps
cloudron list -q               # quiet (IDs only)
cloudron list --tag web        # filter by tag
cloudron status --app <app>    # app details (status, domain, memory, image)
cloudron inspect               # raw JSON of the Cloudron server
```

### App lifecycle

```bash
cloudron install               # install app (on-server build or --image)
cloudron update --app <app>    # update app (rebuilds or uses --image)
cloudron uninstall --app <app>
cloudron repair --app <app>    # reconfigure app without changing image
cloudron clone --app <app> --location new-location
```

`cloudron install` and `cloudron update` accept:
- `--image <repo:tag>` — use a pre-built Docker image
- `--no-backup` — skip backup before update
- `-l, --location <subdomain>` — set the app location
- `-s, --secondary-domains <domains>` — secondary domain bindings
- `-p, --port-bindings <bindings>` — TCP/UDP port bindings
- `-m, --memory-limit <bytes>` — override memory limit
- `--versions-url <url>` — install a community app from a CloudronVersions.json URL

### Run state

```bash
cloudron start --app <app>
cloudron stop --app <app>
cloudron restart --app <app>
cloudron cancel --app <app>     # cancel pending task
```

### Logs

```bash
cloudron logs --app <app>              # recent logs
cloudron logs --app <app> -f           # follow (tail)
cloudron logs --app <app> -l 200       # last 200 lines
cloudron logs --system                 # platform system logs
cloudron logs --system mail            # specific system service
```

### Shell and exec

```bash
cloudron exec --app <app>                              # interactive shell
cloudron exec --app <app> -- ls -la /app/data          # run a command
cloudron exec --app <app> -- bash -c 'echo $CLOUDRON_MYSQL_URL'  # with env vars
```

### Debug mode

When an app keeps crashing, `cloudron exec` may disconnect. Debug mode pauses the app (skips CMD) and makes the filesystem read-write:

```bash
cloudron debug --app <app>             # enter debug mode
cloudron debug --app <app> --disable   # exit debug mode
```

### File transfer

```bash
cloudron push --app <app> local.txt /tmp/remote.txt    # push file
cloudron push --app <app> localdir /tmp/                # push directory
cloudron pull --app <app> /app/data/file.txt .          # pull file
cloudron pull --app <app> /app/data/ ./backup/          # pull directory
cloudron sync push --app <app> ./local/ /app/data       # sync local contents -> remote (changed files only)
cloudron sync push --app <app> ./local /app/data        # sync local dir itself into /app/data/local
cloudron sync push --app <app> file.txt /app/data       # sync single file -> remote
cloudron sync pull --app <app> /app/data/ ./local       # sync remote contents -> local (changed files only)
cloudron sync pull --app <app> /app/data ./local        # sync remote dir itself into ./local/data
cloudron sync push --app <app> ./local/ /app/data --delete  # also delete remote-only files
cloudron sync pull --app <app> /app/data/ ./local --delete  # also delete local-only files
```

A trailing slash on the source syncs its contents; without it, the directory itself is placed inside the destination (rsync convention).
Use `--delete` to remove files present only on the destination side. Use `--force` to remove files blocking directory creation.
For directory transfers, prefer `cloudron sync`; keep `cloudron push`/`pull` for one-off file copy and stream-oriented use cases.

### Environment variables

```bash
cloudron env list --app <app>
cloudron env get --app <app> MY_VAR
cloudron env set --app <app> MY_VAR=value OTHER=val2    # restarts app
cloudron env unset --app <app> MY_VAR                   # restarts app
```

### Configuration

```bash
cloudron set-location --app <app> -l new-subdomain
cloudron set-location --app <app> -s "api.example.com"  # secondary domain
cloudron set-location --app <app> -p "SSH_PORT=2222"    # port binding
```

### Backups

```bash
cloudron backup create --app <app>                      # create backup
cloudron backup list --app <app>                        # list backups
cloudron restore --app <app> --backup <backup-id>       # restore from backup
cloudron export --app <app>                             # export to backup storage
cloudron import --app <app> --backup-path /path         # import external backup
```

Backup encryption utilities (local, offline):

```bash
cloudron backup decrypt <infile> <outfile> --password <pw>
cloudron backup decrypt-dir <indir> <outdir> --password <pw>
cloudron backup encrypt <infile> <outfile> --password <pw>
```

### Utilities

```bash
cloudron open --app <app>       # open app in browser
cloudron init                   # create CloudronManifest.json + Dockerfile
cloudron completion             # shell completion
```

## CI/CD integration

Use `--server` and `--token` to run commands non-interactively. Get API tokens from `https://my.example.com/#/profile`:

```bash
cloudron update \
  --server my.example.com \
  --token 001e7174c4cbad2272 \
  --app blog.example.com \
  --image username/image:tag
```

## Global options

These apply to most commands:

| Option | Purpose |
|--------|---------|
| `--server <domain>` | Target Cloudron server |
| `--token <token>` | API token (for CI/CD) |
| `--allow-selfsigned` | Accept self-signed TLS certificates |
| `--no-wait` | Do not wait for the operation to complete |

## Common workflows

### Check and restart a misbehaving app

```bash
cloudron status --app <app>
cloudron logs --app <app> -l 100
cloudron restart --app <app>
```

### Debug a crashing app

```bash
cloudron debug --app <app>
cloudron exec --app <app>
# inspect filesystem, check logs, test manually
cloudron debug --app <app> --disable
```

### Backup and restore

```bash
cloudron backup create --app <app>
cloudron backup list --app <app>
# note the backup ID
cloudron restore --app <app> --backup <id>
```

### Set env vars for an app

```bash
cloudron env set --app <app> FEATURE_FLAG=true DEBUG=1
# app restarts automatically
cloudron logs --app <app> -f
```
