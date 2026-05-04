"""
Resamples PVGames OtherWorlds Character Creator Kit spritesheets from 10000x10000
(50x50 grid, 200px frames) down to 4000x4000 (50x50 grid, 80px frames). Outputs a
clean PNG (no GIMP/EXIF metadata) under assets/character_pieces/<kit>/<slot>/<variant>/.

Run once after dropping new variants in. Skips files that already exist.
"""
import os, sys
from PIL import Image

Image.MAX_IMAGE_PIXELS = None

SRC_KITS = {
    "female": r"C:/Users/evans/OneDrive/Desktop/2.5D assets/Other Worlds Character Creator Kit Female/Female",
    "male":   r"C:/Users/evans/OneDrive/Desktop/2.5D assets/Other Worlds Character Creator Kit Male/Male",
}
DST_ROOT = r"C:/Users/evans/OneDrive/Desktop/2dIsoGame/assets/character_pieces"
TARGET_SIZE = 6400   # 50x50 grid, 128px per frame

def resample(src_path: str, dst_path: str) -> None:
    if os.path.isfile(dst_path):
        return
    os.makedirs(os.path.dirname(dst_path), exist_ok=True)
    im = Image.open(src_path).convert("RGBA")
    if im.size != (TARGET_SIZE, TARGET_SIZE):
        im = im.resize((TARGET_SIZE, TARGET_SIZE), Image.LANCZOS)
    # Save as plain PNG without metadata.
    im.save(dst_path, format="PNG", optimize=False)
    print(f"  baked {dst_path}  ({os.path.getsize(dst_path)//1024} KB)")

def walk_kit(kit_name: str, base: str) -> None:
    if not os.path.isdir(base):
        print(f"skip {kit_name}: missing")
        return
    for slot in os.listdir(base):
        slot_path = os.path.join(base, slot)
        if not os.path.isdir(slot_path):
            continue
        # Slot may be a single sheet (Shadow) or a folder of variants.
        direct_sheet = os.path.join(slot_path, "Spritesheet.png")
        if os.path.isfile(direct_sheet):
            dst = os.path.join(DST_ROOT, kit_name, slot, "Spritesheet.png")
            print(f"{kit_name}/{slot}")
            resample(direct_sheet, dst)
            continue
        for variant in sorted(os.listdir(slot_path)):
            vpath = os.path.join(slot_path, variant)
            if not os.path.isdir(vpath):
                continue
            sheet = os.path.join(vpath, "Spritesheet.png")
            if not os.path.isfile(sheet):
                continue
            dst = os.path.join(DST_ROOT, kit_name, slot, variant, "Spritesheet.png")
            print(f"{kit_name}/{slot}/{variant}")
            resample(sheet, dst)

def main() -> int:
    for kit, base in SRC_KITS.items():
        walk_kit(kit, base)
    print("\ndone.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
