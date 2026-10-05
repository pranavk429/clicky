#!/usr/bin/env bash
# Assembles + signs build/Clicky.app — THE DEMO PATH (errata B16).
# swift run is dev-only: a bare executable carries no LSUIElement/usage
# descriptions, and macOS kills its microphone access.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
CONFIG="${CONFIG:-release}"
APP="build/Clicky.app"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
./scripts/sign-dev.sh verify
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ClickyApp" "$APP/Contents/MacOS/Clicky"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
# Fixed identifier + fixed certificate = stable designated requirement = TCC survives rebuilds.
codesign --force --options runtime --timestamp=none -s "Clicky-Dev" -i com.clicky.mac "$APP"
codesign --verify --deep --strict "$APP"
echo "Built and signed: $APP   (launch: open $APP)"
