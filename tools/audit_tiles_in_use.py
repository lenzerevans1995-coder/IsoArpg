#!/usr/bin/env python3
"""Read-only tile audit. Walks the project + user-data drafts and prints
every PNG path the running game actively references for world tiles.

Sources scanned:
  1. data/tile_roles.json                — pre-tagged tiles
  2. All .gd / .json / .tscn under repo  — hardcoded paths
  3. User-data arena.json                — paint editor's saved arena
  4. User-data drafts/draft_*.json       — saved templates

Output: deduped paths, grouped by top-level asset folder. Nothing
moved, nothing imported, nothing modified.

Run from repo root:  python tools/audit_tiles_in_use.py
"""
import json, os, re, sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
USER_DATA = Path.home() / "AppData/Roaming/Godot/app_userdata/IsoZombiePoC"

# Match res:// PNG paths under assets/forest, assets/tilesets, assets/drops.
# Filenames may contain spaces (e.g. 'Ground A1_E.png') so we allow
# anything except quote / closing bracket / comma. Skips character /
# skin packs which aren't world tiles.
TILE_RX = re.compile(r'res://assets/(forest|tilesets|drops)/[^"\']+?\.png')

# Folders we don't care about scanning for source-code refs.
SKIP_DIRS = {".git", ".godot", "addons", "_archive", "assets",
             "tools", "docs", ".claude"}

def scan_text_for_paths(text: str, hits: set) -> None:
    for m in TILE_RX.finditer(text):
        hits.add(m.group(0))

def scan_repo(hits: set) -> None:
    for root, dirs, files in os.walk(REPO):
        # Prune skip dirs
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for fn in files:
            if not fn.endswith((".gd", ".json", ".tscn")):
                continue
            p = Path(root) / fn
            try:
                scan_text_for_paths(p.read_text(encoding="utf-8"), hits)
            except (UnicodeDecodeError, OSError):
                continue

def scan_user_arena(hits: set) -> None:
    arena = USER_DATA / "arena.json"
    if not arena.exists():
        return
    try:
        data = json.loads(arena.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"[warn] arena.json parse failed: {e}", file=sys.stderr)
        return
    for bucket in ("bases", "ripples", "props"):
        for entry in data.get(bucket, []):
            tex = entry.get("tex") or entry.get("path")
            if isinstance(tex, str) and TILE_RX.fullmatch(tex):
                hits.add(tex)

def scan_user_drafts(hits: set) -> None:
    drafts_dir = USER_DATA / "drafts"
    if not drafts_dir.is_dir():
        return
    for p in drafts_dir.glob("*.json"):
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
        except Exception:
            continue
        for bucket in ("bases", "ripples", "props"):
            for entry in data.get(bucket, []):
                tex = entry.get("tex") or entry.get("path")
                if isinstance(tex, str) and TILE_RX.fullmatch(tex):
                    hits.add(tex)

def scan_tile_roles(hits: set) -> None:
    p = REPO / "data" / "tile_roles.json"
    if not p.exists():
        return
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return
    if isinstance(data, dict):
        for k in data.keys():
            if isinstance(k, str) and TILE_RX.fullmatch(k):
                hits.add(k)

def group_by_top(paths):
    """assets/<top>/<rest>.png -> {top: [rest...]}"""
    out = {}
    for p in paths:
        # res://assets/forest/foo/bar.png -> ('forest', 'foo/bar.png')
        rel = p[len("res://assets/"):]
        top, _, rest = rel.partition("/")
        out.setdefault(top, []).append(rel)
    for k in out:
        out[k].sort()
    return out

def main():
    hits = set()
    scan_tile_roles(hits)
    scan_repo(hits)
    scan_user_arena(hits)
    scan_user_drafts(hits)
    print(f"# Tile audit — {len(hits)} unique tile paths in use\n")
    grouped = group_by_top(sorted(hits))
    for top in sorted(grouped):
        items = grouped[top]
        print(f"## assets/{top}/  ({len(items)} tiles)")
        for it in items:
            print(f"  - {it}")
        print()
    # Quick category roll-up so it's easy to spot oversize buckets.
    print("# Roll-up by sub-bucket")
    bucket_counts = {}
    for top, items in grouped.items():
        for rel in items:
            parts = rel.split("/")
            bucket = f"{top}/{parts[1] if len(parts) > 1 else '_root'}"
            bucket_counts[bucket] = bucket_counts.get(bucket, 0) + 1
    for b in sorted(bucket_counts, key=lambda x: -bucket_counts[x]):
        print(f"  {bucket_counts[b]:4d}  {b}")

if __name__ == "__main__":
    main()
