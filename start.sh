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

    # Copy Geyser default config so bedrock port and auth-type are pre-configured
    mkdir -p "${SERVER_DIR}/plugins/Geyser-Spigot"
    cp /app/code/config/Geyser-Spigot/config.yml "${SERVER_DIR}/plugins/Geyser-Spigot/config.yml"
fi

chown -R cloudron:cloudron "${SERVER_DIR}"

# ============================================================
# PaperMC JAR — keep in sync with PAPER_MC_VERSION (see Dockerfile / Cloudron env)
# ============================================================
echo "=> PaperMC target version: ${PAPER_MC_VERSION:-1.21.11}"
/app/code/scripts/update-paper.sh

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
# Write server port into server.properties if MINECRAFT_PORT is set
# ============================================================
if [ -n "${MINECRAFT_PORT:-}" ]; then
    sed -i "s/^server-port=.*/server-port=25565/" "${SERVER_DIR}/server.properties"
    echo "=> Minecraft port mapped: external ${MINECRAFT_PORT} -> container 25565"
fi

# ============================================================
# Write bedrock port into Geyser config if GEYSER_PORT is set
# ============================================================
GEYSER_CONFIG="${SERVER_DIR}/plugins/Geyser-Spigot/config.yml"
if [ -n "${GEYSER_PORT:-}" ] && [ -f "${GEYSER_CONFIG}" ]; then
    sed -i "s/^  port: .*/  port: 19132/" "${GEYSER_CONFIG}"
    echo "=> Geyser port mapped: external ${GEYSER_PORT} -> container 19132"
fi

# ============================================================
# Optional: delete world data (incompatible level.dat after MC/Paper downgrade, etc.)
# Set PAPERMC_RESET_WORLD=1 in Cloudron env, deploy once, then remove it.
# ============================================================
if [ "${PAPERMC_RESET_WORLD:-}" = "1" ] || [ "${PAPERMC_RESET_WORLD:-}" = "true" ]; then
    if [ -f "${SERVER_DIR}/server.properties" ]; then
        LEVEL_NAME="$(grep -E '^level-name=' "${SERVER_DIR}/server.properties" | head -1 | cut -d= -f2- | tr -d '\r')"
        LEVEL_NAME="${LEVEL_NAME:-world}"
        echo "=> PAPERMC_RESET_WORLD: removing saves for level-name=${LEVEL_NAME}"
        rm -rf "${SERVER_DIR}/${LEVEL_NAME}" "${SERVER_DIR}/${LEVEL_NAME}_nether" "${SERVER_DIR}/${LEVEL_NAME}_the_end"
    fi
fi

PLUGINS_DIR="${SERVER_DIR}/plugins"
mkdir -p "${PLUGINS_DIR}"
chown cloudron:cloudron "${PLUGINS_DIR}"

# ============================================================
# Web panel first (Cloudron health-checks httpPort during long plugin downloads)
# ============================================================
echo "=> Starting web panel on port 3000"
cd /app/code/web
gosu cloudron:cloudron node server.js &
WEB_PID=$!

# ============================================================
# Install Geyser and Floodgate plugins
# ============================================================
/app/code/scripts/install-plugins.sh "${PLUGINS_DIR}"
chown -R cloudron:cloudron "${PLUGINS_DIR}"

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
