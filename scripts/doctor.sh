#!/usr/bin/env bash
# Demo pre-flight. Exits non-zero on any hard failure.
# TCC permission state itself is verified by the app's permission wizard.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
FAIL=0
ok()   { printf '  ok   %s\n' "$1"; }
warn() { printf '  warn %s\n' "$1"; }
bad()  { printf '  FAIL %s\n' "$1"; FAIL=$((FAIL + 1)); }
swift --version >/dev/null 2>&1 && ok "swift toolchain" || bad "swift toolchain missing"
xcrun --show-sdk-path >/dev/null 2>&1 && ok "macOS SDK" || bad "macOS SDK missing (install Xcode CLT)"
./scripts/sign-dev.sh verify >/dev/null 2>&1 && ok "Clicky-Dev identity" || bad "Clicky-Dev identity missing (run scripts/sign-dev.sh create)"
if [ -d build/Clicky.app ]; then
  codesign --verify --deep --strict build/Clicky.app >/dev/null 2>&1 \
    && ok "Clicky.app signature valid" || bad "Clicky.app signature invalid (rerun make-app.sh)"
  REQUIREMENTS="$(codesign -d --requirements - build/Clicky.app 2>/dev/null || true)"
  CERT_SHA="$(security find-identity -p codesigning 2>/dev/null | awk '/Clicky-Dev/{print $2; exit}' | tr '[:upper:]' '[:lower:]')"
  if [ -n "$CERT_SHA" ]; then
    printf '%s' "$REQUIREMENTS" | tr '[:upper:]' '[:lower:]' | grep -q "certificate leaf = h\"$CERT_SHA\"" \
      && ok "designated requirement pins the current Clicky-Dev leaf (TCC persists)" \
      || bad "requirement does not match the current Clicky-Dev leaf (rerun make-app.sh)"
  else
    warn "Clicky-Dev identity not found; skipped requirement/leaf cross-check"
  fi
  ENTITLEMENTS="$(codesign -d --entitlements - build/Clicky.app 2>/dev/null || true)"
  { printf '%s' "$ENTITLEMENTS" | grep -q 'com.apple.security.device.audio-input' \
    && printf '%s' "$ENTITLEMENTS" | grep -q 'com.apple.security.automation.apple-events'; } \
    && ok "entitlements present (audio-input + apple-events)" \
    || bad "hardened-runtime entitlements missing (rerun make-app.sh; mic and Apple Events would fail)"
else
  warn "build/Clicky.app not built yet"
fi
[ -n "${GEMINI_API_KEY:-}" ] && ok "GEMINI_API_KEY set" || warn "GEMINI_API_KEY not set (fine for unit work)"
git grep -I -l -E 'AIza[0-9A-Za-z_-]{35}' 2>/dev/null | grep -q . && bad "possible API key material committed" || ok "no Google API key material in tracked files"
# Probe models endpoint (403 without a key = reachable host; 404 accepted if endpoint changes)
CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 https://generativelanguage.googleapis.com/v1beta/models || echo 000)"
case "$CODE" in
  200|400|401|403|404) ok "Live API host reachable (HTTP $CODE)";;
  *) bad "Live API host unreachable (HTTP $CODE) — check network/hotspot";;
esac
system_profiler SPAudioDataType 2>/dev/null | grep -q Input && ok "audio input device" || bad "no audio input device"
echo
[ "$FAIL" -gt 0 ] && { echo "doctor: $FAIL hard failure(s) — fix before demo."; exit 1; }
echo "doctor: all hard checks passed (TCC: launch the app and run the wizard)."
