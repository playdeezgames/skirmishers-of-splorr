#!/usr/bin/env bash
# Balance simulator: computer-vs-computer battles between two armies.
#   tools/sim.sh 2k2s 4k -n 1000
# Run with no arguments for the full usage.
set -euo pipefail
cd "$(dirname "$0")/.."
ODIN=${ODIN:-odin}
mkdir -p build
"$ODIN" build tools/sim -o:speed -out:build/sim -vet -strict-style
exec build/sim "$@"
