#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

flutter build web --release --pwa-strategy=none
node worker/scripts/inject-service-worker.mjs

if rg -l --hidden --glob '!*.map' \
  'LTA_ACCOUNT_KEY|ONEMAP_TOKEN|APP_API_KEY|VAPID_PRIVATE_KEY' build/web; then
  echo "Secret marker found in Web output" >&2
  exit 1
fi
