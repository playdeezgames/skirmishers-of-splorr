#!/usr/bin/env bash
# Runs the native rules tests. Extra arguments are passed on, for example
#   ./test.sh -define:ODIN_TEST_NAMES=game.test_dice_odds
set -euo pipefail
cd "$(dirname "$0")"
ODIN=${ODIN:-odin}
"$ODIN" test src/game -define:ODIN_TEST_THREADS=1 -vet -strict-style "$@"
