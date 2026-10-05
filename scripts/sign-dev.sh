#!/usr/bin/env bash
# Persistent self-signed "Clicky-Dev" code-signing identity manager.
# TCC (Accessibility / Screen Recording / Microphone) evaluates the designated
# requirement, not the cdhash — a stable identity keeps grants across rebuilds.
# NEVER regenerate the certificate: its leaf is inside the designated requirement.
# Entitlements must remain unchanged between builds (errata B15).
# Usage: ./scripts/sign-dev.sh [verify|create]
set -euo pipefail
IDENTITY="Clicky-Dev"
MODE="${1:-verify}"
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "ok: identity '$IDENTITY' exists"
  [ "$MODE" = "create" ] && { echo "REFUSING to recreate an existing identity — that destroys every TCC grant."; exit 1; }
  exit 0
fi
if [ "$MODE" != "create" ]; then
  cat <<'GUIDE'
Missing identity "Clicky-Dev". Create it ONCE, either way:
  A) Keychain Access → Certificate Assistant → Create a Certificate…
       Name: Clicky-Dev   ·   Identity Type: Self Signed Root   ·   Certificate Type: Code Signing
  B) ./scripts/sign-dev.sh create      (openssl + security import recipe)
Then never regenerate it — that would invalidate every TCC grant.
GUIDE
  exit 1
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/cert.cnf" <<'EOF'
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = Clicky-Dev
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf"
if openssl version | grep -q "^OpenSSL 3\."; then
  openssl pkcs12 -export -legacy -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$IDENTITY" -out "$WORK/id.p12" -passout pass:clickydev
else
  openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$IDENTITY" -out "$WORK/id.p12" -passout pass:clickydev
fi
KC="$HOME/Library/Keychains/login.keychain-db"
security import "$WORK/id.p12" -k "$KC" -P clickydev -T /usr/bin/codesign -T /usr/bin/security
echo "identity imported"
echo "If codesign reports a key-partition error, run:"
echo "  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k <login-password> $KC"
security find-identity -p codesigning | grep "$IDENTITY" || true
