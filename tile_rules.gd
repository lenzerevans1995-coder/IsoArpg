extends RefCounted
class_name TileRules

# Centralised semantics for terrain tiles. Other systems (editor paint,
# player physics, chunk loader) consult this lib instead of hard-coding
# per-tile rules so we have one place to change behaviour.
#
# Tile family codes are the alphanumeric portion of a Fantasy tileset
# filename, e.g. "G16" from "Ground G16_E.png".

enum Role {
	GROUND,         # plain walkable surface (A-series ground tiles)
	HILL_LOW,       # 1-storey cliff edge / corner (G1-G15) — blocks passage,
	                # interior plateau is walkable on storey 1
	HILL_TALL,      # taller walkable hill (G16, G17) — character can walk up,
	                # walking on top puts them on storey 2
	CAVE_WALL,      # G18-G21 — solid wall, cave interior
	CAVE_DOOR,      # G22 — entrance, passable, transitions storey
	OVERLAY,        # decor, no movement effect
}

# Per-role lift height in pixels — measured from the texture art so the
# player visually stands on top of the tile, not somewhere up its cliff.
# G16/G17 are tall cliffs whose plateau surface sits ~195 px above ground
# in the source PNG (opaque bbox y=15..240 with the standard -82 offset),
# so HILL_TALL has to commit a lift higher than 2 * HILL_LIFT (128).
const LIFT_PX := {
	Role.GROUND: 0,
	Role.HILL_LOW: 64,        # standard 1-storey plateau
	Role.HILL_TALL: 0,        # G16 / G17 — no auto-lift. The visual cliff
	                          # is tall but the actual walkable plateau
	                          # height is set by the stair tool (S1-S4)
	                          # so the user can spread the climb across as
	                          # many cells as they want.
	Role.CAVE_WALL: 0,
	Role.CAVE_DOOR: 0,
	Role.OVERLAY: 0,
}

# Legacy alias kept so callers that still ask for storey count get the right
# integer. 64 px = 1 storey, anything else rounds up.
const STOREY_HEIGHT := {
	Role.GROUND: 0,
	Role.HILL_LOW: 1,
	Role.HILL_TALL: 3,
	Role.CAVE_WALL: 0,
	Role.CAVE_DOOR: 0,
	Role.OVERLAY: 0,
}

# Roles that block straight-line movement (the player can't enter the cell
# unless they're on a compatible storey or via a designated door).
const BLOCKING := {
	Role.HILL_LOW: true,    # cliff perimeter — only enter via ramp
	Role.CAVE_WALL: true,
}

# Returns the role for a given family code, e.g. "G16" -> HILL_TALL.
static func role_for_family(family_code: String) -> int:
	if family_code.length() < 2:
		return Role.GROUND
	var prefix := family_code.substr(0, 1)
	if prefix != "G":
		return Role.GROUND
	var n := family_code.substr(1).to_int()
	if n == 22:
		return Role.CAVE_DOOR
	if n >= 18 and n <= 21:
		return Role.CAVE_WALL
	if n == 16 or n == 17:
		return Role.HILL_TALL
	if n >= 1 and n <= 15:
		return Role.HILL_LOW
	return Role.OVERLAY

# Pulls the family code (e.g. "G16") out of a full tile path
# "res://assets/forest/elevation/dirt/Ground G16_E.png".
static func family_from_path(path: String) -> String:
	var stem := path.get_file().get_basename()   # "Ground G16_E"
	# Strip trailing _N/_S/_E/_W if present.
	if stem.length() > 2:
		var tail := stem.substr(stem.length() - 2, 2)
		if tail in ["_N", "_S", "_E", "_W"]:
			stem = stem.substr(0, stem.length() - 2)
	# Take the last whitespace-separated token: "Ground G16" -> "G16".
	var parts := stem.split(" ", false)
	if parts.size() == 0:
		return ""
	return parts[parts.size() - 1]

static func role_for_path(path: String) -> int:
	return role_for_family(family_from_path(path))

static func storey_for_path(path: String) -> int:
	return STOREY_HEIGHT.get(role_for_path(path), 0)

static func blocks_path(path: String) -> bool:
	return BLOCKING.get(role_for_path(path), false)
