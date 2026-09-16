#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT_DIR/script/validate_developer_id_profile.sh"
PROJECT_FILE="$ROOT_DIR/SiriusMac.xcodeproj/project.pbxproj"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/canis97-profile-tests.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

test "$(grep -Fc 'REGISTER_APP_GROUPS = YES;' "$PROJECT_FILE")" -eq 6 || \
  fail "all app and widget build configurations must register App Groups"
python3 - "$ROOT_DIR/SiriusMac/Canis97.entitlements" "$ROOT_DIR/Canis97Widget/Canis97Widget.entitlements" <<'PY'
import plistlib
import sys

for entitlement_path in sys.argv[1:]:
    with open(entitlement_path, "rb") as entitlement_file:
        entitlements = plistlib.load(entitlement_file)
    if entitlements.get("com.apple.security.application-groups") != ["group.com.canis97.player"]:
        raise SystemExit(f"unexpected App Group entitlement: {entitlement_path}")
PY

openssl req -x509 -newkey rsa:2048 -nodes \
  -subj '/CN=Canis97 Synthetic Developer ID/' \
  -keyout "$TEMP_ROOT/key.pem" \
  -out "$TEMP_ROOT/cert.pem" \
  -days 2 >/dev/null 2>&1
openssl x509 -in "$TEMP_ROOT/cert.pem" -outform DER -out "$TEMP_ROOT/cert.der"
CERTIFICATE_SHA1="$(openssl x509 -in "$TEMP_ROOT/cert.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')"

make_profile() {
  local output_path="$1"
  local bundle_id="$2"
  local app_group="$3"
  local distribution="$4"
  local expiration_year="$5"
  local payload_path="$TEMP_ROOT/payload.plist"

  python3 - "$payload_path" "$TEMP_ROOT/cert.der" "$bundle_id" "$app_group" "$distribution" "$expiration_year" <<'PY'
import datetime
import plistlib
import sys

payload_path, certificate_path, bundle_id, app_group, distribution, expiration_year = sys.argv[1:]
with open(certificate_path, "rb") as certificate_file:
    certificate = certificate_file.read()

profile = {
    "Platform": ["OSX"],
    "TeamIdentifier": ["TEAM12345"],
    "DeveloperCertificates": [certificate],
    "ExpirationDate": datetime.datetime(int(expiration_year), 1, 1),
    "Entitlements": {
        "com.apple.application-identifier": f"TEAM12345.{bundle_id}",
        "com.apple.security.application-groups": [app_group],
    },
}
if distribution == "true":
    profile["ProvisionsAllDevices"] = True
else:
    profile["ProvisionedDevices"] = ["SYNTHETIC-DEVICE"]
    profile["Entitlements"]["com.apple.security.get-task-allow"] = True

with open(payload_path, "wb") as payload_file:
    plistlib.dump(profile, payload_file)
PY

  openssl smime -sign -binary -nodetach -outform DER \
    -in "$payload_path" \
    -signer "$TEMP_ROOT/cert.pem" \
    -inkey "$TEMP_ROOT/key.pem" \
    -out "$output_path"
}

make_profile "$TEMP_ROOT/valid.provisionprofile" com.canis97.player group.com.canis97.player true 2040
"$VALIDATOR" "$TEMP_ROOT/valid.provisionprofile" TEAM12345 \
  com.canis97.player group.com.canis97.player "$CERTIFICATE_SHA1" >/dev/null

if "$VALIDATOR" "$TEMP_ROOT/valid.provisionprofile" TEAM12345 \
  com.canis97.player.widget group.com.canis97.player "$CERTIFICATE_SHA1" >/dev/null 2>&1; then
  fail "profile accepted the wrong bundle identifier"
fi

if "$VALIDATOR" "$TEMP_ROOT/valid.provisionprofile" TEAM12345 \
  com.canis97.player group.com.canis97.other "$CERTIFICATE_SHA1" >/dev/null 2>&1; then
  fail "profile accepted an unauthorized App Group"
fi

if "$VALIDATOR" "$TEMP_ROOT/valid.provisionprofile" TEAM12345 \
  com.canis97.player group.com.canis97.player FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF >/dev/null 2>&1; then
  fail "profile accepted the wrong signing certificate"
fi

make_profile "$TEMP_ROOT/development.provisionprofile" com.canis97.player group.com.canis97.player false 2040
if "$VALIDATOR" "$TEMP_ROOT/development.provisionprofile" TEAM12345 \
  com.canis97.player group.com.canis97.player "$CERTIFICATE_SHA1" >/dev/null 2>&1; then
  fail "validator accepted a development profile"
fi

make_profile "$TEMP_ROOT/expired.provisionprofile" com.canis97.player group.com.canis97.player true 2020
if "$VALIDATOR" "$TEMP_ROOT/expired.provisionprofile" TEAM12345 \
  com.canis97.player group.com.canis97.player "$CERTIFICATE_SHA1" >/dev/null 2>&1; then
  fail "validator accepted an expired profile"
fi

echo "PASS: Developer ID provisioning profile validation"
