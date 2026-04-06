#!/bin/bash
set -eu

PROJECT="paper"
SERVER_DIR="/app/data/server"
JAR_PATH="${SERVER_DIR}/paper.jar"
BUILD_FILE="${SERVER_DIR}/.paper-build"
USER_AGENT="cloudron-papermc/1.0.0 (https://github.com/benneic/cloudron-papermc)"

TARGET_VERSION="${PAPER_MC_VERSION:-1.21.11}"

echo "[auto-update] $(date) — Checking PaperMC ${TARGET_VERSION} for updates..."

BUILDS_RESPONSE=$(curl -sf -H "User-Agent: ${USER_AGENT}" \
    "https://fill.papermc.io/v3/projects/${PROJECT}/versions/${TARGET_VERSION}/builds" 2>/dev/null || echo "")

if [ -z "${BUILDS_RESPONSE}" ]; then
    echo "[auto-update] Could not fetch builds, skipping"
    exit 0
fi

LATEST_BUILD=$(echo "${BUILDS_RESPONSE}" | \
    jq -r 'map(select(.channel == "STABLE")) | .[0] | .id' 2>/dev/null || echo "null")

if [ "${LATEST_BUILD}" = "null" ] || [ -z "${LATEST_BUILD}" ]; then
    echo "[auto-update] No stable build found for ${TARGET_VERSION}, skipping"
    exit 0
fi

# Compare with current
CURRENT_BUILD=""
if [ -f "${BUILD_FILE}" ]; then
    CURRENT_BUILD=$(cat "${BUILD_FILE}")
fi

NEW_BUILD_ID="${TARGET_VERSION}-${LATEST_BUILD}"

if [ "${CURRENT_BUILD}" = "${NEW_BUILD_ID}" ]; then
    echo "[auto-update] Already on latest (${NEW_BUILD_ID}), nothing to do"
    exit 0
fi

echo "[auto-update] New build available: ${NEW_BUILD_ID} (current: ${CURRENT_BUILD:-none})"

DOWNLOAD_URL=$(echo "${BUILDS_RESPONSE}" | \
    jq -r 'map(select(.channel == "STABLE")) | .[0] | .downloads."server:default".url')

if [ -z "${DOWNLOAD_URL}" ] || [ "${DOWNLOAD_URL}" = "null" ]; then
    echo "[auto-update] Could not determine download URL, skipping"
    exit 0
fi

# Download new jar
echo "[auto-update] Downloading ${DOWNLOAD_URL}..."
curl -sf -H "User-Agent: ${USER_AGENT}" -o "${JAR_PATH}.new" "${DOWNLOAD_URL}"

if [ ! -f "${JAR_PATH}.new" ]; then
    echo "[auto-update] Download failed, skipping"
    exit 0
fi

# Stop the Minecraft server by sending SIGTERM to Java processes
echo "[auto-update] Stopping Minecraft server..."
MC_PIDS=$(pgrep -f "java.*paper.jar" || true)
if [ -n "${MC_PIDS}" ]; then
    for pid in ${MC_PIDS}; do
        kill -TERM "${pid}" 2>/dev/null || true
    done
    # Wait up to 30 seconds for graceful shutdown
    for i in $(seq 1 30); do
        if ! pgrep -f "java.*paper.jar" > /dev/null 2>&1; then
            break
        fi
        sleep 1
    done
    # Force kill if still running
    pkill -9 -f "java.*paper.jar" 2>/dev/null || true
fi

# Swap the jar
mv "${JAR_PATH}.new" "${JAR_PATH}"
echo "${NEW_BUILD_ID}" > "${BUILD_FILE}"
chown cloudron:cloudron "${JAR_PATH}" "${BUILD_FILE}"

# Match Bedrock plugins to new Paper (avoids Geyser/Floodgate API drift)
/app/code/scripts/install-plugins.sh "${SERVER_DIR}/plugins"
chown -R cloudron:cloudron "${SERVER_DIR}/plugins" 2>/dev/null || true

echo "[auto-update] Updated to ${NEW_BUILD_ID}. Restarting server..."

# Restart the Minecraft server
cd "${SERVER_DIR}"
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
    ram=$(cat /sys/fs/cgroup/memory.max)
    [ "${ram}" = "max" ] && ram=$((2 * 1024 * 1024 * 1024))
else
    ram=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)
fi
ram_mb=$((ram / 1024 / 1024))
java_mb=$((ram_mb - 256))
[ ${java_mb} -lt 512 ] && java_mb=512

JAVA_OPTS="-Xms${java_mb}M -Xmx${java_mb}M -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200"
gosu cloudron:cloudron java ${JAVA_OPTS} -jar "${JAR_PATH}" --nogui &

echo "[auto-update] Minecraft server restarted with new build ${NEW_BUILD_ID}"
