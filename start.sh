#!/bin/bash
set -eu

echo "=> PaperMC Cloudron App Starting..."

# ============================================================
# Data directory setup
# ============================================================
DATA_DIR="/app/data"
SERVER_DIR="${DATA_DIR}/server"
JAR_PATH="${SERVER_DIR}/paper.jar"

mkdir -p "${SERVER_DIR}" "${DATA_DIR}/backups"
chown -R cloudron:cloudron "${DATA_DIR}"

# ============================================================
# First-run: accept EULA and write default configs
# ============================================================
if [ ! -f "${SERVER_DIR}/eula.txt" ]; then
    echo "=> First run detected — writing defaults"
    echo "eula=true" > "${SERVER_DIR}/eula.txt"

    # Copy kid-friendly server.properties
    cp /app/code/config/server.properties "${SERVER_DIR}/server.properties"
    cp /app/code/config/spigot.yml "${SERVER_DIR}/spigot.yml"
    cp /app/code/config/bukkit.yml "${SERVER_DIR}/bukkit.yml"

    # ops.json — empty by default, user can edit via File Manager
    echo "[]" > "${SERVER_DIR}/ops.json"
    echo "[]" > "${SERVER_DIR}/whitelist.json"
fi

chown -R cloudron:cloudron "${SERVER_DIR}"

# ============================================================
# Download PaperMC if missing
# ============================================================
if [ ! -f "${JAR_PATH}" ]; then
    echo "=> Downloading PaperMC..."
    /app/code/scripts/update-paper.sh
fi

# ============================================================
# Calculate Java memory from cgroup limits
# ============================================================
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
    # cgroup v2
    ram=$(cat /sys/fs/cgroup/memory.max)
    [ "${ram}" = "max" ] && ram=$((2 * 1024 * 1024 * 1024))
else
    ram=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)
fi

ram_mb=$((ram / 1024 / 1024))
# Reserve 256MB for OS + web panel, give the rest to Java
java_mb=$((ram_mb - 256))
[ ${java_mb} -lt 512 ] && java_mb=512

echo "=> Container RAM: ${ram_mb}MB, Java heap: ${java_mb}MB"

export JAVA_OPTS="-Xms${java_mb}M -Xmx${java_mb}M -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200"

# ============================================================
# Set up cron for auto-updates (every 6 hours)
# ============================================================
CRON_FILE="/etc/cron.d/papermc-update"
cat > "${CRON_FILE}" <<'CRON'
0 */6 * * * root /app/code/scripts/auto-update.sh >> /tmp/papermc-update.log 2>&1
CRON
chmod 644 "${CRON_FILE}"
service cron start || true

# ============================================================
# Write server port into server.properties if MINECRAFT_PORT is set
# ============================================================
if [ -n "${MINECRAFT_PORT:-}" ]; then
    sed -i "s/^server-port=.*/server-port=25565/" "${SERVER_DIR}/server.properties"
    echo "=> Minecraft port mapped: external ${MINECRAFT_PORT} -> container 25565"
fi

# ============================================================
# Install Geyser and Floodgate plugins
# ============================================================
PLUGINS_DIR="${SERVER_DIR}/plugins"
mkdir -p "${PLUGINS_DIR}"
chown cloudron:cloudron "${PLUGINS_DIR}"
/app/code/scripts/install-plugins.sh "${PLUGINS_DIR}"
chown -R cloudron:cloudron "${PLUGINS_DIR}"

# ============================================================
# Start the web panel
# ============================================================
echo "=> Starting web panel on port 3000"
cd /app/code/web
exec gosu cloudron:cloudron node server.js &
WEB_PID=$!

# ============================================================
# Start PaperMC
# ============================================================
echo "=> Starting PaperMC server"
cd "${SERVER_DIR}"
exec gosu cloudron:cloudron java ${JAVA_OPTS} -jar "${JAR_PATH}" --nogui &
MC_PID=$!

echo "=> PaperMC PID: ${MC_PID}, Web PID: ${WEB_PID}"

# ============================================================
# Signal handling — graceful shutdown
# ============================================================
shutdown() {
    echo "=> Shutting down..."
    # Send 'stop' to the Minecraft server via its console
    if [ -f "${SERVER_DIR}/paper.pid" ]; then
        kill -TERM ${MC_PID} 2>/dev/null || true
    else
        kill -TERM ${MC_PID} 2>/dev/null || true
    fi
    kill -TERM ${WEB_PID} 2>/dev/null || true
    wait ${MC_PID} 2>/dev/null || true
    wait ${WEB_PID} 2>/dev/null || true
    echo "=> Shutdown complete"
    exit 0
}

trap shutdown SIGTERM SIGINT

# Wait for either process to exit
wait -n ${MC_PID} ${WEB_PID} 2>/dev/null || true
echo "=> A process exited, shutting down"
shutdown
