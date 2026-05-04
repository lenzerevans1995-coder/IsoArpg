extends Node
class_name Loadout

# Persistent character loadout. Maps slot enum -> item_id (or "" for empty).
# Saved to user://profile.json so the character creator carries over between runs.

const SAVE_PATH := "user://profile.json"

static func default_loadout() -> Dictionary:
	return {
		"body": "NakedBody",
		"head": "Head1",
		"hands": "Hands1",
		"chest": "Chest1",
		"legs": "Legs1",
		"shoes": "Shoes1",
		"belt": "",
		"bag": "",
		"offhand": "",
		"mainhand": "",
		"mainhand_class": ItemsDB.WeaponClass.NONE,
		"mount": "",
		"shadow": "Shadow",
		"vfx": "",
		"tints": _default_tints(),
	}

# Per-layer color palettes + default tint. Source sheets are greyscale templates;
# Unity's character creator multiplied a color over them at runtime, and we mirror
# that here. Colors are stored as html strings in the saved profile so JSON is
# round-trippable.
# Each slot is just one Color multiply over a greyscale sprite — confirmed by
# extracting the original Unity GearPresetDatabase. Sprites are pre-separated
# (head = just hair, body = skin/face, chest = just torso cloth) so a single
# tint per slot works cleanly without masks.
#
# Palettes here are aggregated from the 15 shipped presets (gear_presets.json)
# plus a few extras to give meaningful per-slot choice.
const PALETTE := {
	"body":  ["#e6bc98", "#d4aa78", "#a16e4b", "#825c3b", "#5a3823", "#ffe7d1", "#bbe1f4", "#415d10", "#9e001c", "#f7c200"],
	"head":  ["#993f00", "#3a3a3a", "#6c5231", "#d0bfa1", "#825c3b", "#3a77a3", "#dddddd", "#77000f", "#b2b2b2"],
	"chest": ["#b2b2b2", "#3a3a3a", "#d6a725", "#d0bfa1", "#466776", "#283f51", "#825c3b", "#dddddd", "#77000f", "#48063e", "#415d10"],
	"legs":  ["#b2b2b2", "#3a3a3a", "#d6a725", "#d0bfa1", "#825c3b", "#3a5b6a", "#607b55", "#dddddd", "#2b1730", "#697191", "#4c3b30", "#415d10"],
	"shoes": ["#b2b2b2", "#47301e", "#3a3a3a", "#825c3b", "#283f51", "#d6a725", "#607b55"],
	"hands": ["#b2b2b2", "#3a3a3a", "#d6a725", "#6c5231", "#283f51", "#77000f", "#80ba24", "#466776", "#ae3b16", "#ffffff"],
	"belt":  ["#466776", "#5e1145", "#e5dabe", "#825c3b", "#77000f", "#676767", "#3a3a3a", "#030101", "#00316b", "#652419"],
	"bag":   ["#ffffff", "#905937", "#3d3d3d"],
}

const PRESETS_PATH := "res://gear_presets.json"
static var _presets_cache: Array = []

static func presets() -> Array:
	if _presets_cache.is_empty() and FileAccess.file_exists(PRESETS_PATH):
		var f := FileAccess.open(PRESETS_PATH, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Array:
			_presets_cache = parsed
	return _presets_cache

# Apply a numbered preset (0-14) to a loadout's tints in-place.
static func apply_preset(loadout: Dictionary, preset_index: int) -> void:
	var ps := presets()
	if preset_index < 0 or preset_index >= ps.size():
		return
	var preset: Dictionary = ps[preset_index]
	var tints: Dictionary = loadout.get("tints", {})
	# Map preset keys (Unity field names) -> our layer names.
	var key_map := {
		"body": "body", "head": "head", "chest": "chest", "legs": "legs",
		"shoes": "shoes", "hands": "hands", "belt": "belt", "backpack": "bag",
	}
	for src in key_map.keys():
		if preset.has(src):
			tints[key_map[src]] = preset[src]
	loadout["tints"] = tints

static func palette_for(layer: String) -> Array:
	if PALETTE.has(layer):
		var arr: Array = []
		for hex in PALETTE[layer]:
			arr.append(Color(hex))
		return arr
	return [Color.WHITE]

static func _default_tints() -> Dictionary:
	# Default to preset 0 (the shipped Unity default look).
	var d := {}
	var ps := presets()
	if not ps.is_empty():
		var p: Dictionary = ps[0]
		var key_map := {"body":"body","head":"head","chest":"chest","legs":"legs","shoes":"shoes","hands":"hands","belt":"belt","backpack":"bag"}
		for src in key_map.keys():
			if p.has(src):
				d[key_map[src]] = p[src]
	# Fill any missing layers with first palette swatch.
	for layer in PALETTE.keys():
		if not d.has(layer):
			d[layer] = palette_for(layer)[0].to_html()
	return d

static func save(loadout: Dictionary) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Loadout: cannot open %s for write" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(loadout))

static func load_or_default() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return default_loadout()
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return default_loadout()
	var raw := f.get_as_text()
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return default_loadout()
	# Merge over defaults so missing keys don't break anything.
	var out := default_loadout()
	for k in parsed.keys():
		out[k] = parsed[k]
	return out

# Apply a loadout to a LayeredCharacter. The loadout values are sheet folder
# names (e.g. "Chest3"), which map directly onto LayeredCharacter.equip().
static func apply(character: LayeredCharacter, loadout: Dictionary) -> void:
	character.equip("shadow", loadout.get("shadow", ""))
	character.equip("mount", loadout.get("mount", ""))
	character.equip("body", loadout.get("body", ""))
	character.equip("legs", loadout.get("legs", ""))
	character.equip("shoes", loadout.get("shoes", ""))
	character.equip("chest", loadout.get("chest", ""))
	character.equip("belt", loadout.get("belt", ""))
	character.equip("bag", loadout.get("bag", ""))
	character.equip("hands", loadout.get("hands", ""))
	character.equip("head", loadout.get("head", ""))
	character.equip("offhand", loadout.get("offhand", ""))
	character.equip("mainhand", loadout.get("mainhand", ""))
	character.equip("vfx", loadout.get("vfx", ""))
	# Apply per-layer color tints (modulate). Stored as html strings for JSON.
	var tints: Dictionary = loadout.get("tints", {})
	for layer in tints.keys():
		character.set_tint(layer, Color(tints[layer]))
