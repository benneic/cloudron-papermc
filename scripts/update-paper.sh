#!/bin/bash
set -eu

PROJECT="paper"
SERVER_DIR="/app/data/server"
JAR_PATH="${SERVER_DIR}/paper.jar"
BUILD_FILE="${SERVER_DIR}/.paper-build"
USER_AGENT="cloudron-papermc/1.0.0 (https://github.com/benneic/cloudron-papermc)"

echo "[update-paper] Checking for latest PaperMC version..."

# Get latest version
LATEST_VERSION=$(curl -sf -H "User-Agent: ${USER_AGENT}" \
    "https://fill.papermc.io/v3/projects/${PROJECT}" | \
    jq -r '.versions | to_entries[0] | .value[0]')

if [ -z "${LATEST_VERSION}" ] || [ "${LATEST_VERSION}" = "null" ]; then
    echo "[update-paper] ERROR: Could not determine latest version"
    exit 1
fi

echo "[update-paper] Latest Minecraft version: ${LATEST_VERSION}"

# Get latest stable build
BUILDS_RESPONSE=$(curl -sf -H "User-Agent: ${USER_AGENT}" \
    "https://fill.papermc.io/v3/projects/${PROJECT}/versions/${LATEST_VERSION}/builds")

LATEST_BUILD=$(echo "${BUILDS_RESPONSE}" | \
    jq -r 'map(select(.channel == "STABLE")) | .[0] | .id')
DOWNLOAD_URL=$(echo "${BUILDS_RESPONSE}" | \
    jq -r 'map(select(.channel == "STABLE")) | .[0] | .downloads."server:default".url')

if [ -z "${LATEST_BUILD}" ] || [ "${LATEST_BUILD}" = "null" ]; then
    echo "[update-paper] No stable build found for ${LATEST_VERSION}, trying any channel..."
    LATEST_BUILD=$(echo "${BUILDS_RESPONSE}" | jq -r '.[0] | .id')
    DOWNLOAD_URL=$(echo "${BUILDS_RESPONSE}" | jq -r '.[0] | .downloads."server:default".url')
fi

if [ -z "${LATEST_BUILD}" ] || [ "${LATEST_BUILD}" = "null" ]; then
    echo "[update-paper] ERROR: No builds found for ${LATEST_VERSION}"
    exit 1
fi

echo "[update-paper] Latest build: ${LATEST_BUILD}"

# Check if we already have this build
CURRENT_BUILD=""
if [ -f "${BUILD_FILE}" ]; then
    CURRENT_BUILD=$(cat "${BUILD_FILE}")
fi

if [ "${CURRENT_BUILD}" = "${LATEST_VERSION}-${LATEST_BUILD}" ]; then
    echo "[update-paper] Already running latest build (${LATEST_VERSION}-${LATEST_BUILD})"
    exit 0
fi

echo "[update-paper] Downloading: ${DOWNLOAD_URL}"
curl -sf -H "User-Agent: ${USER_AGENT}" -o "${JAR_PATH}.tmp" "${DOWNLOAD_URL}"

mv "${JAR_PATH}.tmp" "${JAR_PATH}"
echo "${LATEST_VERSION}-${LATEST_BUILD}" > "${BUILD_FILE}"
chown cloudron:cloudron "${JAR_PATH}" "${BUILD_FILE}"

echo "[update-paper] Updated to PaperMC ${LATEST_VERSION} build ${LATEST_BUILD}"
