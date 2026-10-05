#!/usr/bin/env bash
# Build the signed .app and launch it (the demo path).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
./scripts/make-app.sh
open build/Clicky.app
echo "Clicky launched — look for the waveform icon in the menu bar."
