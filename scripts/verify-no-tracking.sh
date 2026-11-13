#!/usr/bin/env bash
#
# verify-no-tracking.sh <path-to-apk>
#
# Fails (exit 1) if the APK still contains any Google/Firebase tracking
# surface. This is the gate that stops a bad build from being published.
#
set -euo pipefail

APK="${1:-}"
if [ -z "$APK" ] || [ ! -f "$APK" ]; then
  echo "usage: $0 <apk>" >&2
  exit 2
fi

fail=0
note() { printf '  %-52s %s\n' "$1" "$2"; }
ok()   { note "$1" "OK"; }
bad()  { note "$1" "FAIL"; fail=1; }

BT=$(ls -d "${ANDROID_HOME:-/usr/local/lib/android/sdk}"/build-tools/* 2>/dev/null | sort -V | tail -n1 || true)
AAPT2="$BT/aapt2"
APKSIGNER="$BT/apksigner"
[ -x "$AAPT2" ]    || { echo "aapt2 not found in $BT" >&2; exit 2; }
[ -x "$APKSIGNER" ] || { echo "apksigner not found in $BT" >&2; exit 2; }

echo
echo "Verifying $(basename "$APK")"
echo "--------------------------------------------------------------"

# 1. package identity --------------------------------------------------------
badging=$("$AAPT2" dump badging "$APK" 2>/dev/null || true)
pkg=$(printf '%s\n' "$badging" | sed -n "s/^package: name='\([^']*\)'.*/\1/p")
vcode=$(printf '%s\n' "$badging" | sed -n "s/^package: .*versionCode='\([^']*\)'.*/\1/p")
vname=$(printf '%s\n' "$badging" | sed -n "s/^package: .*versionName='\([^']*\)'.*/\1/p")
note "package" "${pkg:-?}"
note "version" "${vname:-?} (${vcode:-?})"

# 2. permissions -------------------------------------------------------------
perms=$("$AAPT2" dump permissions "$APK" 2>/dev/null || true)
if printf '%s\n' "$perms" | grep -q 'com.google.android.gms.permission.AD_ID'; then
  bad "permission com.google.android.gms.permission.AD_ID"
else
  ok  "permission com.google.android.gms.permission.AD_ID absent"
fi

# 3. no google-services config ----------------------------------------------
if unzip -l "$APK" 2>/dev/null | grep -qi 'google-services.json'; then
  bad "google-services.json bundled"
else
  ok  "no google-services.json"
fi

# 4. dex contents ------------------------------------------------------------
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unzip -qq -o "$APK" 'classes*.dex' -d "$tmp" 2>/dev/null || true
if ! ls "$tmp"/classes*.dex >/dev/null 2>&1; then
  echo "  could not extract dex - aborting" >&2
  exit 2
fi
strings "$tmp"/classes*.dex > "$tmp/strings.txt" 2>/dev/null || true

check_marker() {
  local label="$1" pattern="$2"
  if grep -qF -- "$pattern" "$tmp/strings.txt"; then
    bad "$label"
  else
    ok  "$label absent"
  fi
}

check_marker "Firebase Analytics classes"   "com/google/firebase/analytics"
check_marker "Firebase Installations"       "com/google/firebase/installations"
check_marker "Firebase core"                "com/google/firebase/FirebaseApp"
check_marker "Google Analytics collector"   "app-measurement.com"
check_marker "Google Ads services"          "googleadservices.com"

# 5. signature ---------------------------------------------------------------
if "$APKSIGNER" verify "$APK" >/dev/null 2>&1; then
  ok "APK signature valid"
  "$APKSIGNER" verify --print-certs "$APK" 2>/dev/null \
    | sed -n 's/^Signer #1 certificate DN: /  signer DN: /p'
else
  bad "APK signature invalid"
fi

echo "--------------------------------------------------------------"
if [ "$fail" -ne 0 ]; then
  echo "RESULT: FAILED - tracking surface still present, not publishing."
  exit 1
fi
echo "RESULT: PASSED - no Firebase/Google tracking found."
