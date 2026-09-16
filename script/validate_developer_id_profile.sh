#!/usr/bin/env bash
set -euo pipefail

PROFILE_PATH="${1:-}"
EXPECTED_TEAM_ID="${2:-}"
EXPECTED_BUNDLE_ID="${3:-}"
EXPECTED_APP_GROUP="${4:-}"
EXPECTED_CERTIFICATE_SHA1="${5:-}"

if [[ -z "$PROFILE_PATH" || -z "$EXPECTED_TEAM_ID" || -z "$EXPECTED_BUNDLE_ID" || -z "$EXPECTED_APP_GROUP" ]]; then
  echo "usage: $0 PROFILE_PATH TEAM_ID BUNDLE_ID APP_GROUP [CERTIFICATE_SHA1]" >&2
  exit 2
fi

[[ -f "$PROFILE_PATH" ]] || { echo "provisioning profile does not exist: $PROFILE_PATH" >&2; exit 1; }

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/canis97-profile-validation.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT
PAYLOAD_PATH="$TEMP_ROOT/profile.plist"

openssl smime -verify -inform DER -noverify \
  -in "$PROFILE_PATH" \
  -out "$PAYLOAD_PATH" \
  >/dev/null 2>&1 || {
    echo "provisioning profile is not a valid signed CMS document" >&2
    exit 1
  }

python3 - "$PAYLOAD_PATH" "$EXPECTED_TEAM_ID" "$EXPECTED_BUNDLE_ID" "$EXPECTED_APP_GROUP" "$EXPECTED_CERTIFICATE_SHA1" <<'PY'
import datetime
import hashlib
import plistlib
import sys

profile_path, expected_team, expected_bundle, expected_group, expected_certificate_sha1 = sys.argv[1:]
with open(profile_path, "rb") as profile_file:
    profile = plistlib.load(profile_file)

def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)

require("OSX" in profile.get("Platform", []), "profile platform does not include macOS")
require(profile.get("ProvisionsAllDevices") is True, "profile is not a Developer ID distribution profile")
require("ProvisionedDevices" not in profile, "profile unexpectedly restricts installation to development devices")
developer_certificates = profile.get("DeveloperCertificates", [])
require(bool(developer_certificates), "profile has no developer certificate")
if expected_certificate_sha1:
    expected_fingerprint = expected_certificate_sha1.replace(":", "").upper()
    fingerprints = {hashlib.sha1(certificate).hexdigest().upper() for certificate in developer_certificates}
    require(expected_fingerprint in fingerprints, "profile does not contain the configured Developer ID certificate")
require(expected_team in profile.get("TeamIdentifier", []), "profile team does not match APPLE_TEAM_ID")

entitlements = profile.get("Entitlements", {})
expected_application_id = f"{expected_team}.{expected_bundle}"
require(
    entitlements.get("com.apple.application-identifier") == expected_application_id,
    f"profile application identifier does not match {expected_bundle}",
)
require(
    expected_group in entitlements.get("com.apple.security.application-groups", []),
    f"profile does not authorize {expected_group}",
)
require(
    entitlements.get("com.apple.security.get-task-allow") is not True,
    "development profile cannot be used for release",
)

expiration = profile.get("ExpirationDate")
require(isinstance(expiration, datetime.datetime), "profile expiration is missing or malformed")
now = (
    datetime.datetime.now(expiration.tzinfo)
    if expiration.tzinfo
    else datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
)
require(expiration > now, "profile is expired")
PY

echo "valid Developer ID profile for $EXPECTED_BUNDLE_ID"
