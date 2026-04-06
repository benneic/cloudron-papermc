#!/bin/bash
set -eu

PROJECT="paper"
SERVER_DIR="/app/data/server"
JAR_PATH="${SERVER_DIR}/paper.jar"
BUILD_FILE="${SERVER_DIR}/.paper-build"
USER_AGENT="cloudron-papermc/1.0.0 (https://github.com/benneic/cloudron-papermc)"

# Do not use fill.papermc.io "first" version key (that is Paper 26.x); Geyser/Floodgate lag behind.
TARGET_VERSION="${PAPER_MC_VERSION:-1.21.11}"

echo "[update-paper] Checking PaperMC builds for Minecraft ${TARGET_VERSION}..."

BUILDS_RESPONSE=$(curl -sf -H "User-Agent: ${USER_AGENT}" \
    "https://fill.papermc.io/v3/projects/${PROJECT}/versions/${TARGET_VERSION}/builds" || true)

if [ -z "${BUILDS_RESPONSE}" ]; then
    echo "[update-paper] ERROR: Could not fetch builds for ${TARGET_VERSION}"
    exit 1
fi

LATEST_BUILD=$(echo "${BUILDS_RESPONSE}" | \
    jq -r 'map(select(.channel == "STABLE")) | .[0] | .id')
DOWNLOAD_URL=$(echo "${BUILDS_RESPONSE}" | \
    jq -r 'map(select(.channel == "STABLE")) | .[0] | .downloads."server:default".url')

if [ -z "${LATEST_BUILD}" ] || [ "${LATEST_BUILD}" = "null" ]; then
    echo "[update-paper] No stable build found for ${TARGET_VERSION}, trying any channel..."
    LATEST_BUILD=$(echo "${BUILDS_RESPONSE}" | jq -r '.[0] | .id')
    DOWNLOAD_URL=$(echo "${BUILDS_RESPONSE}" | jq -r '.[0] | .downloads."server:default".url')
fi

if [ -z "${LATEST_BUILD}" ] || [ "${LATEST_BUILD}" = "null" ]; then
    echo "[update-paper] ERROR: No builds found for ${TARGET_VERSION} (wrong PAPER_MC_VERSION?)"
    exit 1
fi

echo "[update-paper] Latest stable build: ${LATEST_BUILD}"

# Check if we already have this build
CURRENT_BUILD=""
if [ -f "${BUILD_FILE}" ]; then
    CURRENT_BUILD=$(cat "${BUILD_FILE}")
fi

NEW_BUILD_ID="${TARGET_VERSION}-${LATEST_BUILD}"

if [ "${CURRENT_BUILD}" = "${NEW_BUILD_ID}" ]; then
    echo "[update-paper] Already on ${NEW_BUILD_ID}"
    exit 0
fi

echo "[update-paper] Downloading: ${DOWNLOAD_URL}"
curl -sf -H "User-Agent: ${USER_AGENT}" -o "${JAR_PATH}.tmp" "${DOWNLOAD_URL}"

mv "${JAR_PATH}.tmp" "${JAR_PATH}"
echo "${NEW_BUILD_ID}" > "${BUILD_FILE}"
chown cloudron:cloudron "${JAR_PATH}" "${BUILD_FILE}"

echo "[update-paper] Updated to PaperMC ${NEW_BUILD_ID}"
