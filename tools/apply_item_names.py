#!/usr/bin/env python3
"""One-shot rename script for data/items/*/*.tres after the first naming pass.

Each entry below maps item_id -> dict of fields to set:
    {"name": "Display Name"}
    {"unique": "Display Name"}        # marks as unique
    {"name": "...", "stub": True}     # blanks can_drop, leaves base_name set as TODO marker

Run from repo root: python tools/apply_item_names.py
"""
import os, re, sys

NAMES = {
    # ----- BAG -----
    "bag_1": {"name": "Rucksack"},
    "bag_2": {"name": "Hunter's Quiver"},
    "bag_3": {"name": "Quiver"},
    "bag_4": {"unique": "Sylph's Embrace"},
    "bag_5": {"unique": "Pact of the Abyss"},
    "bag_6": {"name": "Traveler's Pack"},
    "bag_7": {"name": "(empty)", "stub": True},
    "bag_8": {"unique": "Raven's Mantle"},
    # ----- BELT -----
    "belt_1": {"name": "Leather Belt"},
    "belt_2": {"name": "Reinforced Belt"},
    # ----- CHEST -----
    "chest_1": {"name": "Tunic"},
    "chest_2": {"name": "Spaulders"},
    "chest_3": {"name": "Plate Mail"},
    "chest_4": {"name": "Heavy Plate"},
    "chest_5": {"name": "Tattered Mail"},
    "chest_6": {"name": "Warlord's Pauldrons"},
    "chest_7": {"name": "Crested Plate"},
    "chest_8": {"name": "Champion's Plate"},
    "chest_9": {"name": "Rogue's Garb"},
    "chest_10": {"name": "Padded Vest"},
    "chest_11": {"name": "Linen Shirt"},
    "chest_12": {"name": "Quilted Jerkin"},
    "chest_13": {"name": "Apprentice Robes"},
    "chest_14": {"name": "Archmage's Robes"},
    "chest_15": {"unique": "Shadowmender"},
    "chest_16": {"name": "Knight's Plate"},
    "chest_17": {"name": "Buccaneer's Coat"},
    "chest_18": {"name": "Wolfpelt Mantle"},
    "chest_19": {"unique": "Whisperveil"},
    # ----- HANDS -----
    "hands_1": {"name": "Gauntlets"},
    "hands_2": {"unique": "Grasping Coil"},
    "hands_3": {"name": "Hand Wraps"},
    "hands_4": {"name": "Duelist's Gloves"},
    # ----- HEAD ----- (head_2 = pendant, removed via SKIP_IDS in items_db.gd)
    "head_1": {"name": "Bandana"},
    "head_3": {"name": "Hood"},
    "head_4": {"name": "Cultist's Hood"},
    "head_5": {"name": "Circlet"},
    "head_6": {"name": "Executioner's Hood"},
    "head_7": {"name": "Assassin's Cowl"},
    "head_8": {"unique": "Crown of the Lich"},
    "head_9": {"name": "Hair 1", "stub": True},
    "head_10": {"name": "Hair 2", "stub": True},
    "head_11": {"name": "Bald", "stub": True},
    "head_12": {"name": "Wanderer's Hood"},
    "head_13": {"name": "Iron Helm"},
    "head_14": {"unique": "Wargaze"},
    "head_15": {"name": "Witch's Hat"},
    "head_16": {"name": "Hair 3", "stub": True},
    "head_17": {"name": "Hair 4", "stub": True},
    "head_18": {"name": "Hornsteel Helm"},
    "head_19": {"name": "Spiked Helm"},
    "head_20": {"unique": "Carapace Crown"},
    "head_21": {"unique": "Bonespire"},
    "head_22": {"name": "Hair 5", "stub": True},
    "head_23": {"unique": "Nightcowl"},
    "head_24": {"unique": "Medusan Veil"},
    # ----- LEGS -----
    "legs_1": {"name": "Trousers"},
    "legs_2": {"name": "Loose Breeches"},
    "legs_3": {"name": "Mage's Robes"},
    "legs_4": {"name": "Linen Leggings"},
    "legs_5": {"name": "Plate Greaves"},
    "legs_6": {"name": "Banded Leggings"},
    "legs_7": {"name": "Mail Leggings"},
    "legs_8": {"name": "Knightly Greaves"},
    "legs_9": {"name": "Breeches"},
    # ----- MAINHAND (Melee) -----
    "melee_1": {"name": "Dagger"},
    "melee_2": {"name": "Longsword"},
    "melee_3": {"name": "Saber"},
    "melee_4": {"name": "Cleaver"},
    "melee_5": {"name": "Broadsword"},
    "melee_6": {"name": "Greatsword"},
    "melee_7": {"name": "Scimitar"},
    "melee_8": {"unique": "Soulrend"},
    "melee_9": {"name": "Mace"},
    "melee_10": {"name": "Warhammer"},
    "melee_11": {"name": "Maul"},
    "melee_12": {"name": "Heavy Mace"},
    "melee_13": {"unique": "Twinfang"},
    "melee_14": {"name": "Battleaxe"},
    "melee_15": {"name": "Hand Axe"},
    "melee_16": {"name": "Greataxe"},
    "melee_17": {"name": "Bearded Axe"},
    "melee_18": {"name": "Pickaxe (mining — pending)", "stub": True},
    "melee_19": {"name": "Wizard's Staff"},
    "melee_20": {"name": "Runed Staff"},
    "melee_21": {"unique": "Stormcaller"},
    "melee_22": {"unique": "Wand of the Lich"},
    "melee_23": {"unique": "Skyrender"},
    "melee_24": {"name": "Spear"},
    "melee_25": {"name": "Pike"},
    # ----- MAINHAND (Ranged) -----
    "ranged_1": {"name": "Shortbow"},
    "ranged_2": {"unique": "Wyrmstring"},
    "ranged_3": {"name": "Elven Bow"},
    "ranged_4": {"name": "Hunter's Bow"},
    "ranged_5": {"name": "Garden Tool (pending — not a bow)", "stub": True},
    "ranged_6": {"unique": "Crossfire"},
    "ranged_7": {"name": "Composite Bow"},
    # ----- MOUNT -----
    "mount_1": {"name": "Steed"},
    "mount_2": {"name": "Mountain Ram"},
    "mount_3": {"name": "War Bear"},
    "mount_4": {"name": "Dire Wolf"},
    "mount_5": {"unique": "Brood Mother"},
    # ----- OFFHAND -----
    "offhand_1": {"name": "Parrying Sword"},
    "offhand_2": {"name": "Off-hand Dagger"},
    # ----- SHIELD -----
    "shield_1": {"name": "Round Shield"},
    "shield_2": {"unique": "Aegis of the Sun"},
    "shield_3": {"name": "Heater Shield"},
    "shield_4": {"name": "Templar Shield"},
    "shield_5": {"name": "Tower Shield"},
    "shield_6": {"name": "Kite Shield"},
    "shield_7": {"name": "Bark Shield"},
    # ----- SHOES -----
    "shoes_1": {"name": "Shoes"},
    "shoes_2": {"name": "Boots"},
    "shoes_3": {"name": "Soft Boots"},
    "shoes_4": {"name": "Sandals"},
    "shoes_5": {"name": "Riding Boots"},
}

# Files to delete entirely (item also pruned from items_db catalog).
DELETE_IDS = {"head_2"}

ROOT = "data/items"

def slot_for(item_id: str) -> str:
    if item_id.startswith(("melee_", "ranged_", "magic_")):
        return "mainhand"
    return item_id.split("_", 1)[0]

def patch_field(text: str, key: str, value: str) -> str:
    pat = re.compile(r'^' + re.escape(key) + r'\s*=.*$', re.MULTILINE)
    if pat.search(text):
        return pat.sub(f'{key} = {value}', text, count=1)
    # Field missing — append before EOF (after last existing key in [resource]).
    return text.rstrip() + f"\n{key} = {value}\n"

def main():
    if not os.path.isdir(ROOT):
        print(f"missing {ROOT}; run from repo root", file=sys.stderr); sys.exit(1)
    updated = deleted = 0
    for item_id in DELETE_IDS:
        path = os.path.join(ROOT, slot_for(item_id), f"{item_id}.tres")
        if os.path.exists(path):
            os.remove(path); deleted += 1; print(f"DEL  {path}")
    for item_id, spec in NAMES.items():
        path = os.path.join(ROOT, slot_for(item_id), f"{item_id}.tres")
        if not os.path.exists(path):
            print(f"skip (no file) {path}"); continue
        with open(path, "r") as f: txt = f.read()
        if "unique" in spec:
            txt = patch_field(txt, "is_unique", "true")
            txt = patch_field(txt, "unique_name", f'"{spec["unique"]}"')
            txt = patch_field(txt, "base_name", f'""')
        else:
            txt = patch_field(txt, "is_unique", "false")
            txt = patch_field(txt, "unique_name", '""')
            txt = patch_field(txt, "base_name", f'"{spec["name"]}"')
        if spec.get("stub"):
            txt = patch_field(txt, "can_drop", "false")
        else:
            txt = patch_field(txt, "can_drop", "true")
        with open(path, "w") as f: f.write(txt)
        updated += 1; print(f"OK   {path}")
    print(f"\nupdated: {updated}    deleted: {deleted}")

if __name__ == "__main__":
    main()
