#!/usr/bin/env bash
# Builds the shipping (size-optimised) game into docs/ for GitHub Pages.
# It does not commit or push: commit docs/ and push main to update the page at
#   https://playdeezgames.github.io/skirmishers-of-splorr/
set -euo pipefail
cd "$(dirname "$0")/.."
OPT=size ./build.sh
rm -rf docs
mkdir docs
cp -r build/web/. docs/
touch docs/.nojekyll
ls -la docs
