#!/usr/bin/env bash
# Builds the wasm game into build/web, ready to serve.
set -euo pipefail
cd "$(dirname "$0")"
ODIN=${ODIN:-odin}
OUT=build/web
mkdir -p "$OUT"
"$ODIN" build src -target:js_wasm32 -out:"$OUT/game.wasm" -o:"${OPT:-speed}" -vet -strict-style "$@"
cp web/index.html "$OUT/"
# art and sound made in the Anvil (assets/art/world.json, assets/sfx/*.wav)
python3 tools/gen_atlas.py assets/art/world.json "$OUT/art.png" >/dev/null
mkdir -p "$OUT/sfx"
cp assets/sfx/*.wav "$OUT/sfx/"
cp "$("$ODIN" root)/core/sys/wasm/js/odin.js" "$OUT/"
