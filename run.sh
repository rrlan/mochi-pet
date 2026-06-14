#!/bin/bash
#
# Build (if needed) and launch Mochi.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Mochi.app"

if [ ! -d "$APP" ]; then
  "$ROOT/build.sh"
fi

# Relaunch a fresh instance.
pkill -x Mochi >/dev/null 2>&1 || true
open "$APP"
echo "Mochi launched. Look for the 🍡 in your menu bar."
