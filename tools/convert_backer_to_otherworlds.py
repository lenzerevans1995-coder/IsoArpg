"""
One-shot converter: takes BackerReward characters (24x25 grid, 160 px frames,
4 PNGs per slot, cardinal+diagonal halves per anim) and re-renders each slot
as a single 50x50 OtherWorlds-format spritesheet (8000x8000, 160 px frames),
so they slot into the existing female/male kit's variant lists.

Drop the converted sheets into:
  assets/character_pieces/<gender>/<canonical_slot>/Backer_<Char>_<Slot>/
                                                                        Spritesheet.png

Run after the main importer; rerunning is idempotent (skips existing files).
"""
import json, os, struct, sys
from PIL import Image

Image.MAX_IMAGE_PIXELS = None

PROJ = r"C:/Users/evans/OneDrive/Desktop/2dIsoGame"
BACKER_ROOT = os.path.join(PROJ, "assets/backer_characters")
PIECES_OUT = os.path.join(PROJ, "assets/character_pieces")
BACKER_CAT = os.path.join(PROJ, "backer_anim_catalog.json")
OW_CAT = os.path.join(PROJ, "character_pieces_catalog.json")

OW_GRID = 50
OW_OUT_SIZE = 5000     # match PIECES_TARGET in import_pvgames_packs.py
FRAME = OW_OUT_SIZE // OW_GRID   # OW cell size in the destination canvas
BACKER_CELL = 160       # Backer source cell size (always 160 px)
BACKER_GRID_W = 24
BACKER_GRID_H = 25

# Body-height ratio between OW (~44% cell fill) and Backer (~54% cell fill).
BODY_HEIGHT_RATIO = 0.83
# Combined scale: cell-size ratio × body-height ratio. Backer cells get
# resampled from 160 -> FRAME, then further shrunk so the character body
# matches OW proportions, then bottom-centered into the FRAME-sized cell.
BACKER_TO_OW_SCALE = (float(FRAME) / float(BACKER_CELL)) * BODY_HEIGHT_RATIO

# Backer anim name -> OtherWorlds anim name. Anims not in the map are skipped.
ANIM_MAP = {
    "Walking":              "Walk",
    "Running":              "Run",
    "Idle 1":               "Idle 1",
    "Idle 2":               "Idle 2",
    "Idle 3":               "Idle 3",
    "Idle 4":               "Idle 4",
    "Sitting":              "Sitting",
    "Casting":              "Casting",
    "Block Shield":         "Block",
    "Evade":                "Evade Roll",
    "Get Hit":              "Get Hit 1",
    "Use Item":             "Use Item",
    "Punch":                "Unarmed Attack 2",
    "1-H Idle General":     "1-H Idle",
    "Attack 1-H Side Slash":"1-H Attack 1",
    "Attack 1-H Overhead":  "1-H Attack 2",
    "Attack 1-H Stab":      "1-H Attack 3",
    "2-H Idle General 1":   "2-H Idle",
    "Attack 2-H Slash":     "2-H Attack 1",
    "Attack 2-H Swing":     "2-H Attack 2",
    "Idle Dual-Wield":      "Dual Wield I dle",
    "Attack Dual-Wield":    "Dual Wield Attack 1",
    "Idle Bow":             "Bow Idle",
    "Attack Bow":           "Bow Attack 1",
    "Idle Pistol 1":        "Pistol Idle",
    "Attack Pistol 1":      "Pistol Attack 1",
    "Attack Pistol 2":      "Pistol Attack 2",
    "Idle Rifle 1":         "MG/Rifle/ Xbow Idle",
    "Attack Rifle":         "MG/Rifle/ Xbow Attack 1",
    "Sneak":                "Sneaking",
    "Pray Standing":        "Praying",
    "Jump":                 "Jump",
    "Drink":                "Drink",
    "Climb":                "Climb",
    "Critical Health Idle 1": "Critical Idle 1",
    "Critical Health Idle 2": "Critical Idle 2",
    "Idle Unarmed":         "Unarmed Idle",
    "Dead":                 "Dead/Down Forward",
}

# Slot suffix (after Char_) -> OW canonical slot.
SLOT_MAP = {
    "Base": "Base", "Top": "Top", "Bottom": "Bottom", "Hair": "Hair",
    "Head": "Head", "FacialHair": "FacialHair",
    "Bow": "Weapons", "Crossbow": "Weapons", "Sword": "Weapons",
    "Mace": "Weapons", "Dagger": "Weapons", "Staff": "Weapons",
    "Pistol": "Weapons", "Rifle": "Weapons", "Pickaxe": "Weapons",
    "Weapon": "Weapons", "Shield": "Weapons",
    "Back": "Accessories", "Hat": "Hair", "Instrument": "Accessories",
}

CHAR_TO_GENDER = {
    "Female_Archer":     "female", "Female_Bard":         "female",
    "Female_Battleguard":"female", "Female_Cleric":       "female",
    "Female_Mage":       "female", "Female_Orc1":         "female",
    "Female_Rogue":      "female",
    "Male_Musketeer":    "male",   "Male_Miner":          "male",
}

def load_sheet(path):
    if not os.path.isfile(path):
        return None
    return Image.open(path).convert("RGBA")

def map_index_backer(idx):
    return (idx % BACKER_GRID_W, idx // BACKER_GRID_W)

def map_index_ow(idx):
    return (idx % OW_GRID, idx // OW_GRID)

def copy_anim(canvas, sheets, banim, oanim):
    """sheets is a list of 4 PIL images (Sprite_1..4). banim, oanim are dicts."""
    sheet_idx = int(banim["sheet"]) - 1
    if sheet_idx < 0 or sheet_idx >= len(sheets) or sheets[sheet_idx] is None:
        return
    src = sheets[sheet_idx]
    bcard = int(banim["card"]); bdiag = int(banim["diag"])
    btotal = int(banim["total"])
    bper = btotal // 8
    flat = (bcard == bdiag)   # Dead anim: all 8 dirs sequential from card
    oper = int(oanim["per_dir"])
    ostart = int(oanim["start"])
    for d in range(8):
        if flat:
            bdir = bcard + d * bper
        elif d < 4:
            bdir = bcard + d * bper
        else:
            bdir = bdiag + (d - 4) * bper
        for f in range(oper):
            if oper == bper:
                src_f = bdir + f
            elif bper > oper:
                src_f = bdir + (f * bper) // oper
            else:
                # ping-pong pad: 0,1,2,1,0 for bper=3, oper=5
                if f < bper:
                    src_f = bdir + f
                else:
                    j = 2 * bper - 2 - f
                    if j < 0: j = 0
                    src_f = bdir + j
            bc, br = map_index_backer(src_f)
            ow_idx = ostart + d * oper + f
            oc, orow = map_index_ow(ow_idx)
            try:
                cell = src.crop((bc * FRAME, br * FRAME, (bc+1) * FRAME, (br+1) * FRAME))
                # Scale + bottom-center so Backer characters match OW kit body height.
                nw = int(FRAME * BACKER_TO_OW_SCALE)
                nh = int(FRAME * BACKER_TO_OW_SCALE)
                scaled = cell.resize((nw, nh), Image.LANCZOS)
                placed = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
                dx = (FRAME - nw) // 2
                dy = FRAME - nh   # feet at bottom edge
                placed.paste(scaled, (dx, dy), scaled)
                canvas.paste(placed, (oc * FRAME, orow * FRAME), placed)
            except Exception:
                pass

def parse_slot(folder):
    """Female_Archer/Archer_Bow -> ('Archer', 'Bow')"""
    name = os.path.basename(folder)
    if "_" in name:
        prefix, suffix = name.split("_", 1)
        return prefix, suffix
    return None, name

def main():
    backer_cat = json.load(open(BACKER_CAT))["animations"]
    ow_cat = json.load(open(OW_CAT))["animations"]
    if not os.path.isdir(BACKER_ROOT):
        print(f"missing {BACKER_ROOT}"); return 1
    written = 0
    for char in sorted(os.listdir(BACKER_ROOT)):
        char_dir = os.path.join(BACKER_ROOT, char)
        if not os.path.isdir(char_dir):
            continue
        gender = CHAR_TO_GENDER.get(char)
        if gender is None:
            print(f"skip {char}: unknown gender"); continue
        for slot_folder in sorted(os.listdir(char_dir)):
            slot_dir = os.path.join(char_dir, slot_folder)
            if not os.path.isdir(slot_dir):
                continue
            _, suffix = parse_slot(slot_folder)
            ow_slot = SLOT_MAP.get(suffix)
            if ow_slot is None:
                print(f"  - {char}/{slot_folder}: no OW slot mapping for '{suffix}'")
                continue
            variant = f"Backer_{char}_{suffix}"
            dst_dir = os.path.join(PIECES_OUT, gender, ow_slot, variant)
            dst = os.path.join(dst_dir, "Spritesheet.png")
            if os.path.isfile(dst):
                continue
            sheets = [load_sheet(os.path.join(slot_dir, f"Sprite_{n}.png")) for n in [1,2,3,4]]
            if all(s is None for s in sheets):
                continue
            canvas = Image.new("RGBA", (OW_OUT_SIZE, OW_OUT_SIZE), (0,0,0,0))
            for bname, oname in ANIM_MAP.items():
                if bname not in backer_cat or oname not in ow_cat:
                    continue
                copy_anim(canvas, sheets, backer_cat[bname], ow_cat[oname])
            os.makedirs(dst_dir, exist_ok=True)
            canvas.save(dst, format="PNG", optimize=False)
            written += 1
            print(f"  + {gender}/{ow_slot}/{variant}")
    print(f"\nwrote {written} converted spritesheets.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
