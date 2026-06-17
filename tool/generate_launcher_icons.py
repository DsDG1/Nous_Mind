#!/usr/bin/env python3
"""Regenerate Android and iOS launcher icons from a single master logo.

Reads ``assets/icons/nous_logo.png`` and overwrites every platform-specific
launcher icon PNG in-place. Designed to be re-run any time the source logo
changes; downstream code, manifests, and ``Info.plist`` are not touched.

Usage::

    python3 tool/generate_launcher_icons.py

Requires the ``Pillow`` package (``pip install Pillow``).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets" / "icons" / "nous_logo.png"

# Android density buckets — pixel size for ``ic_launcher.png`` in each.
# See https://developer.android.com/training/multiscreen/screendensities.
ANDROID_ICONS: list[tuple[str, int]] = [
    ("mipmap-mdpi", 48),
    ("mipmap-hdpi", 72),
    ("mipmap-xhdpi", 96),
    ("mipmap-xxhdpi", 144),
    ("mipmap-xxxhdpi", 192),
]

ANDROID_RES = (
    ROOT / "android" / "app" / "src" / "main" / "res"
)
IOS_APPICON_DIR = (
    ROOT
    / "ios"
    / "Runner"
    / "Assets.xcassets"
    / "AppIcon.appiconset"
)


def load_ios_targets() -> list[tuple[str, int]]:
    """Read ``Contents.json`` and return ``(filename, pixel_size)`` pairs.

    The list is deduplicated by filename because the same PNG slot is
    sometimes referenced from both ``iphone`` and ``ipad`` entries (e.g.
    ``Icon-App-29x29@2x.png`` at 58×58 is reused across idioms).
    """
    contents_path = IOS_APPICON_DIR / "Contents.json"
    with contents_path.open("r", encoding="utf-8") as f:
        contents = json.load(f)

    seen: dict[str, int] = {}
    for entry in contents["images"]:
        filename = entry["filename"]
        if filename in seen:
            continue
        # ``size`` is "WIDTHxHEIGHT" (e.g. "20x20" or "83.5x83.5").
        # Pixel size = base * scale (scale is "Nx", e.g. "2x" or "3x").
        base = float(entry["size"].split("x")[0])
        scale = int(entry["scale"].rstrip("x"))
        seen[filename] = round(base * scale)
    return sorted(seen.items())


def render(src: Image.Image, size: int) -> Image.Image:
    """Downscale ``src`` to ``size``×``size`` with high-quality resampling."""
    return src.resize((size, size), Image.Resampling.LANCZOS)


def main() -> int:
    if not SOURCE.exists():
        print(
            f"ERROR: source logo not found: {SOURCE}",
            file=sys.stderr,
        )
        return 1

    with Image.open(SOURCE) as raw:
        # iOS App Store requires a flat (no-alpha) icon. Normalize to RGB so
        # callers don't have to worry about palette / RGBA / grayscale modes.
        logo = raw.convert("RGB")
    print(
        f"Source: {SOURCE.relative_to(ROOT)} "
        f"({logo.size[0]}x{logo.size[1]}, mode=RGB)"
    )

    written = 0

    print("\nAndroid:")
    for bucket, size in ANDROID_ICONS:
        out = ANDROID_RES / bucket / "ic_launcher.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        render(logo, size).save(out, "PNG", optimize=True)
        print(f"  {out.relative_to(ROOT)}  ({size}x{size})")
        written += 1

    print("\niOS:")
    for filename, size in load_ios_targets():
        out = IOS_APPICON_DIR / filename
        render(logo, size).save(out, "PNG", optimize=True)
        print(f"  {out.relative_to(ROOT)}  ({size}x{size})")
        written += 1

    print(f"\nDone. Wrote {written} files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
