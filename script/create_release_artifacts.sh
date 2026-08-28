#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"
OUTPUT_DIR="${RELEASE_OUTPUT_DIR:-$ROOT_DIR/build/release}"
WORK_DIR="${RELEASE_WORK_DIR:-$ROOT_DIR/build/release-work}"
ARCHIVE_PATH="$WORK_DIR/Canis97.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/Canis97.app"
NOTARY_ARCHIVE="$WORK_DIR/Canis97-notary.zip"
FINAL_ARCHIVE="$OUTPUT_DIR/Canis97-$VERSION-arm64.zip"

if [[ ! "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "usage: $0 MAJOR.MINOR.PATCH" >&2
  exit 2
fi
if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "BUILD_NUMBER must be a positive integer" >&2
  exit 2
fi
if [[ ! "$GITHUB_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "GITHUB_REPOSITORY must be OWNER/REPOSITORY" >&2
  exit 2
fi
for required_name in APPLE_TEAM_ID APPLE_ID APPLE_APP_SPECIFIC_PASSWORD; do
  if [[ -z "${!required_name:-}" ]]; then
    echo "$required_name is required" >&2
    exit 2
  fi
done

mkdir -p "$OUTPUT_DIR" "$WORK_DIR"

xcodebuild archive \
  -project "$ROOT_DIR/SiriusMac.xcodeproj" \
  -scheme Canis97 \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$WORK_DIR/DerivedData" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CANIS97_GITHUB_REPOSITORY="$GITHUB_REPOSITORY" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  'CODE_SIGN_IDENTITY=Developer ID Application' \
  'OTHER_CODE_SIGN_FLAGS=--timestamp' \
  ENABLE_HARDENED_RUNTIME=YES

if [[ ! -d "$APP_PATH" ]]; then
  echo "archive did not contain Canis97.app" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -d --verbose=4 "$APP_PATH" 2>&1 | grep -F 'Runtime Version='
codesign -d --verbose=4 "$APP_PATH" 2>&1 | grep -F 'Timestamp='

/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ARCHIVE"
xcrun notarytool submit "$NOTARY_ARCHIVE" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --wait

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH"

/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$FINAL_ARCHIVE"
(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$(basename "$FINAL_ARCHIVE")" > SHA256SUMS
)

RELEASE_ARCHIVE_PATH="$FINAL_ARCHIVE" \
  "$ROOT_DIR/script/generate_release_sbom.sh" "$VERSION" "$OUTPUT_DIR/Canis97-$VERSION.spdx"

printf 'release artifacts: %s\n' "$OUTPUT_DIR"
