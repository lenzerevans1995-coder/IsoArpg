import os, json
from PIL import Image

ASSET_ROOT = r"C:/Users/evans/OneDrive/Desktop/2dIsoGame/assets/charachters/Sprites/Players"
PACKS = [
    ("hd1",     "Projectiles - 2D HD Character pack 1"),
    ("pack1",   "Projectiles Character Pack 1"),
    ("pack2",   "Projectiles Character Pack 2"),
]
# Fantasy tileset effects live outside the Players/ tree but are
# functionally a projectile pack (Bolt = travel, AoE = at_target,
# Buff* = at_player, etc.). Wired in here so the skill editor exposes
# them under the same Pack/Category/Name pickers.
FANTASY_PACK = ("fantasy",
    r"C:/Users/evans/OneDrive/Desktop/2dIsoGame/assets/tilesets/Fantasy tileset - 2D Isometric V1.1/Fantasy tileset - 2D Isometric/Animations/Effects")

PROJECT_ROOT = r"C:/Users/evans/OneDrive/Desktop/2dIsoGame"

def norm(p):
    s = p.replace(os.sep, "/")
    # Godot's load()/ResourceLoader only accept res:// paths, not absolute
    # filesystem paths. Strip the project root and rewrite as res://.
    pl = s.lower(); rl = PROJECT_ROOT.lower()
    if pl.startswith(rl):
        return "res://" + s[len(PROJECT_ROOT):].lstrip("/")
    return s

def category_default_motion(cat):
    cl = cat.lower()
    if "arrow" in cl: return "travel"
    if "aoe" in cl:   return "at_target"
    if "spell" in cl: return "at_player"
    return "at_target"

def category_for_fantasy(name):
    nl = name.lower()
    if nl.startswith("buff") or nl == "levelup": return "Buffs"
    if nl == "bolt": return "Bolts"
    if nl == "aoe":  return "AoE"
    if nl == "cone": return "Cones"
    if nl == "dash" or nl == "hook": return "Movement"
    return "Effects"

def fantasy_motion_default(cat):
    cl = cat.lower()
    if cl == "buffs": return "at_player"
    if cl == "bolts": return "travel"
    if cl == "aoe": return "at_target"
    return "at_target"

out = {}
# Fantasy tileset effects: flat list of subfolders, no per-category
# directory layer. Bucket them into virtual categories based on name.
fantasy_base = FANTASY_PACK[1]
if os.path.isdir(fantasy_base):
    for entry in sorted(os.listdir(fantasy_base)):
        ep = os.path.join(fantasy_base, entry)
        if not os.path.isdir(ep):
            continue
        pngs = sorted([f for f in os.listdir(ep) if f.endswith(".png") and not f.endswith(".import")])
        if not pngs: continue
        sample = os.path.join(ep, pngs[0])
        try:
            im = Image.open(sample); w, h = im.size
            cat = category_for_fantasy(entry)
            out.setdefault(FANTASY_PACK[0], {}).setdefault(cat, {})[entry] = {
                "kind": "folder",
                "path": norm(ep),
                "frames": [norm(os.path.join(ep, f)) for f in pngs],
                "frame_count": len(pngs),
                "size": [w, h],
                "motion_default": fantasy_motion_default(cat),
            }
        except Exception:
            pass

for pid, pdir in PACKS:
    base = os.path.join(ASSET_ROOT, pdir)
    if not os.path.isdir(base):
        continue
    # Some packs (the HD one) have the actual category folders one
    # level deeper, in a directory named the same as the pack itself.
    # Auto-descend if base contains exactly one subfolder named the same.
    contents = [c for c in os.listdir(base) if os.path.isdir(os.path.join(base, c))]
    if len(contents) == 1 and contents[0] == pdir:
        base = os.path.join(base, pdir)
    for cat in sorted(os.listdir(base)):
        catp = os.path.join(base, cat)
        if not os.path.isdir(catp):
            continue
        for entry in sorted(os.listdir(catp)):
            ep = os.path.join(catp, entry)
            if os.path.isdir(ep):
                pngs = sorted([f for f in os.listdir(ep) if f.endswith(".png") and not f.endswith(".import")])
                if not pngs: continue
                sample = os.path.join(ep, pngs[0])
                try:
                    im = Image.open(sample)
                    w, h = im.size
                    out.setdefault(pid, {}).setdefault(cat, {})[entry] = {
                        "kind": "folder",
                        "path": norm(ep),
                        "frames": [norm(os.path.join(ep, f)) for f in pngs],
                        "frame_count": len(pngs),
                        "size": [w, h],
                        "motion_default": category_default_motion(cat),
                    }
                except Exception:
                    pass
            elif entry.endswith(".png") and not entry.endswith(".import"):
                name = os.path.splitext(entry)[0]
                if name in out.get(pid, {}).get(cat, {}):
                    continue
                try:
                    im = Image.open(ep)
                    w, h = im.size
                    out.setdefault(pid, {}).setdefault(cat, {})[name] = {
                        "kind": "sheet",
                        "path": norm(ep),
                        "size": [w, h],
                        "frame_h": h // 8,
                        "motion_default": category_default_motion(cat),
                    }
                except Exception:
                    pass

for pid in out:
    total = sum(len(v) for v in out[pid].values())
    print("=== %s (%d entries) ===" % (pid, total))
    for cat, items in out[pid].items():
        print("  %s: %d" % (cat, len(items)))
        for n, info in list(items.items())[:3]:
            fc = info.get("frame_count", 1)
            print("    %s -> %s fc=%d (%s)" % (n, info["size"], fc, info["kind"]))

target = r"C:/Users/evans/OneDrive/Desktop/2dIsoGame/data/projectiles.json"
with open(target, "w") as f:
    json.dump(out, f, indent="\t", sort_keys=True)
print("wrote", target)
