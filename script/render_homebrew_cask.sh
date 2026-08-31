#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
SHA256="${2:-}"
GITHUB_REPOSITORY="${3:-}"

if [[ ! "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "usage: $0 MAJOR.MINOR.PATCH SHA256 OWNER/REPOSITORY" >&2
  exit 2
fi
if [[ ! "$SHA256" =~ ^[a-f0-9]{64}$ ]]; then
  echo "SHA256 must be 64 lowercase hexadecimal characters" >&2
  exit 2
fi
if [[ ! "$GITHUB_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "GitHub repository must be OWNER/REPOSITORY" >&2
  exit 2
fi

printf '%s\n' \
  'cask "canis97" do' \
  "  version \"$VERSION\"" \
  "  sha256 \"$SHA256\"" \
  '' \
  "  url \"https://github.com/$GITHUB_REPOSITORY/releases/download/v#{version}/Canis97-#{version}-arm64.dmg\"" \
  '  name "Canis97"' \
  '  desc "Native macOS SiriusXM player"' \
  "  homepage \"https://github.com/$GITHUB_REPOSITORY\"" \
  '' \
  '  depends_on arch: :arm64' \
  '  depends_on macos: ">= :tahoe"' \
  '' \
  '  app "Canis97.app"' \
  '' \
  '  zap trash: [' \
  '    "~/Library/Application Support/Canis97",' \
  '    "~/Library/Preferences/com.canis97.player.plist",' \
  '    "~/Library/Saved Application State/com.canis97.player.savedState",' \
  '  ]' \
  'end'
