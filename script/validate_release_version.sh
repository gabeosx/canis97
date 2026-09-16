#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_CONFIG="$ROOT_DIR/Config/Version.xcconfig"
EXPECTED_TAG="${1:-}"
RUBY_BIN="${RUBY_BIN:-/usr/bin/ruby}"

read_setting() {
  local key="$1"
  awk -F= -v key="$key" '
    $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
      value = $2
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "$VERSION_CONFIG"
}

VERSION="$(read_setting MARKETING_VERSION)"
BUILD_NUMBER="$(read_setting CURRENT_PROJECT_VERSION)"

if [[ ! "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "MARKETING_VERSION must be stable MAJOR.MINOR.PATCH; found '$VERSION'" >&2
  exit 1
fi

if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "CURRENT_PROJECT_VERSION must be a positive integer; found '$BUILD_NUMBER'" >&2
  exit 1
fi

# Catch stale release-candidate branches before they can validate an already
# superseded marketing version. Equal is valid for the currently published
# release; a lower version than any stable tag in the repository is not.
LATEST_RELEASE_VERSION="$({
  git -C "$ROOT_DIR" tag --list 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null || true
} | "$RUBY_BIN" -e '
  versions = STDIN.each_line.each_with_object([]) do |line, result|
    match = line.strip.match(/\Av(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\z/)
    result << match.captures.map(&:to_i) if match
  end
  puts versions.max.join(".") unless versions.empty?
')"

if [[ -n "$LATEST_RELEASE_VERSION" ]]; then
  configured_is_older="$($RUBY_BIN -e '
    configured = ARGV.fetch(0).split(".").map(&:to_i)
    latest = ARGV.fetch(1).split(".").map(&:to_i)
    print((configured <=> latest) == -1 ? "yes" : "no")
  ' "$VERSION" "$LATEST_RELEASE_VERSION")"
  if [[ "$configured_is_older" == "yes" ]]; then
    echo "MARKETING_VERSION '$VERSION' is older than existing release tag 'v$LATEST_RELEASE_VERSION'" >&2
    exit 1
  fi
fi

if [[ -n "$EXPECTED_TAG" && "$EXPECTED_TAG" != "v$VERSION" ]]; then
  echo "tag '$EXPECTED_TAG' does not match MARKETING_VERSION '$VERSION'" >&2
  exit 1
fi

if [[ -n "$EXPECTED_TAG" ]]; then
  VERSION_PATTERN="${VERSION//./\\.}"
  if ! grep -Eq "^## \\[$VERSION_PATTERN\\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$ROOT_DIR/CHANGELOG.md"; then
    echo "CHANGELOG.md must contain a dated [$VERSION] release heading" >&2
    exit 1
  fi
fi

if ! /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/SiriusMac/Info.plist" \
  | grep -Fxq '$(MARKETING_VERSION)'; then
  echo "Info.plist must source CFBundleShortVersionString from MARKETING_VERSION" >&2
  exit 1
fi

if ! /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT_DIR/SiriusMac/Info.plist" \
  | grep -Fxq '$(CURRENT_PROJECT_VERSION)'; then
  echo "Info.plist must source CFBundleVersion from CURRENT_PROJECT_VERSION" >&2
  exit 1
fi

printf '%s\n' "$VERSION"
