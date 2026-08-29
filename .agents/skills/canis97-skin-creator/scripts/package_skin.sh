#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 <source-directory> [output.canis97skin]" >&2
  exit 2
fi

SOURCE_DIR="$(cd "$1" 2>/dev/null && pwd)" || {
  echo "source directory does not exist: $1" >&2
  exit 1
}
DEFAULT_NAME="$(basename "$SOURCE_DIR").canis97skin"
OUTPUT_PATH="${2:-$PWD/$DEFAULT_NAME}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/validate_skin.py"
if [[ "$OUTPUT_PATH" != /* ]]; then
  OUTPUT_PATH="$PWD/$OUTPUT_PATH"
fi

[[ "$OUTPUT_PATH" == *.canis97skin ]] || {
  echo "output must end in .canis97skin" >&2
  exit 1
}
[[ -f "$SOURCE_DIR/manifest.json" ]] || {
  echo "manifest.json must be at the source-directory root" >&2
  exit 1
}
[[ ! -e "$OUTPUT_PATH" ]] || {
  echo "refusing to overwrite existing package: $OUTPUT_PATH" >&2
  exit 1
}
[[ -x "$VALIDATOR" ]] || {
  echo "skin validator is missing or not executable: $VALIDATOR" >&2
  exit 1
}
python3 "$VALIDATOR" "$SOURCE_DIR" >&2
mkdir -p "$(dirname "$OUTPUT_PATH")"

pushd "$SOURCE_DIR" >/dev/null
FILES=()
while IFS= read -r -d '' FILE; do
  FILES+=("${FILE#./}")
done < <(find . -type f -print0 | sort -z)
[[ ${#FILES[@]} -gt 0 ]] || {
  echo "source directory contains no files" >&2
  exit 1
}
/usr/bin/zip -X -q "$OUTPUT_PATH" "${FILES[@]}"
popd >/dev/null

ARCHIVE_BYTES="$(stat -f '%z' "$OUTPUT_PATH")"
if (( ARCHIVE_BYTES > 16 * 1024 * 1024 )); then
  rm -f "$OUTPUT_PATH"
  echo "package exceeds the 16 MiB archive limit" >&2
  exit 1
fi

if ! python3 "$VALIDATOR" "$OUTPUT_PATH" >&2; then
  rm -f "$OUTPUT_PATH"
  exit 1
fi

echo "$OUTPUT_PATH"
