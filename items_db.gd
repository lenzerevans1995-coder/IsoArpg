extends Node
class_name ItemsDB

# Catalog of all equipment available, keyed by item_id. Slot determines which
# LayeredCharacter layer the sheet binds to. weapon_class drives auto-attack-set
# selection (Melee->Attack1, Ranged->Attack2, Magic->Special1, etc.).
#
# Item id convention: "<slot>_<n>" matches the source folder name lowercased.
# Sources: shop = buyable, craft = recipe, loot = drop, starter = creator pick.

enum Slot { BODY, HEAD, HANDS, CHEST, LEGS, SHOES, BELT, BAG, MAINHAND, OFFHAND, SHIELD, MOUNT, VFX }
enum WeaponClass { NONE, MELEE, RANGED, MAGIC }

# Folder prefix -> (LayeredCharacter layer name, default count of variants)
const SLOT_LAYER := {
	Slot.BODY: "body",
	Slot.HEAD: "head",
	Slot.HANDS: "hands",
	Slot.CHEST: "chest",
	Slot.LEGS: "legs",
	Slot.SHOES: "shoes",
	Slot.BELT: "belt",
	Slot.BAG: "bag",
	Slot.MAINHAND: "mainhand",
	Slot.OFFHAND: "offhand",
	Slot.SHIELD: "offhand",
	Slot.MOUNT: "mount",
	Slot.VFX: "vfx",
}

# Per-slot variant counts as discovered in StreamingAssets/spritesheets.
# (Skin tone Body is "NakedBody", "NakedBody2", "NakedBody3" — handled specially.)
const SLOT_COUNTS := {
	Slot.HEAD: 24,
	Slot.HANDS: 4,
	Slot.CHEST: 19,
	Slot.LEGS: 9,
	Slot.SHOES: 5,
	Slot.BELT: 2,
	Slot.BAG: 8,
	Slot.MAINHAND: 0,   # composed from MELEE+RANGED+MAGIC
	Slot.OFFHAND: 2,
	Slot.SHIELD: 7,
	Slot.MOUNT: 5,
}

const MELEE_COUNT := 25
const RANGED_COUNT := 7
const MAGIC_COUNT := 3
const BODY_TONES := ["NakedBody", "NakedBody2", "NakedBody3"]

# Items intended for character-creator pick (cosmetic starters).
const STARTER_HEADS := 24       # all heads available in creator
# IDs that exist as sheet folders but should NOT appear in the catalog.
# head_2 was originally "necklace" — wrong slot, retired.
const SKIP_IDS := {"head_2": true}
const STARTER_CHESTS := [1, 2, 3]
const STARTER_LEGS := [1, 2, 3]
const STARTER_SHOES := [1, 2]
const STARTER_HANDS := [1]
const STARTER_BODIES := BODY_TONES

# Build the full item catalog at runtime. Returns Array of Dictionary entries.
static func build_catalog() -> Array:
	var out: Array = []
	for n in range(1, STARTER_HEADS + 1):
		var hid: String = "head_%d" % n
		if SKIP_IDS.has(hid): continue
		out.append(_mk(hid, Slot.HEAD, "Head%d" % n, "Head %d" % n, "starter"))
	for n in range(1, SLOT_COUNTS[Slot.CHEST] + 1):
		var src := "starter" if n in STARTER_CHESTS else _src_for_tier(n)
		out.append(_mk("chest_%d" % n, Slot.CHEST, "Chest%d" % n, "Chest %d" % n, src))
	for n in range(1, SLOT_COUNTS[Slot.LEGS] + 1):
		var src := "starter" if n in STARTER_LEGS else _src_for_tier(n)
		out.append(_mk("legs_%d" % n, Slot.LEGS, "Legs%d" % n, "Legs %d" % n, src))
	for n in range(1, SLOT_COUNTS[Slot.SHOES] + 1):
		var src := "starter" if n in STARTER_SHOES else _src_for_tier(n)
		out.append(_mk("shoes_%d" % n, Slot.SHOES, "Shoes%d" % n, "Shoes %d" % n, src))
	for n in range(1, SLOT_COUNTS[Slot.HANDS] + 1):
		var src := "starter" if n in STARTER_HANDS else "shop"
		out.append(_mk("hands_%d" % n, Slot.HANDS, "Hands%d" % n, "Hands %d" % n, src))
	for n in range(1, SLOT_COUNTS[Slot.BELT] + 1):
		out.append(_mk("belt_%d" % n, Slot.BELT, "Belt%d" % n, "Belt %d" % n, "shop"))
	for n in range(1, SLOT_COUNTS[Slot.BAG] + 1):
		out.append(_mk("bag_%d" % n, Slot.BAG, "Bag%d" % n, "Bag %d" % n, "shop"))
	for n in range(1, SLOT_COUNTS[Slot.OFFHAND] + 1):
		out.append(_mk("offhand_%d" % n, Slot.OFFHAND, "Offhand%d" % n, "Offhand %d" % n, "loot"))
	for n in range(1, SLOT_COUNTS[Slot.SHIELD] + 1):
		out.append(_mk("shield_%d" % n, Slot.SHIELD, "Shield%d" % n, "Shield %d" % n, "loot"))
	for n in range(1, SLOT_COUNTS[Slot.MOUNT] + 1):
		out.append(_mk("mount_%d" % n, Slot.MOUNT, "Mount%d" % n, "Mount %d" % n, "shop"))
	# Weapons: separate by class so we can drive attack-set selection.
	for n in range(1, MELEE_COUNT + 1):
		var e := _mk("melee_%d" % n, Slot.MAINHAND, "Melee%d" % n, "Melee %d" % n, "loot")
		e["weapon_class"] = WeaponClass.MELEE
		out.append(e)
	for n in range(1, RANGED_COUNT + 1):
		var e := _mk("ranged_%d" % n, Slot.MAINHAND, "Ranged%d" % n, "Ranged %d" % n, "loot")
		e["weapon_class"] = WeaponClass.RANGED
		out.append(e)
	# Magic1/2/3 sheets are spell-cast hand animations, not equippable
	# items — intentionally not in the catalog. The WeaponClass.MAGIC
	# enum stays for future spell-class items that don't bind to those
	# specific sheets.
	# VFX layer — special abilities / auras the character creator
	# exposes. Effect1..5 are general-purpose visual overlays; Special1/2
	# are class-tied cast effects. All play on the LayeredCharacter's
	# 'vfx' layer (top of the layer stack). Browse + name them in the
	# item editor like any other item; pick one to equip via a future
	# ability-binding UI.
	for n in range(1, 6):
		out.append(_mk("effect_%d" % n, Slot.VFX, "Effect%d" % n, "Effect %d" % n, "ability"))
	for n in range(1, 3):
		out.append(_mk("special_%d" % n, Slot.VFX, "Special%d" % n, "Special %d" % n, "ability"))
	return out

static func _mk(id: String, slot: int, folder: String, display: String, source: String) -> Dictionary:
	return {
		"id": id,
		"slot": slot,
		"folder": folder,
		"display": display,
		"source": source,
		"weapon_class": WeaponClass.NONE,
	}

static func _src_for_tier(n: int) -> String:
	# Higher-numbered variants lean toward loot/craft; mid-tier in shops.
	if n <= 8:
		return "shop"
	if n <= 14:
		return "craft"
	return "loot"

# Auto-pick the attack anim for a given weapon class. The body sheet's
# Attack rows have weapon-specific poses authored in: Attack1 reads as
# a melee swing, Attack3 is the canonical bow-draw + release on the
# Fantasy tileset bodies. If a particular weapon set looks wrong here
# tweak per-class instead of fighting the convention.
static func attack_anim_for(weapon_class: int) -> String:
	match weapon_class:
		WeaponClass.MELEE: return "Attack1"
		WeaponClass.RANGED: return "Attack3"
		WeaponClass.MAGIC: return "Special1"
		_: return "Attack1"
