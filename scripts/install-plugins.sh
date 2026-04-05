#!/bin/bash
# Downloads Geyser and Floodgate plugins if not already present.
# Usage: install-plugins.sh <plugins-dir>
set -eu

PLUGINS_DIR="${1:-/app/data/server/plugins}"
mkdir -p "${PLUGINS_DIR}"

GEYSER_JAR="${PLUGINS_DIR}/Geyser-Spigot.jar"
FLOODGATE_JAR="${PLUGINS_DIR}/floodgate-spigot.jar"

GEYSER_URL="https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot"
FLOODGATE_URL="https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot"

if [ ! -f "${GEYSER_JAR}" ]; then
    echo "=> Downloading Geyser-Spigot plugin..."
    curl -fsSL -o "${GEYSER_JAR}" "${GEYSER_URL}"
    echo "=> Geyser downloaded"
else
    echo "=> Geyser already installed, skipping"
fi

if [ ! -f "${FLOODGATE_JAR}" ]; then
    echo "=> Downloading Floodgate plugin..."
    curl -fsSL -o "${FLOODGATE_JAR}" "${FLOODGATE_URL}"
    echo "=> Floodgate downloaded"
else
    echo "=> Floodgate already installed, skipping"
fi
