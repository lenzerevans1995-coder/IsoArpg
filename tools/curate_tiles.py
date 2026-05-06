#!/usr/bin/env python3
"""Phase 2: copy in-use world tiles into assets/curated_tiles/ with
descriptive names. Originals are not touched — this is a copy, not a
move, so the chunk streamer / paint editor still loads from the
original paths.

Run from repo root:  python tools/curate_tiles.py
"""
import os, re, shutil, sys
from pathlib import Path

# Re-use the audit scanner so we always work off the same source list.
sys.path.insert(0, str(Path(__file__).resolve().parent))
import audit_tiles_in_use as audit  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
DEST = REPO / "assets" / "curated_tiles"

# Mapping rules: ordered (substring -> bucket) pairs. First match wins.
# Each rule emits the curated subfolder. Direction suffix preserved as
# lowercase _e / _n / _s / _w for tiles that have one.
RULES = [
    # walls + stone (collision-bearing)
    ("Wall A1",                  "walls"),
    ("Wall A2",                  "walls"),
    ("WallFlora",                "walls"),
    ("Stone ",                   "walls"),
    # trees (silhouette obstacles even if not strictly collision)
    ("Tree ",                    "flora"),
    # ground bases
    ("ground/grass",             "ground"),
    ("ground/dirt",              "ground"),
    ("environment/Ground A1",    "ground"),
    ("environment/Ground D",     "ground"),
    # water (animated frames + bed tiles)
    ("water_ripples",            "water"),
    ("water_bed",                "water"),
    # flora & decor (non-blocking)
    ("tall_grass",               "flora"),
    ("decor/tufts",              "flora"),
    ("decor/flowers",            "flora"),
    ("environment/Flora",        "flora"),
    # decor variants in environment (A20+ are scatter rocks/flowers etc.)
    ("environment/Ground A2",    "flora"),
    # elevation (G family — ramp / hill tiles)
    ("elevation/",               "elevation"),
    ("environment/Ground G",     "elevation"),
    # edges (autotile fodder — A3 corners, A4 singles)
    ("edges/grass_corner",       "ground_edges"),
    ("edges/grass_single",       "ground_edges"),
]

DIR_RX = re.compile(r"_([NESW])\.png$", re.IGNORECASE)

def bucket_for(path: str):
    rel = path[len("res://assets/"):]
    for needle, bucket in RULES:
        if needle in path:
            return bucket
    return None  # caller decides whether to skip

def descriptive_name(path: str, bucket: str) -> str:
    """Build a clean filename based on the path semantics."""
    rel = path[len("res://assets/"):]
    fn = os.path.basename(rel)            # 'Ground A1_E.png'
    stem, ext = os.path.splitext(fn)
    name = stem.lower().replace(" ", "_")  # 'ground_a1_e'

    # Tile-family prefix from path segment 1 (after assets/forest/)
    # 'forest/elevation/dirt/Ground G3_E.png' -> 'dirt_g3_e'
    # 'forest/edges/grass_corner/Ground A3_S.png' -> 'grass_corner_a3_s'
    parent_dirs = rel.split("/")[1:-1]
    if parent_dirs and parent_dirs[-1] not in ("environment", "ground"):
        prefix = parent_dirs[-1].lower().replace(" ", "_")
        if not name.startswith(prefix):
            name = f"{prefix}_{name.split('_', 1)[-1]}" if "_" in name else f"{prefix}_{name}"

    # Animated water_ripples: parent dir is the variant id (Ripple3/0001.png)
    if "water_ripples" in rel:
        variant = parent_dirs[-1].lower()  # 'ripple3'
        frame = stem                        # '0001'
        name = f"{variant}_{frame}"

    return f"{name}{ext.lower()}"

def main():
    if not DEST.exists():
        DEST.mkdir(parents=True)

    # Pull the audit list.
    hits = set()
    audit.scan_tile_roles(hits)
    audit.scan_repo(hits)
    audit.scan_user_arena(hits)
    audit.scan_user_drafts(hits)

    summary = {}        # bucket -> [(src, dest)]
    skipped = []
    for path in sorted(hits):
        # Drop non-tile entries: player anim sheets and drop visuals.
        if "Characters/Player" in path or path.startswith("res://assets/drops/"):
            skipped.append(path)
            continue
        bucket = bucket_for(path)
        if bucket is None:
            skipped.append(path)
            continue
        src_rel = path[len("res://"):]
        src_abs = REPO / src_rel
        if not src_abs.exists():
            print(f"[miss] {src_rel}", file=sys.stderr)
            continue
        dest_dir = DEST / bucket
        dest_dir.mkdir(parents=True, exist_ok=True)
        new_name = descriptive_name(path, bucket)
        dest_abs = dest_dir / new_name
        shutil.copy2(src_abs, dest_abs)
        summary.setdefault(bucket, []).append((src_rel, str(dest_abs.relative_to(REPO))))

    # Report.
    total = sum(len(v) for v in summary.values())
    print(f"Curated {total} tiles into {DEST.relative_to(REPO)}/\n")
    for bucket in sorted(summary):
        print(f"## {bucket}/  ({len(summary[bucket])})")
        for src, dst in summary[bucket]:
            src_short = src.split("/")[-1]
            dst_short = dst.split("/")[-1]
            print(f"  {src_short:40s}  ->  {dst_short}")
        print()
    if skipped:
        print(f"# Skipped ({len(skipped)}) — not world tiles:")
        for p in skipped:
            print(f"  - {p}")

if __name__ == "__main__":
    main()
