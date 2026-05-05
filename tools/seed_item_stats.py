#!/usr/bin/env python3
"""Seed baseline stats and unique-glow colors on key items.

Each entry: {field_name: value (raw .tres syntax)}.
Run from repo root:  python tools/seed_item_stats.py
"""
import os, re, sys

UPDATES = {
    # ---- baseline weapons ----
    "data/items/mainhand/melee_1.tres":  {"base_damage_min": "3",  "base_damage_max": "6"},   # Dagger
    "data/items/mainhand/melee_2.tres":  {"base_damage_min": "8",  "base_damage_max": "14"},  # Longsword (the "simple sword")
    "data/items/mainhand/melee_5.tres":  {"base_damage_min": "11", "base_damage_max": "17"},  # Broadsword
    "data/items/mainhand/melee_9.tres":  {"base_damage_min": "9",  "base_damage_max": "16"},  # Mace
    "data/items/mainhand/melee_10.tres": {"base_damage_min": "10", "base_damage_max": "18"},  # Warhammer
    # ---- a few uniques get fixed damage + colored glow ----
    "data/items/mainhand/melee_8.tres":  {"base_damage_min": "16", "base_damage_max": "26",
                                          "unique_glow_color": 'Color(1.0, 0.18, 0.20, 1)'},  # Soulrend (red)
    "data/items/mainhand/melee_22.tres": {"base_damage_min": "12", "base_damage_max": "22",
                                          "unique_glow_color": 'Color(0.65, 0.30, 0.95, 1)'}, # Wand of the Lich (purple)
    "data/items/mainhand/melee_23.tres": {"base_damage_min": "18", "base_damage_max": "30",
                                          "unique_glow_color": 'Color(0.40, 0.80, 1.0, 1)'},  # Skyrender (sky blue)

    # ---- baseline body armor (simple) ----
    "data/items/chest/chest_1.tres":  {"base_armor": "2"},   # Tunic
    "data/items/chest/chest_3.tres":  {"base_armor": "12"},  # Plate Mail (the "simple body armor")
    "data/items/chest/chest_4.tres":  {"base_armor": "16"},  # Heavy Plate
    "data/items/chest/chest_19.tres": {"base_armor": "10",
                                       "unique_glow_color": 'Color(0.45, 0.90, 1.0, 1)'},   # Whisperveil (cool teal)

    # ---- baseline leg armor ----
    "data/items/legs/legs_1.tres": {"base_armor": "1"},   # Trousers
    "data/items/legs/legs_5.tres": {"base_armor": "8"},   # Plate Greaves (the "simple leg armor")
    "data/items/legs/legs_8.tres": {"base_armor": "12"},  # Knightly Greaves
    "data/items/legs/legs_9.tres": {"base_armor": "1"},   # Shorts/Breeches — starter

    # ---- a couple unique mounts get glow ----
    "data/items/mount/mount_5.tres": {"unique_glow_color": 'Color(0.85, 0.10, 0.10, 1)'},  # Brood Mother (deep red)
}

def patch_field(text: str, key: str, value: str) -> str:
    pat = re.compile(r'^' + re.escape(key) + r'\s*=.*$', re.MULTILINE)
    if pat.search(text):
        return pat.sub(f'{key} = {value}', text, count=1)
    return text.rstrip() + f"\n{key} = {value}\n"

def main():
    n = 0
    for path, fields in UPDATES.items():
        if not os.path.exists(path):
            print(f"skip (missing) {path}")
            continue
        with open(path, "r", encoding="utf-8") as f: txt = f.read()
        for k, v in fields.items():
            txt = patch_field(txt, k, v)
        with open(path, "w", encoding="utf-8") as f: f.write(txt)
        n += 1; print(f"OK   {path}")
    print(f"\nupdated {n} files")

if __name__ == "__main__":
    main()
