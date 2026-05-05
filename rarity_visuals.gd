extends RefCounted
class_name RarityVisuals

# Single source of truth for rarity colors. Indices reference
# data/swatch_palette.json (the project's 81-swatch palette).
# Loot beams, world-drop modulate, inventory icon glow, and tooltip
# name-coloring all pull from here so the game reads consistently.

enum Rarity { COMMON, MAGIC, RARE, UNIQUE, LEGENDARY }

# Palette index per rarity. Picked from data/swatch_palette.json:
#   0  #f5f5f5  white
#   33 #1854a1  deep blue
#   55 #efd834  yellow-gold
#   58 #dc740b  orange
#   49 #c60024  red
const PALETTE_INDEX := {
	Rarity.COMMON:    0,
	Rarity.MAGIC:     33,
	Rarity.RARE:      55,
	Rarity.UNIQUE:    58,
	Rarity.LEGENDARY: 49,
}

# Glow strength multiplier per tier — drives icon-glow alpha and beam
# intensity. Common gets no glow at all.
const GLOW_STRENGTH := {
	Rarity.COMMON:    0.0,
	Rarity.MAGIC:     0.4,
	Rarity.RARE:      0.6,
	Rarity.UNIQUE:    0.8,
	Rarity.LEGENDARY: 1.0,
}

const PALETTE_PATH := "res://data/swatch_palette.json"
static var _palette_cache: Array = []

static func _palette() -> Array:
	if not _palette_cache.is_empty():
		return _palette_cache
	if FileAccess.file_exists(PALETTE_PATH):
		var f := FileAccess.open(PALETTE_PATH, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Array:
			_palette_cache = parsed
	return _palette_cache

static func color_for(rarity: int) -> Color:
	var idx: int = int(PALETTE_INDEX.get(rarity, 0))
	var pal: Array = _palette()
	if idx >= 0 and idx < pal.size():
		return Color(String(pal[idx]))
	return Color(1, 1, 1, 1)

static func glow_strength(rarity: int) -> float:
	return float(GLOW_STRENGTH.get(rarity, 0.0))

# Convenience: full Color with alpha pre-set for beam draw (alpha is
# applied by the caller per visual layer — glow / mid / core).
static func beam_color(rarity: int) -> Color:
	return color_for(rarity)
