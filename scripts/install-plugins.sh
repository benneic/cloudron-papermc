#!/bin/bash
# Downloads Geyser and Floodgate, or refreshes them when Paper build changes.
# Old JARs with a new Paper version cause reflection errors (e.g. ItemStackParser).
# Usage: install-plugins.sh <plugins-dir>
set -eu

PLUGINS_DIR="${1:-/app/data/server/plugins}"
mkdir -p "${PLUGINS_DIR}"

SERVER_DIR="$(cd "$(dirname "${PLUGINS_DIR}")" && pwd)"
SYNC_MARKER="${SERVER_DIR}/.geyser-floodgate-paper-build"

GEYSER_JAR="${PLUGINS_DIR}/Geyser-Spigot.jar"
FLOODGATE_JAR="${PLUGINS_DIR}/floodgate-spigot.jar"

GEYSER_URL="https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot"
FLOODGATE_URL="https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot"

PAPER_BUILD=""
if [ -f "${SERVER_DIR}/.paper-build" ]; then
    PAPER_BUILD="$(tr -d '\n' < "${SERVER_DIR}/.paper-build")"
fi

PREVIOUS=""
if [ -f "${SYNC_MARKER}" ]; then
    PREVIOUS="$(tr -d '\n' < "${SYNC_MARKER}")"
fi

need_download=0
if [ ! -f "${GEYSER_JAR}" ] || [ ! -f "${FLOODGATE_JAR}" ]; then
    need_download=1
elif [ -n "${PAPER_BUILD}" ] && [ "${PAPER_BUILD}" != "${PREVIOUS}" ]; then
    need_download=1
fi

if [ "${need_download}" -eq 0 ]; then
    echo "=> Geyser and Floodgate already synced for Paper ${PAPER_BUILD:-unknown}, skipping"
    exit 0
fi

echo "=> Refreshing Geyser/Floodgate (Paper build: ${PAPER_BUILD:-unknown})..."
curl -fsSL -o "${GEYSER_JAR}.tmp" "${GEYSER_URL}"
mv "${GEYSER_JAR}.tmp" "${GEYSER_JAR}"

curl -fsSL -o "${FLOODGATE_JAR}.tmp" "${FLOODGATE_URL}"
mv "${FLOODGATE_JAR}.tmp" "${FLOODGATE_JAR}"

if [ -n "${PAPER_BUILD}" ]; then
    printf '%s' "${PAPER_BUILD}" > "${SYNC_MARKER}"
else
    rm -f "${SYNC_MARKER}"
fi

echo "=> Geyser and Floodgate installed"
