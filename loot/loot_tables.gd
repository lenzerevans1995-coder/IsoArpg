extends RefCounted
class_name LootTables

# Per-enemy drop configuration. Roll order:
#   1. drop_chance — probability the enemy drops at all
#   2. drop_count  — number of items dropped (defaults to 1)
#   3. rarity_weights — pick rarity tier (common/magic/rare/unique/legendary)
#   4. slot_weights  — pick which slot the dropped item belongs to
#   5. items_db filter — gather every droppable item in that slot
#   6. drop_weight per-item — weighted pick within the filtered pool
#
# Slot weight keys:
#   "mainhand_melee", "mainhand_ranged" — slot+weapon_class composite
#   "chest", "legs", "head", "shoes", "hands", "belt", "bag",
#   "shield", "offhand", "mount" — direct slot mapping

const ItemsDB := preload("res://items_db.gd")
const ItemMetadataScript := preload("res://loot/item_metadata.gd")
const LootDropScript := preload("res://loot/loot_drop.gd")

const RARITY_KEYS := ["common", "magic", "rare", "unique", "legendary"]
const RARITY_VALUES := [
	LootDropScript.Rarity.COMMON,
	LootDropScript.Rarity.MAGIC,
	LootDropScript.Rarity.RARE,
	LootDropScript.Rarity.UNIQUE,
	LootDropScript.Rarity.LEGENDARY,
]

# Standard armor weights — every kind shares this shape with a custom
# mainhand slice on top.
const _ARMOR_BASE := {
	"chest": 15, "legs": 15, "head": 10, "shoes": 8,
	"hands": 6, "belt": 4, "bag": 2,
}

const TABLES := {
	# --- regular skeletons ---
	"skel_warrior": {
		"drop_chance": 0.45,
		"rarity_weights": {"common": 70, "magic": 22, "rare": 7, "unique": 1, "legendary": 0},
		"slot_weights": {
			"mainhand_melee": 30, "shield": 10,
			"chest": 15, "legs": 15, "head": 10, "shoes": 8, "hands": 6, "belt": 4, "bag": 2,
		},
	},
	"skel_archer": {
		"drop_chance": 0.45,
		"rarity_weights": {"common": 70, "magic": 22, "rare": 7, "unique": 1, "legendary": 0},
		"slot_weights": {
			"mainhand_ranged": 35,
			"chest": 15, "legs": 15, "head": 10, "shoes": 10, "hands": 8, "belt": 4, "bag": 3,
		},
	},
	"skel_wizard": {
		"drop_chance": 0.45,
		"rarity_weights": {"common": 65, "magic": 25, "rare": 8, "unique": 2, "legendary": 0},
		"slot_weights": {
			"chest": 25, "head": 20, "legs": 15, "bag": 15, "belt": 10, "shoes": 10, "hands": 5,
		},
	},
	# --- elites ---
	"skel_brute": {
		"drop_chance": 0.85,
		"rarity_weights": {"common": 35, "magic": 40, "rare": 20, "unique": 4, "legendary": 1},
		"slot_weights": {
			"mainhand_melee": 35, "shield": 12,
			"chest": 15, "legs": 12, "head": 10, "shoes": 6, "hands": 5, "belt": 3, "bag": 2,
		},
	},
	"skel_dark_knight": {
		"drop_chance": 0.85,
		"rarity_weights": {"common": 30, "magic": 40, "rare": 22, "unique": 6, "legendary": 2},
		"slot_weights": {
			"mainhand_melee": 30, "shield": 15,
			"chest": 17, "legs": 12, "head": 10, "shoes": 6, "hands": 5, "belt": 3, "bag": 2,
		},
	},
	"skel_berserker": {
		"drop_chance": 0.85,
		"rarity_weights": {"common": 35, "magic": 40, "rare": 20, "unique": 4, "legendary": 1},
		"slot_weights": {
			"mainhand_melee": 45,
			"chest": 15, "legs": 12, "head": 8, "shoes": 6, "hands": 6, "belt": 4, "bag": 4,
		},
	},
	"skel_dark_archer": {
		"drop_chance": 0.85,
		"rarity_weights": {"common": 30, "magic": 40, "rare": 22, "unique": 6, "legendary": 2},
		"slot_weights": {
			"mainhand_ranged": 40,
			"chest": 15, "legs": 12, "head": 10, "shoes": 8, "hands": 7, "belt": 4, "bag": 4,
		},
	},
	"skel_necromancer": {
		"drop_chance": 0.90,
		"rarity_weights": {"common": 25, "magic": 40, "rare": 25, "unique": 8, "legendary": 2},
		"slot_weights": {
			"chest": 22, "head": 18, "legs": 14, "bag": 16, "belt": 12, "shoes": 10, "hands": 8,
		},
	},
	# --- boss ---
	"skel_deathlord": {
		"drop_chance": 1.0,
		"drop_count": 3,
		"rarity_weights": {"common": 0, "magic": 20, "rare": 50, "unique": 25, "legendary": 5},
		"slot_weights": {
			"mainhand_melee": 25, "shield": 10,
			"chest": 20, "head": 15, "legs": 10, "hands": 8, "belt": 6, "bag": 4, "shoes": 2,
		},
	},
}

# Roll a full set of LootDrops for a kill. Returns Array of Dictionaries
# of the form {"item_id": String, "rarity": int, "is_unique": bool}.
# Caller decides where to spawn them (skeleton.gd uses its own position).
static func roll_drops(enemy_id: String, rng: RandomNumberGenerator = null) -> Array:
	var out: Array = []
	if not TABLES.has(enemy_id):
		return out
	var t: Dictionary = TABLES[enemy_id]
	var chance: float = float(t.get("drop_chance", 0.0))
	var count: int = int(t.get("drop_count", 1))
	var roll: float = (rng.randf() if rng != null else randf())
	if roll >= chance:
		return out
	for i in range(count):
		var rarity: int = _weighted_pick_int(t.get("rarity_weights", {}), RARITY_KEYS, RARITY_VALUES, rng)
		var slot_key: String = _weighted_pick_str(t.get("slot_weights", {}), rng)
		if slot_key == "":
			continue
		var item_id: String = _pick_item_for_slot(slot_key, rarity, rng)
		if item_id == "":
			continue
		out.append({"item_id": item_id, "rarity": rarity})
	return out

static func _weighted_pick_int(weights: Dictionary, keys: Array, values: Array, rng) -> int:
	var total: float = 0.0
	for k in keys:
		total += float(weights.get(k, 0))
	if total <= 0.0:
		return values[0]
	var pick: float = (rng.randf() if rng != null else randf()) * total
	var cumul: float = 0.0
	for i in keys.size():
		cumul += float(weights.get(keys[i], 0))
		if pick < cumul:
			return values[i]
	return values[values.size() - 1]

static func _weighted_pick_str(weights: Dictionary, rng) -> String:
	var total: float = 0.0
	for v in weights.values(): total += float(v)
	if total <= 0.0: return ""
	var pick: float = (rng.randf() if rng != null else randf()) * total
	var cumul: float = 0.0
	for k in weights.keys():
		cumul += float(weights[k])
		if pick < cumul:
			return String(k)
	return String(weights.keys()[weights.size() - 1])

# Filter items_db by slot key, then roll an item by per-item drop_weight.
# For unique/legendary rarity tiers, restrict to is_unique=true items in
# that slot. Falls back to rare-tier pool if no uniques exist.
static func _pick_item_for_slot(slot_key: String, rarity: int, rng) -> String:
	var pool: Array = _slot_pool(slot_key)
	if pool.is_empty():
		return ""
	var unique_only: bool = (rarity == LootDropScript.Rarity.UNIQUE
			or rarity == LootDropScript.Rarity.LEGENDARY)
	var filtered: Array = []
	var weights: Array = []
	for entry in pool:
		var meta: Resource = _meta_for(entry)
		if meta == null:
			continue
		if not bool(meta.can_drop):
			continue
		if unique_only and not bool(meta.is_unique):
			continue
		filtered.append(entry)
		weights.append(max(0.001, float(meta.drop_weight)))
	# Fall back to non-unique pool if nothing in this slot is flagged unique.
	if filtered.is_empty() and unique_only:
		for entry in pool:
			var meta2: Resource = _meta_for(entry)
			if meta2 == null or not bool(meta2.can_drop):
				continue
			filtered.append(entry)
			weights.append(max(0.001, float(meta2.drop_weight)))
	if filtered.is_empty():
		return ""
	# Weighted pick.
	var total: float = 0.0
	for w in weights: total += w
	var pick: float = (rng.randf() if rng != null else randf()) * total
	var cumul: float = 0.0
	for i in filtered.size():
		cumul += weights[i]
		if pick < cumul:
			return String(filtered[i]["id"])
	return String(filtered[filtered.size() - 1]["id"])

static func _slot_pool(slot_key: String) -> Array:
	var out: Array = []
	var cat: Array = ItemsDB.build_catalog()
	# Composite "mainhand_<class>" routing.
	if slot_key == "mainhand_melee":
		for e in cat:
			if int(e["slot"]) == ItemsDB.Slot.MAINHAND and int(e["weapon_class"]) == ItemsDB.WeaponClass.MELEE:
				out.append(e)
		return out
	if slot_key == "mainhand_ranged":
		for e in cat:
			if int(e["slot"]) == ItemsDB.Slot.MAINHAND and int(e["weapon_class"]) == ItemsDB.WeaponClass.RANGED:
				out.append(e)
		return out
	# Plain slot id matching by lowercased enum name.
	for e in cat:
		var enum_name: String = ItemsDB.Slot.keys()[int(e["slot"])].to_lower()
		if enum_name == slot_key:
			out.append(e)
	return out

static func _meta_for(entry: Dictionary) -> Resource:
	var slot_name: String = ItemsDB.Slot.keys()[int(entry["slot"])].to_lower()
	var path: String = "res://data/items/%s/%s.tres" % [slot_name, String(entry["id"])]
	if not FileAccess.file_exists(path):
		return null
	var r: Resource = load(path)
	if r is ItemMetadataScript:
		return r
	return null
