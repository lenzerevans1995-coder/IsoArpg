"""
Imports every compatible PVGames pack from C:/Users/evans/OneDrive/Desktop/2.5D assets/
into the project:

  - OtherWorlds Character Creator Kit Female/Male  -> assets/character_pieces/<kit>/
  - Other Worlds Patreon Exclusive Armor           -> appended into Female/Male slots
  - RTPTools_Addon_Weapons                          -> appended into Female/Male/Weapons
  - Other Worlds Goblins                           -> assets/character_pieces/goblin/
  - 21x21-grid monster spritesheets                -> assets/shader_sprites/<MonsterName>/
        (OtherWorlds_Monsters, Other Worlds Slime, SkullHound)

All character-piece sheets are resampled from 10000x10000 -> 6400x6400 (128 px/frame)
to fit VRAM with fast equip swaps. Monster sheets are copied as-is (cleaned of
GIMP/EXIF metadata) since they're already 6300x6300 (300 px/frame).

Skips files already at the destination so re-runs are cheap.

Outputs:
  assets/character_pieces/...
  assets/shader_sprites/...
  character_kit_manifest.json   (updated with new slots/variants)
"""
import os, sys, json, struct
from PIL import Image

Image.MAX_IMAGE_PIXELS = None

ROOT = r"C:/Users/evans/OneDrive/Desktop/2.5D assets"
PROJ = r"C:/Users/evans/OneDrive/Desktop/2dIsoGame"
PIECES_OUT = os.path.join(PROJ, "assets", "character_pieces")
MONSTERS_OUT = os.path.join(PROJ, "assets", "shader_sprites")

PIECES_TARGET = 5000        # 50x50 grid -> 100 px/frame (~5MB/sheet PNG, ~100MB VRAM uncompressed)

# Plural-to-singular slot remap. Several packs use "Bases", "Bottoms", "Tops".
PLURAL_SLOT_REMAP = {"Bases": "Base", "Bottoms": "Bottom", "Tops": "Top",
                     "Weapon": "Weapons"}

CHARACTER_KIT_SOURCES = [
    # OtherWorlds base kits
    {"root": os.path.join(ROOT, "Other Worlds Character Creator Kit Female", "Female"),
     "kit": "female"},
    {"root": os.path.join(ROOT, "Other Worlds Character Creator Kit Male", "Male"),
     "kit": "male"},
    # Patreon exclusive armor
    {"root": os.path.join(ROOT, "Other Worlds Patreon Exclusive Armor",
                          "Other Worlds Patreon Exclusive", "Character Pieces", "Female"),
     "kit": "female"},
    {"root": os.path.join(ROOT, "Other Worlds Patreon Exclusive Armor",
                          "Other Worlds Patreon Exclusive", "Character Pieces", "Male"),
     "kit": "male"},
    # RTPTools weapon addon
    {"root": os.path.join(ROOT, "RTPTools_Addon_Weapons", "Character Pieces", "Female"),
     "kit": "female"},
    {"root": os.path.join(ROOT, "RTPTools_Addon_Weapons", "Character Pieces", "Male"),
     "kit": "male"},
    # Goblins (21x21 monster-style grid at 200px/frame). target_size=None means
    # copy without resampling so the catalog can detect the original layout.
    {"root": os.path.join(ROOT, "Other Worlds Goblins", "Other Worlds Goblins",
                          "Character Pieces", "Goblin"),
     "kit": "goblin", "target_size": None},
    # Northfolk (merged into the base male/female kits as additional variants)
    {"root": os.path.join(ROOT, "Northfolk_CharacterCreatorKit_1",
                          "Northfolk Character Creator Kit 1", "Male"),
     "kit": "male"},
    {"root": os.path.join(ROOT, "Northfolk_CharacterCreatorKit_2",
                          "Northfolk Character Creator Kit 2", "Female"),
     "kit": "female"},
]

# RPGTools_Addon_Characters_*  +  RPGTools_CharacterPieces_*  follow the same
# layout (root/<gender>/<slot>/<variant>) so we glob them in.
def _add_rpgtools_dirs():
    for n in range(1, 7):
        d = os.path.join(ROOT, f"RPGTools_Addon_Characters_{n}")
        if os.path.isdir(d):
            for gender in ("Female", "Male"):
                gp = os.path.join(d, gender)
                if os.path.isdir(gp):
                    CHARACTER_KIT_SOURCES.append({"root": gp, "kit": gender.lower()})
    for n in range(1, 6):
        d = os.path.join(ROOT, f"RPGTools_CharacterPieces_{n}")
        if os.path.isdir(d):
            for gender in ("Female", "Male"):
                gp = os.path.join(d, gender)
                if os.path.isdir(gp):
                    CHARACTER_KIT_SOURCES.append({"root": gp, "kit": gender.lower()})

_add_rpgtools_dirs()

# One-off fix: a corrected Male/Top/RTP_3 sheet ships in a flat folder. Apply
# it on top of any prior bake.
FIXED_TOP_RTP_3 = os.path.join(ROOT, "FIXED-Character Pieces - Male - Top _ RTP_3",
                               "Spritesheet.png")

# Folders containing Spritesheet.png monster sheets (21x21 grid format).
MONSTER_SOURCES = [
    os.path.join(ROOT, "OtherWorlds_Monsters", "Other Worlds Monsters"),
    os.path.join(ROOT, "Other Worlds Slime", "Other Worlds Slime", "Creatures"),
    os.path.join(ROOT, "Other Worlds Patreon Exclusive Skull Hound"),
]

# ---- HELPERS ----------------------------------------------------------------

def fix(p): return p.replace(os.sep, "/")

def strip_png_metadata(src: str, dst: str) -> bool:
    """Copy a PNG keeping only IHDR/IDAT/IEND/PLTE/tRNS (no GIMP/EXIF)."""
    if os.path.isfile(dst):
        return False
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(src, "rb") as f:
        data = f.read()
    out = bytearray(data[:8])
    keep = {b"IHDR", b"IDAT", b"IEND", b"PLTE", b"tRNS"}
    i = 8
    while i < len(data):
        ln = struct.unpack(">I", data[i:i+4])[0]
        typ = data[i+4:i+8]
        if typ in keep:
            out += data[i:i+8+ln+4]
        if typ == b"IEND":
            break
        i += 8 + ln + 4
    with open(dst, "wb") as f:
        f.write(out)
    return True

def resample(src_path: str, dst_path: str, target: int) -> bool:
    if os.path.isfile(dst_path):
        return False
    os.makedirs(os.path.dirname(dst_path), exist_ok=True)
    im = Image.open(src_path).convert("RGBA")
    if im.size != (target, target):
        im = im.resize((target, target), Image.LANCZOS)
    im.save(dst_path, format="PNG", optimize=False)
    return True

# ---- IMPORTERS --------------------------------------------------------------

def import_character_pack(spec, manifest):
    base = spec["root"]
    kit = spec["kit"]
    remap = spec.get("slot_remap", {}) or {}
    target_size = spec["target_size"] if "target_size" in spec else PIECES_TARGET
    if not os.path.isdir(base):
        print(f"skip {kit}: missing {base}")
        return
    print(f"\n[{kit}] from {base}")
    for slot in os.listdir(base):
        slot_path = os.path.join(base, slot)
        if not os.path.isdir(slot_path):
            continue
        canonical_slot = remap.get(slot, PLURAL_SLOT_REMAP.get(slot, slot))

        # Slot may be a single sheet (e.g. Shadow at slot root) or a folder of variants.
        direct_sheet = os.path.join(slot_path, "Spritesheet.png")
        if os.path.isfile(direct_sheet):
            dst = os.path.join(PIECES_OUT, kit, canonical_slot, "Spritesheet.png")
            if (strip_png_metadata(direct_sheet, dst) if target_size is None else resample(direct_sheet, dst, target_size)):
                print(f"  {kit}/{canonical_slot}  (single-sheet)")
            manifest.setdefault(kit, {}).setdefault(canonical_slot, [])
            continue

        for variant in sorted(os.listdir(slot_path)):
            vpath = os.path.join(slot_path, variant)
            if not os.path.isdir(vpath):
                continue
            sheet = os.path.join(vpath, "Spritesheet.png")
            if not os.path.isfile(sheet):
                continue
            dst = os.path.join(PIECES_OUT, kit, canonical_slot, variant, "Spritesheet.png")
            did = (strip_png_metadata(sheet, dst) if target_size is None else resample(sheet, dst, target_size))
            mark = "+" if did else "·"
            print(f"  {mark} {kit}/{canonical_slot}/{variant}")
            entries = manifest.setdefault(kit, {}).setdefault(canonical_slot, [])
            if not any(e.get("name") == variant for e in entries):
                entries.append({
                    "name": variant,
                    "spritesheet": fix(os.path.relpath(dst, PROJ)),
                })

def import_monsters():
    if not os.path.isdir(MONSTERS_OUT):
        os.makedirs(MONSTERS_OUT, exist_ok=True)
    for src in MONSTER_SOURCES:
        if not os.path.isdir(src):
            continue
        # Walk one level: SkullHound is direct, Other Worlds Monsters/Slime have
        # a sub-folder per creature.
        for entry in sorted(os.listdir(src)):
            sub = os.path.join(src, entry)
            if not os.path.isdir(sub):
                continue
            sheet = os.path.join(sub, "Spritesheet.png")
            if not os.path.isfile(sheet):
                continue
            dst = os.path.join(MONSTERS_OUT, entry, "Spritesheet.png")
            if strip_png_metadata(sheet, dst):
                print(f"  monster + {entry}")

# ---- MAIN -------------------------------------------------------------------

def main() -> int:
    manifest_path = os.path.join(PROJ, "character_kit_manifest.json")
    manifest = {
        "_doc": "PVGames OtherWorlds character pieces. 50x50 grid, baked at 128 px/frame (6400x6400). Slot order for layering bottom-to-top: Shadow, Base, Bottom, Top, Head, Hair, FacialHair, Weapons.",
    }
    for spec in CHARACTER_KIT_SOURCES:
        import_character_pack(spec, manifest)

    # Pick up any pre-existing variants written directly to the destination
    # tree (e.g. Backer_* sheets produced by convert_backer_to_otherworlds.py).
    if os.path.isdir(PIECES_OUT):
        for kit_name in os.listdir(PIECES_OUT):
            kit_dir = os.path.join(PIECES_OUT, kit_name)
            if not os.path.isdir(kit_dir):
                continue
            for slot_name in os.listdir(kit_dir):
                slot_dir = os.path.join(kit_dir, slot_name)
                if not os.path.isdir(slot_dir):
                    continue
                for variant in sorted(os.listdir(slot_dir)):
                    vdir = os.path.join(slot_dir, variant)
                    if not os.path.isdir(vdir):
                        continue
                    sheet = os.path.join(vdir, "Spritesheet.png")
                    if not os.path.isfile(sheet):
                        continue
                    entries = manifest.setdefault(kit_name, {}).setdefault(slot_name, [])
                    if not any(e.get("name") == variant for e in entries):
                        entries.append({
                            "name": variant,
                            "spritesheet": fix(os.path.relpath(sheet, PROJ)),
                        })

    # FIXED: Male/Top/RTP_3 corrected sheet overrides any prior bake.
    if os.path.isfile(FIXED_TOP_RTP_3):
        dst = os.path.join(PIECES_OUT, "male", "Top", "RTP_3", "Spritesheet.png")
        if os.path.isfile(dst):
            os.remove(dst)
        if resample(FIXED_TOP_RTP_3, dst, PIECES_TARGET):
            print(f"applied FIXED -> male/Top/RTP_3")
        # Make sure manifest entry exists.
        entries = manifest.setdefault("male", {}).setdefault("Top", [])
        if not any(e.get("name") == "RTP_3" for e in entries):
            entries.append({"name": "RTP_3", "spritesheet": fix(os.path.relpath(dst, PROJ))})

    # Sort variants per slot
    for kit in list(manifest.keys()):
        if kit.startswith("_"):
            continue
        for slot in manifest[kit]:
            manifest[kit][slot].sort(key=lambda e: e["name"])

    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)
    print(f"\nwrote {manifest_path}")

    print("\nmonsters:")
    import_monsters()

    print("\ndone.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
