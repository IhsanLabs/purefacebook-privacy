#!/usr/bin/env bash
#
# generate-keystore.sh
#
# Creates a PKCS#12 signing key for the release APK, without Android Studio.
# Needs only `openssl` (no JDK, no keytool).
#
#   ./scripts/generate-keystore.sh [output-dir]
#
# Then add these 4 repo secrets (Settings -> Secrets and variables -> Actions):
#   KEYSTORE_BASE64      base64 -w0 release.p12
#   KEYSTORE_PASSWORD    contents of keystore-password.txt
#   KEY_ALIAS            contents of key-alias.txt
#   KEY_PASSWORD         same as KEYSTORE_PASSWORD
#
set -euo pipefail

OUT_DIR="${1:-./signing}"
ALIAS="purefacebook"
DAYS=10000

mkdir -p "$OUT_DIR"
umask 077

if [ -f "$OUT_DIR/release.p12" ]; then
  echo "refusing to overwrite $OUT_DIR/release.p12" >&2
  exit 1
fi

PASS=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)

openssl req -x509 -newkey rsa:4096 -nodes \
  -keyout "$OUT_DIR/key.pem" \
  -out "$OUT_DIR/cert.pem" \
  -days "$DAYS" \
  -subj "/CN=PureFacebook/O=Ihsan Labs/C=BD" 2>/dev/null

openssl pkcs12 -export \
  -in "$OUT_DIR/cert.pem" \
  -inkey "$OUT_DIR/key.pem" \
  -name "$ALIAS" \
  -out "$OUT_DIR/release.p12" \
  -passout "pass:$PASS"

printf '%s' "$PASS"  > "$OUT_DIR/keystore-password.txt"
printf '%s' "$ALIAS" > "$OUT_DIR/key-alias.txt"
base64 -w0 "$OUT_DIR/release.p12" > "$OUT_DIR/keystore-base64.txt"

cat <<EOF

Keystore created in $OUT_DIR

  release.p12            <- the key itself. BACK THIS UP. Lose it = users cannot update.
  keystore-base64.txt    <- paste into secret KEYSTORE_BASE64
  keystore-password.txt  <- paste into secret KEYSTORE_PASSWORD and KEY_PASSWORD
  key-alias.txt          <- paste into secret KEY_ALIAS

Validity: $DAYS days. Alias: $ALIAS
EOF
