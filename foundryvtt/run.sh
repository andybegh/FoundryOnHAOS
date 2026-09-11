#!/usr/bin/env bash
set -Eeuo pipefail

OPTIONS_PATH="/data/options.json"
FOUNDRY_DATA_PATH="/config"
FOUNDRY_CACHE_PATH="${FOUNDRY_DATA_PATH}/container_cache"

value() {
  jq -r "$1 // empty" "${OPTIONS_PATH}"
}

ensure_symlink() {
  local target="$1"
  local link="$2"

  if [ -L "${link}" ]; then
    ln -sfn "${target}" "${link}"
  elif [ -e "${link}" ]; then
    echo "ATTENZIONE: ${link} esiste e non e un link simbolico; lo lascio invariato."
  else
    ln -s "${target}" "${link}"
  fi
}

FOUNDRY_USERNAME_OPT="$(value '.foundry_username')"
FOUNDRY_PASSWORD_OPT="$(value '.foundry_password')"
FOUNDRY_RELEASE_URL_OPT="$(value '.foundry_release_url')"
FOUNDRY_ADMIN_KEY="$(value '.foundry_admin_key')"
FOUNDRY_LICENSE_KEY="$(value '.foundry_license_key')"
FOUNDRY_TELEMETRY="$(value '.foundry_telemetry')"
CONTAINER_PRESERVE_CONFIG="$(value '.container_preserve_config')"
FORCE_DOWNLOAD="$(value '.force_download')"

export FOUNDRY_ADMIN_KEY
export FOUNDRY_LICENSE_KEY
export FOUNDRY_TELEMETRY
export CONTAINER_PRESERVE_CONFIG
export CONTAINER_CACHE="${FOUNDRY_CACHE_PATH}"
export CONTAINER_CACHE_SIZE="2"

mkdir -p \
  "${FOUNDRY_DATA_PATH}/Backups" \
  "${FOUNDRY_DATA_PATH}/Config" \
  "${FOUNDRY_DATA_PATH}/Data/assets" \
  "${FOUNDRY_DATA_PATH}/Logs" \
  "${FOUNDRY_CACHE_PATH}"

# The upstream image runs Foundry as node (uid/gid 1000).
chown -R 1000:1000 "${FOUNDRY_DATA_PATH}"
chmod -R u+rwX,g+rwX "${FOUNDRY_DATA_PATH}"

if [ -d /share ]; then
  ensure_symlink /share "${FOUNDRY_DATA_PATH}/Data/assets/haos-share"
fi

if [ -d /media ]; then
  ensure_symlink /media "${FOUNDRY_DATA_PATH}/Data/assets/haos-media"
fi

CACHED_RELEASE="${FOUNDRY_CACHE_PATH}/foundryvtt-${FOUNDRY_VERSION}.zip"
INSTALLED_RELEASE=""

if [ -f /home/node/resources/app/package.json ]; then
  INSTALLED_RELEASE="$(jq -r '.release | "\(.generation).\(.build)"' /home/node/resources/app/package.json)"
fi

if [ "${FORCE_DOWNLOAD}" = "true" ]; then
  echo "force_download=true: richiedo un nuovo download di Foundry VTT ${FOUNDRY_VERSION}."
  rm -f "${CACHED_RELEASE}"
  rm -rf /home/node/resources
  INSTALLED_RELEASE=""
  export FOUNDRY_USERNAME="${FOUNDRY_USERNAME_OPT}"
  export FOUNDRY_PASSWORD="${FOUNDRY_PASSWORD_OPT}"
  export FOUNDRY_RELEASE_URL="${FOUNDRY_RELEASE_URL_OPT}"
elif [ "${INSTALLED_RELEASE}" = "${FOUNDRY_VERSION}" ]; then
  echo "Foundry ${FOUNDRY_VERSION} e gia installato nel container: nessun download richiesto."
  unset FOUNDRY_USERNAME FOUNDRY_PASSWORD FOUNDRY_RELEASE_URL
elif [ -f "${CACHED_RELEASE}" ]; then
  echo "Cache Foundry ${FOUNDRY_VERSION} trovata: non uso URL o credenziali per il download."
  unset FOUNDRY_USERNAME FOUNDRY_PASSWORD FOUNDRY_RELEASE_URL
else
  echo "Cache Foundry ${FOUNDRY_VERSION} assente: abilito il download iniziale."
  export FOUNDRY_USERNAME="${FOUNDRY_USERNAME_OPT}"
  export FOUNDRY_PASSWORD="${FOUNDRY_PASSWORD_OPT}"
  export FOUNDRY_RELEASE_URL="${FOUNDRY_RELEASE_URL_OPT}"
fi

if [ "${INSTALLED_RELEASE}" != "${FOUNDRY_VERSION}" ] \
  && [ ! -f "${CACHED_RELEASE}" ] \
  && [ -z "${FOUNDRY_RELEASE_URL:-}" ] \
  && { [ -z "${FOUNDRY_USERNAME:-}" ] || [ -z "${FOUNDRY_PASSWORD:-}" ]; }; then
  echo "ERRORE: cache ${FOUNDRY_VERSION} assente. Configura foundry_release_url oppure foundry_username e foundry_password."
  exit 1
fi

echo "Foundry data path: ${FOUNDRY_DATA_PATH}"
echo "Foundry cache path: ${FOUNDRY_CACHE_PATH}"
echo "force_download: ${FORCE_DOWNLOAD}"

cd /home/node

exec gosu node:node ./entrypoint.sh \
  resources/app/main.mjs \
  --port=30000 \
  --headless \
  --noupdate \
  --dataPath="${FOUNDRY_DATA_PATH}"
