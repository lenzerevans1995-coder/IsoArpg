extends Node
class_name AffixDB

# Affix catalog. Six baseline affixes (3 prefixes, 3 suffixes), each with
# tier-scaled value ranges and a small word table so we don't ship the
# same name on every dropped sword.
#
# Roll an affix:
#   var inst := AffixDB.roll("sharp", tier, rng)
# Returns an ItemAffix instance with rolled_value populated.

const ItemAffix := preload("res://loot/item_affix.gd")

# Affix definitions. Each entry:
#   "is_prefix":   bool — true=prefix, false=suffix
#   "stat":        String — what stat this modifies (informational; the
#                  consumer of the rolled item interprets this)
#   "words":       Array[String] — display-name variants. The roller
#                  picks one per item so identical affix-stat pairs read
#                  with subtle name variety.
#   "tiers":       Array[Dictionary] — index 0 = tier 1, etc.
#                  each: { "min": int, "max": int }
const ENTRIES := {
	# --- prefixes ---
	"sharp": {
		"is_prefix": true,
		"stat": "damage",
		"words": ["Sharp", "Honed", "Keen", "Jagged", "Cruel"],
		"tiers": [
			{"min": 1, "max": 3},
			{"min": 3, "max": 6},
			{"min": 6, "max": 10},
			{"min": 10, "max": 16},
			{"min": 16, "max": 25},
		],
	},
	"vicious": {
		# Multiplicative damage bonus — slots into the (1 + pct/100) term
		# of combat.compute_player_damage. Pairs with `sharp` (flat +damage).
		"is_prefix": true,
		"stat": "damage_pct",
		"words": ["Vicious", "Brutal", "Ruinous", "Savage", "Murderous"],
		"tiers": [
			{"min": 5, "max": 10},
			{"min": 10, "max": 20},
			{"min": 20, "max": 35},
			{"min": 35, "max": 55},
			{"min": 55, "max": 80},
		],
	},
	"sturdy": {
		"is_prefix": true,
		"stat": "armor",
		"words": ["Sturdy", "Reinforced", "Plated", "Iron-Bound", "Bulwark"],
		"tiers": [
			{"min": 2, "max": 5},
			{"min": 5, "max": 10},
			{"min": 10, "max": 18},
			{"min": 18, "max": 30},
			{"min": 30, "max": 50},
		],
	},
	"swift": {
		"is_prefix": true,
		"stat": "attack_speed_pct",
		"words": ["Swift", "Brisk", "Quickened", "Fleet", "Lightning"],
		"tiers": [
			{"min": 3, "max": 6},
			{"min": 6, "max": 10},
			{"min": 10, "max": 14},
			{"min": 14, "max": 18},
			{"min": 18, "max": 22},
		],
	},
	# --- suffixes ---
	"of_health": {
		"is_prefix": false,
		"stat": "max_hp",
		"words": ["of Health", "of Vigor", "of the Bear", "of Endurance", "of Vitality"],
		"tiers": [
			{"min": 5, "max": 10},
			{"min": 10, "max": 20},
			{"min": 20, "max": 35},
			{"min": 35, "max": 60},
			{"min": 60, "max": 100},
		],
	},
	"of_might": {
		"is_prefix": false,
		"stat": "strength",
		"words": ["of Might", "of the Ox", "of Strength", "of the Titan", "of the Giant"],
		"tiers": [
			{"min": 1, "max": 3},
			{"min": 3, "max": 5},
			{"min": 5, "max": 8},
			{"min": 8, "max": 12},
			{"min": 12, "max": 18},
		],
	},
	"of_wisdom": {
		"is_prefix": false,
		"stat": "energy",
		"words": ["of Wisdom", "of the Owl", "of the Mage", "of Intellect", "of the Sage"],
		"tiers": [
			{"min": 1, "max": 3},
			{"min": 3, "max": 5},
			{"min": 5, "max": 8},
			{"min": 8, "max": 12},
			{"min": 12, "max": 18},
		],
	},
}

# All prefix / suffix ids — handy for editor pickers.
static func prefix_ids() -> Array[String]:
	var out: Array[String] = []
	for id in ENTRIES.keys():
		if ENTRIES[id]["is_prefix"]:
			out.append(id)
	return out

static func suffix_ids() -> Array[String]:
	var out: Array[String] = []
	for id in ENTRIES.keys():
		if not ENTRIES[id]["is_prefix"]:
			out.append(id)
	return out

# Roll a value for the given affix at the given tier. Returns a fresh
# ItemAffix Resource with everything populated. Returns null if the
# affix id or tier is invalid.
static func roll(affix_id: String, tier: int, rng: RandomNumberGenerator = null) -> ItemAffix:
	if not ENTRIES.has(affix_id):
		return null
	var entry: Dictionary = ENTRIES[affix_id]
	var tiers: Array = entry["tiers"]
	var t_idx: int = clampi(tier - 1, 0, tiers.size() - 1)
	var range_def: Dictionary = tiers[t_idx]
	var lo: int = int(range_def["min"])
	var hi: int = int(range_def["max"])
	var v: int = lo
	if hi > lo:
		v = (rng.randi_range(lo, hi) if rng != null else randi_range(lo, hi))
	var inst := ItemAffix.new()
	inst.affix_id = affix_id
	inst.is_prefix = bool(entry["is_prefix"])
	inst.tier = t_idx + 1
	inst.rolled_value = v
	return inst

# Pick a display word for this affix. Items with the same affix
# shouldn't all read identically — picking randomly per item keeps the
# dropped-name pool varied.
static func word_for(affix_id: String, rng: RandomNumberGenerator = null) -> String:
	if not ENTRIES.has(affix_id):
		return affix_id
	var words: Array = ENTRIES[affix_id]["words"]
	if words.is_empty():
		return affix_id
	var i: int = (rng.randi() if rng != null else randi()) % words.size()
	return String(words[i])

# Stat key for an affix — caller maps it onto whatever stat container is
# in scope ("damage" -> weapon damage bonus, "max_hp" -> CharacterStats, etc.).
static func stat_for(affix_id: String) -> String:
	if not ENTRIES.has(affix_id):
		return ""
	return String(ENTRIES[affix_id]["stat"])
