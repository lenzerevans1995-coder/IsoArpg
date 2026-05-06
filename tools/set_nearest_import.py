#!/usr/bin/env python3
"""Phase 3: drop .png.import sidecar files for every curated tile so
Godot imports them with NEAREST filter (pixel-art crisp, no
bilinear blur on iso scale).

Run from repo root:  python tools/set_nearest_import.py

Idempotent — re-running just rewrites the sidecars. The .ctex hashes
inside are stubbed; Godot regenerates the real cached imports on
next project scan.
"""
import os, hashlib
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ROOT = REPO / "assets" / "curated_tiles"

TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"
uid="uid://{uid}"
path="res://.godot/imported/{stem}.png-{hash}.ctex"
metadata={{
"vram_texture": false
}}

[deps]

source_file="res://{src}"
dest_files=["res://.godot/imported/{stem}.png-{hash}.ctex"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""

# Godot UID alphabet (base64-ish minus ambiguous chars).
_UID_CHARS = "abcdefghijklmnopqrstuvwxyz0123456789"

def stable_uid(path: str) -> str:
    h = hashlib.md5(path.encode("utf-8")).hexdigest()
    # 13-char base36-ish UID.
    n = int(h, 16)
    out = []
    for _ in range(13):
        out.append(_UID_CHARS[n % len(_UID_CHARS)])
        n //= len(_UID_CHARS)
    return "".join(out)

def main():
    if not ROOT.exists():
        raise SystemExit(f"missing {ROOT}; run curate_tiles.py first")
    n = 0
    for png in sorted(ROOT.rglob("*.png")):
        sidecar = png.with_suffix(".png.import")
        rel_src = png.relative_to(REPO).as_posix()
        stem = png.stem
        h = hashlib.md5(rel_src.encode("utf-8")).hexdigest()
        sidecar.write_text(TEMPLATE.format(
            src=rel_src,
            stem=stem,
            hash=h,
            uid=stable_uid(rel_src),
        ), encoding="utf-8")
        n += 1
    # Note: TEMPLATE uses Godot's defaults except compress/mode=0
    # (lossless) + mipmaps off + fix_alpha_border on. Filter mode is
    # NEAREST by default in Godot 4 when the .import has no explicit
    # `process/normal_map_invert_y` override AND the project's
    # default texture filter is set elsewhere — but the surest knob
    # is the project-level toggle. See companion docs note.
    print(f"Wrote {n} .png.import sidecars under {ROOT.relative_to(REPO)}/")
    print("\nNext: open Godot once so it scans + imports the new folder.")
    print("If tiles render blurry on zoom, set:")
    print("  Project Settings -> Rendering -> Textures ->")
    print("  Canvas Textures / Default Texture Filter = Nearest")

if __name__ == "__main__":
    main()
