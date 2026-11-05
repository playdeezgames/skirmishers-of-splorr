#!/usr/bin/env bash
# Regenerates assets/screenshots/*.png and assets/cover.png from the real web build.
# Serves build/web on a spare port, captures each scenario with headless Chrome
# (?steps=N has the computer play N actions first), crops to the
# 1060x580 canvas, then builds the cover with tools/make_cover.py.
# Needs google-chrome and Python 3 with Pillow. Usage: tools/shots.sh
set -euo pipefail
cd "$(dirname "$0")/.."
OPT=size ./build.sh >/dev/null
PORT=${PORT:-8197}
if ss -ltn | grep -q ":$PORT "; then echo "port $PORT is in use; set PORT=..." >&2; exit 1; fi
python3 -m http.server -d build/web "$PORT" >/dev/null 2>&1 &
SERVER=$!
trap 'kill $SERVER' EXIT
sleep 1
mkdir -p build/shots assets/screenshots

# name, scenario (1-based), computer actions played before the picture
shot() {
	google-chrome --headless=new --no-sandbox --disable-gpu --hide-scrollbars \
		--window-size=1060,624 --virtual-time-budget=2000 \
		--screenshot="build/shots/$1.png" "http://localhost:$PORT/?scenario=$2&steps=$3" 2>/dev/null
}
shot 01-skirmish 1 0
shot 02-battle 3 90
shot 03-forest 6 0
shot 04-fight 2 22

python3 -I tools/make_cover.py build/shots assets
ls -la assets/screenshots assets/cover.png
