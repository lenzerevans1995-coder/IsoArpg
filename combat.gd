extends RefCounted
class_name Combat

# Centralised damage calculation. Pure functions — no state — so it
# can be called from main.gd's strike sites without the player object
# needing to track yet another field.
#
# Slice formula:
#   final = (weapon_base + flat_dmg_affixes)
#         * (1 + pct_dmg_affixes / 100)
#         * (1 + stats.damage_bonus_pct() / 100)
#
# Affixes from rolled-on-pickup items aren't yet flowing through — the
# slice has no inventory pickup. The formula reads affix paths off the
# equipped item's `unique_fixed_affixes` (set in the item_editor for
# named uniques), so an equipped unique sword DOES roll its locked
# affixes. Magic / rare drops will plug in once pickup lands.

const ItemsDB := preload("res://items_db.gd")
const ItemMetadataScript := preload("res://loot/item_metadata.gd")

# Fist-fight fallback when no weapon is equipped (or the equipped
# weapon has unset base_damage in its .tres). Bumped to 10-18 so
# unarmed slice combat actually kills 30-HP skeletons in 2-3 swings.
const FIST_MIN := 10
const FIST_MAX := 18

# Compute one player melee swing's damage value.
# `stats`        : CharacterStats instance (or null — will skip Str bonus)
# `loadout`      : Dictionary as stored on the player (folder name + class)
# `rng`          : optional RandomNumberGenerator for reproducible rolls
static func compute_player_damage(stats, loadout: Dictionary, rng: RandomNumberGenerator = null) -> int:
	var folder: String = String(loadout.get("mainhand", ""))
	var meta: Resource = _meta_for_mainhand_folder(folder)
	var base_min: int = FIST_MIN
	var base_max: int = FIST_MAX
	var flat_bonus: int = 0
	var pct_bonus: float = 0.0
	if meta != null:
		var meta_max: int = int(meta.base_damage_max)
		# Items with unset / zero damage in their .tres fall back to
		# fist range — saves us hand-tuning all 32 weapon files just to
		# get a usable slice. Once weapon balance is real, set
		# base_damage_min/max in the editor and this branch picks them up.
		if meta_max > 0:
			base_min = max(1, int(meta.base_damage_min))
			base_max = max(base_min, meta_max)
		# Locked affixes on uniques.
		for aff in meta.unique_fixed_affixes:
			if aff == null:
				continue
			var stat: String = AffixDB.stat_for(String(aff.affix_id))
			match stat:
				"damage":
					flat_bonus += int(aff.rolled_value)
				"damage_pct":
					pct_bonus += float(aff.rolled_value)
	var roll: int = base_min if base_max <= base_min else (rng.randi_range(base_min, base_max) if rng != null else randi_range(base_min, base_max))
	var dmg: float = float(roll + flat_bonus) * (1.0 + pct_bonus / 100.0)
	if stats != null:
		dmg *= 1.0 + stats.damage_bonus_pct() / 100.0
	return int(round(max(1.0, dmg)))

# folder e.g. "Melee3" → "res://data/items/mainhand/melee_3.tres"
static func _meta_for_mainhand_folder(folder: String) -> Resource:
	if folder == "":
		return null
	var item_id: String = ""
	# PVGames sheets are named Melee1..MeleeN, Ranged1..N, Magic1..N. Strip
	# the digits and lowercase the type word.
	var rx := RegEx.new()
	rx.compile("^([A-Za-z]+)(\\d+)$")
	var m := rx.search(folder)
	if m == null:
		return null
	item_id = "%s_%s" % [m.get_string(1).to_lower(), m.get_string(2)]
	var path: String = "res://data/items/mainhand/%s.tres" % item_id
	if not FileAccess.file_exists(path):
		return null
	var r: Resource = load(path)
	if r is ItemMetadataScript:
		return r
	return null
