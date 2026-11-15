#!/usr/bin/env bash
# Prepares the itch.io build: tests, a size-optimised web build, a zip. Pushes ONLY with --push. Never commits,
# never deletes anything but its own zip. Usage: tools/ship.sh [--push]
#
# Page: https://thegrumpygamedev.itch.io/skirmishers-of-splorr (created as a draft November 15, 2026, edit id 5368297).
# New pages use the html channel; do not rename it once the page is live.
set -euo pipefail
cd "$(dirname "$0")/.."
ODIN=${ODIN:-odin}
TARGET="thegrumpygamedev/skirmishers-of-splorr:html"
ZIP="build/skirmishers-of-splorr-html5.zip"

ODIN="$ODIN" ./test.sh
ODIN="$ODIN" OPT=size ./build.sh
rm -f "$ZIP"
(cd build/web && zip -q -9 -r "../skirmishers-of-splorr-html5.zip" .) # index.html at the zip's root
echo "zip: $ZIP ($(du -h "$ZIP" | cut -f1)); wasm $(du -h build/web/game.wasm | cut -f1)"
unzip -l "$ZIP" | tail -6

if [[ "${1:-}" == "--push" ]]; then
	if [[ -z "$TARGET" ]]; then
		echo "refusing to push: TARGET is not set in tools/ship.sh (create the itch.io page first)" >&2
		exit 1
	fi
	if [[ -n "$(git status --porcelain)" ]]; then echo "note: the working tree has uncommitted changes; what is pushed is the working tree, not a commit"; fi
	butler push build/web "$TARGET"
	echo "pushed to $TARGET. It goes live after itch.io processes it; check: butler status $TARGET"
else
	echo "not pushed (run tools/ship.sh --push when you want it live; target: ${TARGET:-<not set yet>})"
fi
