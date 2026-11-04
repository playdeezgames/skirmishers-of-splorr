#!/usr/bin/env bash
# Builds the wasm game into build/web, ready to serve.
set -euo pipefail
cd "$(dirname "$0")"
ODIN=${ODIN:-odin}
OUT=build/web
mkdir -p "$OUT"
"$ODIN" build src -target:js_wasm32 -out:"$OUT/game.wasm" -o:"${OPT:-speed}" -vet -strict-style "$@"
cp web/index.html "$OUT/"
cp "$("$ODIN" root)/core/sys/wasm/js/odin.js" "$OUT/"
