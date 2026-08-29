#!/usr/bin/env python3
"""Validate a Canis97 skin source directory or .canis97skin archive.

This uses Python's standard library and macOS's built-in sips/ImageIO decoder,
so the installed skill needs no Canis97 checkout or third-party packages.
"""

from __future__ import annotations

import argparse
import binascii
import json
import re
import stat
import struct
import subprocess
import sys
import tempfile
import unicodedata
import zipfile
import zlib
from pathlib import Path, PurePosixPath
from typing import Any


ARCHIVE_BYTES = 16 * 1024 * 1024
EXPANDED_BYTES = 64 * 1024 * 1024
ENTRY_COUNT = 128
FILE_BYTES = 8 * 1024 * 1024
MANIFEST_BYTES = 64 * 1024
COMPRESSION_RATIO = 100
IMAGE_DIMENSION = 4_096
IMAGE_PIXELS = 16_777_216
PATH_COMPONENTS = 4
PATH_UTF8_BYTES = 240

COLOR_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")
IDENTIFIER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
DRIVE_RE = re.compile(r"^[A-Za-z]:")
SEMANTICS = {
    "artwork",
    "channelIdentity",
    "metadata",
    "favorite",
    "status",
    "transport",
    "library",
    "overflowMenu",
}
TYPOGRAPHY_TOKENS = {"systemDefault", "systemRounded", "systemMonospaced"}
LAYOUTS = {
    "legacyStack": ("nativeRect", "legacy400x288", 400, 288),
    "desktopUtility": ("pixelNotched", "desktop432x304", 432, 304),
    "discConsole": ("discPod", "console384x320", 384, 320),
    "aquaPod": ("bubbleCapsule", "capsule448x304", 448, 304),
}

V1_REQUIRED = {
    "schemaVersion",
    "identifier",
    "displayName",
    "playerBackground",
    "metadataPanel",
    "accent",
    "destructive",
    "foregroundScheme",
    "contentPadding",
    "sectionSpacing",
    "cornerRadius",
}
V1_OPTIONAL = {"backgroundAsset", "metadataPanelAsset"}
V2_REQUIRED = V1_REQUIRED | {"chromeHighlight", "displayGlow"}
V3_KEYS = {
    "schemaVersion",
    "identifier",
    "displayName",
    "playerBackground",
    "metadataPanel",
    "accent",
    "destructive",
    "foregroundScheme",
    "layoutVariant",
    "silhouette",
    "size",
    "typography",
    "slots",
    "dragRegions",
    "decorations",
}


class SkinValidationError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SkinValidationError(message)


def is_int(value: Any) -> bool:
    return type(value) is int


def exact_keys(value: Any, keys: set[str], label: str) -> dict[str, Any]:
    require(isinstance(value, dict), f"{label} must be an object")
    require(set(value) == keys, f"{label} has unknown or missing keys")
    return value


def canonical_path(raw: Any, label: str) -> str:
    require(isinstance(raw, str) and raw, f"{label} must be a nonempty string")
    require("\0" not in raw and "\\" not in raw, f"{label} contains an unsafe character")
    require(not raw.startswith("/") and not DRIVE_RE.match(raw), f"{label} must be relative")
    require("://" not in raw, f"{label} cannot be a URL")
    parts = raw.split("/")
    require(0 < len(parts) <= PATH_COMPONENTS, f"{label} has too many path components")
    require(all(part not in {"", ".", ".."} for part in parts), f"{label} is not canonical")
    require(all(not part.startswith(".") for part in parts), f"{label} cannot be hidden")
    normalized = "/".join(unicodedata.normalize("NFC", part) for part in parts)
    require(normalized == raw, f"{label} must use precomposed Unicode")
    require(len(normalized.encode("utf-8")) <= PATH_UTF8_BYTES, f"{label} is too long")
    return normalized


def validate_common(manifest: dict[str, Any], colors: list[str]) -> None:
    identifier = manifest.get("identifier")
    require(isinstance(identifier, str), "identifier must be a string")
    require(len(identifier.encode("utf-8")) <= 64 and IDENTIFIER_RE.fullmatch(identifier) is not None,
            "identifier must be stable ASCII and at most 64 bytes")
    display_name = manifest.get("displayName")
    require(isinstance(display_name, str) and 1 <= len(display_name) <= 64,
            "displayName must contain 1-64 characters")
    require(display_name.strip() == display_name, "displayName cannot have surrounding whitespace")
    require(all(isinstance(manifest.get(key), str) and COLOR_RE.fullmatch(manifest[key]) for key in colors),
            "colors must use #RRGGBB")
    require(manifest.get("foregroundScheme") in {"light", "dark"},
            "foregroundScheme must be light or dark")


def validate_asset_paths(paths: list[str]) -> set[str]:
    canonical = [canonical_path(path, "asset path") for path in paths]
    require(len({path.casefold() for path in canonical}) == len(canonical),
            "asset paths must be unique without case collisions")
    return set(canonical)


def validate_legacy(manifest: dict[str, Any], version: int) -> set[str]:
    required = V2_REQUIRED if version == 2 else V1_REQUIRED
    keys = set(manifest)
    require(required <= keys <= (required | V1_OPTIONAL),
            f"schema {version} has unknown or missing keys")
    require(manifest.get("schemaVersion") == version, f"schemaVersion must be {version}")
    colors = ["playerBackground", "metadataPanel", "accent", "destructive"]
    if version == 2:
        colors += ["chromeHighlight", "displayGlow"]
    validate_common(manifest, colors)
    for key, low, high in (
        ("contentPadding", 12, 20),
        ("sectionSpacing", 4, 12),
        ("cornerRadius", 0, 12),
    ):
        value = manifest.get(key)
        require(is_int(value) and low <= value <= high, f"{key} must be {low}-{high}")
    assets: list[str] = []
    for key in sorted(V1_OPTIONAL):
        value = manifest.get(key)
        require(value is None or isinstance(value, str), f"{key} must be null or a path")
        if value is not None:
            assets.append(value)
    return validate_asset_paths(assets)


def validate_rect(value: Any, label: str, canvas: tuple[int, int], focus: bool) -> dict[str, int]:
    rect = exact_keys(value, {"x", "y", "width", "height"}, label)
    values = [rect[key] for key in ("x", "y", "width", "height")]
    require(all(is_int(item) and item >= 0 and item % 4 == 0 for item in values),
            f"{label} must use nonnegative four-point-grid values")
    x, y, width, height = values
    require(width > 0 and height > 0, f"{label} must have positive size")
    require(x + width <= canvas[0] and y + height <= canvas[1], f"{label} exceeds the canvas")
    if focus:
        require(x >= 4 and y >= 4 and x + width <= canvas[0] - 4 and y + height <= canvas[1] - 4,
                f"{label} violates four-point focus clearance")
    return rect


def overlaps(a: dict[str, int], b: dict[str, int]) -> bool:
    return (
        a["x"] < b["x"] + b["width"]
        and b["x"] < a["x"] + a["width"]
        and a["y"] < b["y"] + b["height"]
        and b["y"] < a["y"] + a["height"]
    )


def validate_v3(manifest: dict[str, Any]) -> set[str]:
    exact_keys(manifest, V3_KEYS, "schema 3 manifest")
    require(manifest.get("schemaVersion") == 3, "schemaVersion must be 3")
    validate_common(manifest, ["playerBackground", "metadataPanel", "accent", "destructive"])

    variant = manifest.get("layoutVariant")
    require(variant in LAYOUTS, "unsupported layoutVariant")
    silhouette, size_name, width, height = LAYOUTS[variant]
    require(manifest.get("silhouette") == silhouette and manifest.get("size") == size_name,
            "layoutVariant, silhouette, and size must use a supported tuple")
    canvas = (width, height)

    typography = exact_keys(manifest.get("typography"), {"display", "body", "label"}, "typography")
    require(all(value in TYPOGRAPHY_TOKENS for value in typography.values()),
            "unsupported typography token")

    slots = manifest.get("slots")
    require(isinstance(slots, list) and len(slots) == len(SEMANTICS),
            "slots must define all eight semantic regions exactly once")
    frames: dict[str, dict[str, int]] = {}
    for index, raw_slot in enumerate(slots):
        slot = exact_keys(raw_slot, {"semantic", "frame"}, f"slots[{index}]")
        semantic = slot.get("semantic")
        require(semantic in SEMANTICS and semantic not in frames, "slot semantics must be unique and supported")
        frames[semantic] = validate_rect(slot.get("frame"), f"{semantic} frame", canvas, focus=True)
    require(set(frames) == SEMANTICS, "slots must define every semantic region")

    frame_items = list(frames.items())
    for index, (name, frame) in enumerate(frame_items):
        for other_name, other_frame in frame_items[index + 1 :]:
            require(not overlaps(frame, other_frame), f"{name} overlaps {other_name}")

    for semantic in ("favorite", "transport", "library", "overflowMenu"):
        require(frames[semantic]["width"] >= 32 and frames[semantic]["height"] >= 32,
                f"{semantic} must be at least 32x32")
    for semantic, minimum in (
        ("channelIdentity", (96, 20)),
        ("metadata", (128, 40)),
        ("status", (80, 20)),
    ):
        require(frames[semantic]["width"] >= minimum[0] and frames[semantic]["height"] >= minimum[1],
                f"{semantic} is too small")

    drag_regions = manifest.get("dragRegions")
    require(isinstance(drag_regions, list) and drag_regions, "at least one drag region is required")
    for index, raw_drag in enumerate(drag_regions):
        drag = validate_rect(raw_drag, f"dragRegions[{index}]", canvas, focus=False)
        require(drag["width"] >= 80 and drag["height"] >= 20,
                "drag regions must be at least 80x20")
        require(all(not overlaps(drag, frame) for frame in frames.values()),
                "drag regions cannot overlap semantic slots")

    decorations = exact_keys(
        manifest.get("decorations"),
        {"backdrop", "chromeFrame", "displayPlate", "ornaments"},
        "decorations",
    )
    require(isinstance(decorations.get("ornaments"), list) and len(decorations["ornaments"]) <= 3,
            "decorations may contain at most three ornaments")
    assets: list[str] = []
    for key in ("backdrop", "chromeFrame", "displayPlate"):
        value = decorations.get(key)
        require(value is None or isinstance(value, str), f"decorations.{key} must be null or a path")
        if value is not None:
            assets.append(value)
    require(all(isinstance(path, str) for path in decorations["ornaments"]),
            "ornament paths must be strings")
    assets += decorations["ornaments"]
    require(len(assets) <= 6, "schema 3 may reference at most six decoration assets")
    return validate_asset_paths(assets)


def validate_manifest(data: bytes) -> tuple[dict[str, Any], set[str]]:
    require(len(data) <= MANIFEST_BYTES, "manifest.json exceeds 64 KiB")
    try:
        manifest = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise SkinValidationError(f"manifest.json is not valid UTF-8 JSON: {error}") from error
    require(isinstance(manifest, dict), "manifest.json must contain an object")
    version = manifest.get("schemaVersion")
    require(is_int(version), "schemaVersion must be an integer")
    if version in {1, 2}:
        assets = validate_legacy(manifest, version)
    elif version == 3:
        assets = validate_v3(manifest)
    else:
        raise SkinValidationError("only schema versions 1-3 are supported")
    return manifest, assets


def validate_dimensions(width: int, height: int, label: str) -> None:
    require(0 < width <= IMAGE_DIMENSION and 0 < height <= IMAGE_DIMENSION,
            f"{label} dimensions exceed 4096 pixels")
    require(width * height <= IMAGE_PIXELS, f"{label} exceeds the pixel limit")


def png_dimensions(data: bytes, label: str) -> tuple[int, int]:
    require(data.startswith(b"\x89PNG\r\n\x1a\n"), f"{label} is not a PNG")
    offset = 8
    chunks: list[tuple[bytes, bytes]] = []
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        end = offset + 12 + length
        require(end <= len(data), f"{label} has a truncated PNG chunk")
        payload = data[offset + 8 : offset + 8 + length]
        expected_crc = struct.unpack(">I", data[offset + 8 + length : end])[0]
        actual_crc = binascii.crc32(chunk_type + payload) & 0xFFFFFFFF
        require(actual_crc == expected_crc, f"{label} has an invalid PNG checksum")
        chunks.append((chunk_type, payload))
        offset = end
        if chunk_type == b"IEND":
            break
    require(chunks and chunks[0][0] == b"IHDR" and len(chunks[0][1]) == 13,
            f"{label} has no valid IHDR")
    require(sum(1 for kind, _ in chunks if kind == b"IHDR") == 1, f"{label} has multiple IHDR chunks")
    require(chunks[-1][0] == b"IEND" and offset == len(data), f"{label} has an invalid PNG ending")
    require(all(kind != b"acTL" for kind, _ in chunks), f"{label} must be a single-frame PNG")
    compressed = b"".join(payload for kind, payload in chunks if kind == b"IDAT")
    require(compressed, f"{label} has no image data")
    try:
        zlib.decompress(compressed)
    except zlib.error as error:
        raise SkinValidationError(f"{label} has invalid compressed image data") from error
    width, height = struct.unpack(">II", chunks[0][1][:8])
    return width, height


def jpeg_dimensions(data: bytes, label: str) -> tuple[int, int]:
    require(data.startswith(b"\xff\xd8") and data.endswith(b"\xff\xd9"), f"{label} is not a complete JPEG")
    offset = 2
    sof_markers = set(range(0xC0, 0xD0)) - {0xC4, 0xC8, 0xCC}
    while offset < len(data) - 2:
        require(data[offset] == 0xFF, f"{label} has an invalid JPEG marker")
        while offset < len(data) and data[offset] == 0xFF:
            offset += 1
        require(offset < len(data), f"{label} has a truncated JPEG marker")
        marker = data[offset]
        offset += 1
        if marker == 0xDA:
            break
        if marker in {0x01, 0xD8, 0xD9} or 0xD0 <= marker <= 0xD7:
            continue
        require(offset + 2 <= len(data), f"{label} has a truncated JPEG segment")
        length = struct.unpack(">H", data[offset : offset + 2])[0]
        require(length >= 2 and offset + length <= len(data), f"{label} has an invalid JPEG segment")
        if marker in sof_markers:
            require(length >= 7, f"{label} has an invalid JPEG frame")
            height, width = struct.unpack(">HH", data[offset + 3 : offset + 7])
            return width, height
        offset += length
    raise SkinValidationError(f"{label} has no supported JPEG frame")


def validate_image(data: bytes, path: str) -> None:
    require(0 < len(data) <= FILE_BYTES, f"{path} exceeds 8 MiB or is empty")
    suffix = PurePosixPath(path).suffix
    if suffix == ".png":
        width, height = png_dimensions(data, path)
    elif suffix in {".jpg", ".jpeg"}:
        width, height = jpeg_dimensions(data, path)
    else:
        raise SkinValidationError(f"{path} must use a lowercase .png, .jpg, or .jpeg extension")
    validate_dimensions(width, height, path)
    validate_imageio_decode(data, suffix, path)


def validate_imageio_decode(data: bytes, suffix: str, label: str) -> None:
    """Require the same macOS image stack used by Canis97 to decode the asset."""
    sips = Path("/usr/bin/sips")
    require(sips.is_file(), "macOS sips is required for importer-compatible image validation")
    try:
        with tempfile.TemporaryDirectory(prefix="canis97-skin-validator-") as directory:
            source = Path(directory) / f"asset{suffix}"
            decoded = Path(directory) / "decoded.png"
            source.write_bytes(data)
            result = subprocess.run(
                [str(sips), "-s", "format", "png", str(source), "--out", str(decoded)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=10,
                check=False,
            )
            require(
                result.returncode == 0 and decoded.is_file() and decoded.stat().st_size > 0,
                f"{label} cannot be decoded by macOS ImageIO",
            )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise SkinValidationError(f"{label} could not complete macOS ImageIO validation") from error


def validate_payload(files: dict[str, bytes]) -> tuple[dict[str, Any], set[str]]:
    require("manifest.json" in files, "manifest.json must be at the package root")
    manifest, assets = validate_manifest(files["manifest.json"])
    expected = assets | {"manifest.json"}
    require(set(files) == expected, "package contains missing, unreferenced, or extra files")
    for asset in sorted(assets):
        validate_image(files[asset], asset)
    return manifest, assets


def validate_source(root: Path) -> tuple[dict[str, Any], set[str]]:
    require(root.is_dir(), f"source directory does not exist: {root}")
    files: dict[str, bytes] = {}
    comparison_paths: set[str] = set()
    for item in sorted(root.rglob("*")):
        require(not item.is_symlink(), f"symbolic links are not allowed: {item}")
        if item.is_dir():
            continue
        require(item.is_file(), f"unsupported source entry: {item}")
        relative = item.relative_to(root).as_posix()
        path = canonical_path(relative, "source path")
        require(path.casefold() not in comparison_paths, f"source path collision: {path}")
        comparison_paths.add(path.casefold())
        data = item.read_bytes()
        require(len(data) <= FILE_BYTES, f"{path} exceeds 8 MiB")
        files[path] = data
    require(len(files) <= ENTRY_COUNT, "source contains too many files")
    require(sum(len(data) for data in files.values()) <= EXPANDED_BYTES, "source exceeds 64 MiB")
    return validate_payload(files)


def validate_archive(archive: Path) -> tuple[dict[str, Any], set[str]]:
    require(archive.is_file(), f"archive does not exist: {archive}")
    require(archive.suffix == ".canis97skin", "archive must end in .canis97skin")
    require(archive.stat().st_size <= ARCHIVE_BYTES, "archive exceeds 16 MiB")
    files: dict[str, bytes] = {}
    exact_paths: set[str] = set()
    comparison_paths: set[str] = set()
    total_compressed = 0
    total_expanded = 0
    try:
        with zipfile.ZipFile(archive) as package:
            infos = package.infolist()
            require(len(infos) <= ENTRY_COUNT, "archive contains too many entries")
            for info in infos:
                require(not info.is_dir(), "archive must contain files only")
                mode = info.external_attr >> 16
                require(not (info.create_system == 3 and stat.S_ISLNK(mode)), "symbolic links are not allowed")
                require(info.flag_bits & 0x1 == 0, "encrypted entries are not allowed")
                path = canonical_path(info.filename, "archive path")
                require(path == info.filename, "archive paths must already be canonical")
                require(path not in exact_paths, f"duplicate archive path: {path}")
                require(path.casefold() not in comparison_paths, f"archive path collision: {path}")
                for existing in exact_paths:
                    require(not (path.startswith(existing + "/") or existing.startswith(path + "/")),
                            "archive contains a file/path prefix conflict")
                exact_paths.add(path)
                comparison_paths.add(path.casefold())
                require(info.file_size <= FILE_BYTES, f"{path} exceeds 8 MiB")
                if info.file_size > 0:
                    require(info.compress_size > 0 and info.file_size <= info.compress_size * COMPRESSION_RATIO,
                            f"{path} exceeds the compression-ratio limit")
                total_compressed += info.compress_size
                total_expanded += info.file_size
                require(total_expanded <= EXPANDED_BYTES, "archive expands beyond 64 MiB")
            if total_expanded > 0:
                require(total_compressed > 0 and total_expanded <= total_compressed * COMPRESSION_RATIO,
                        "archive exceeds the aggregate compression-ratio limit")
            bad_file = package.testzip()
            require(bad_file is None, f"archive has a corrupt entry: {bad_file}")
            for info in infos:
                files[info.filename] = package.read(info)
    except (OSError, zipfile.BadZipFile, RuntimeError) as error:
        raise SkinValidationError(f"cannot read archive: {error}") from error
    return validate_payload(files)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="skin source directory or .canis97skin archive")
    args = parser.parse_args()
    try:
        if args.input.is_dir():
            manifest, assets = validate_source(args.input)
            kind = "source"
        else:
            manifest, assets = validate_archive(args.input)
            kind = "archive"
    except (OSError, SkinValidationError) as error:
        print(f"validation failed: {error}", file=sys.stderr)
        return 1
    print(
        f"validated {kind}: schema={manifest['schemaVersion']} "
        f"identifier={manifest['identifier']} assets={len(assets)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
