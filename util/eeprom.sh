#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f /etc/default/weather-initialization ]]; then
    # shellcheck disable=SC1091
    source /etc/default/weather-initialization
fi

VANTAGE_PUBLISHER_DIR="${VANTAGE_PUBLISHER_DIR:-$HOME/vantage-publisher}"
WEATHER_DEVICE_URL="${WEATHER_DEVICE_URL:-tcp:127.0.0.1:22222}"
STORAGE_DIR="${STORAGE_DIR:-/storage}"

echo "Starting EEPROM archive backup..."
cd "${VANTAGE_PUBLISHER_DIR}"

YEAR="$(date +"%Y")"
MONTH="$(date +"%m")"
BASE_PATH="${STORAGE_DIR}/eeprom"

mkdir -p "${BASE_PATH}/${YEAR}"

CSV_DB="${BASE_PATH}/${YEAR}/${YEAR}-${MONTH}.csv"
START_DATE="${YEAR}-${MONTH}-01 00:00"

docker compose down
trap 'docker compose up -d' EXIT

python3 "${INSTALL_DIR}/util/backup-eeprom.py" "${WEATHER_DEVICE_URL}" \
    --start "${START_DATE}" \
    --output "${CSV_DB}"

echo "EEPROM backup updated: ${CSV_DB}"
