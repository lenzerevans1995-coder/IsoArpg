extends RefCounted
class_name EnemyDB

# Single source of truth for per-enemy gameplay numbers — XP reward,
# level, base damage / HP scalars, etc. Kill handlers look up by id
# (matches Skeleton.Kind enum values, plus goblin variants).
# Tune values here; combat code never hard-codes XP or level.

const ENTRIES := {
	# Tuning: this is the slice's L1→L5 dungeon. Total XP to hit L5 is
	# ~870 (XP curve in character_stats). A full clear of ~25 regulars
	# + 6 elites + boss should land the player around L5, not L8.
	# Skeleton commons — backbone of dungeon encounters.
	"skel_warrior":   {"name": "Skeleton Warrior",   "level": 4,  "xp": 6},
	"skel_archer":    {"name": "Skeleton Archer",    "level": 4,  "xp": 7},
	"skel_wizard":    {"name": "Skeleton Wizard",    "level": 5,  "xp": 9},
	# Skeleton elites — rarer, fatter rewards.
	"skel_brute":     {"name": "Brute",              "level": 8,  "xp": 50},
	"skel_dark_knight":{"name":"Dark Knight",        "level": 9,  "xp": 60},
	"skel_berserker": {"name": "Berserker",          "level": 9,  "xp": 55},
	"skel_dark_archer":{"name":"Dark Archer",        "level": 9,  "xp": 58},
	"skel_necromancer":{"name":"Necromancer",        "level": 10, "xp": 75},
	# Boss.
	"skel_deathlord": {"name": "Deathlord",          "level": 14, "xp": 200},
	# Forest goblins (open-world fights).
	"goblin":         {"name": "Goblin",             "level": 2,  "xp": 4},
	"goblin_archer":  {"name": "Goblin Archer",      "level": 3,  "xp": 5},
	"goblin_boss":    {"name": "Goblin Chieftain",   "level": 6,  "xp": 50},
}

static func get_entry(id: String) -> Dictionary:
	return ENTRIES.get(id, {})

static func xp_for(id: String) -> int:
	return int(ENTRIES.get(id, {}).get("xp", 0))

# XP scales with the player ↔ enemy level gap so over-levelled players
# stop farming low-tier mobs forever (similar progression dampener as
# the games that inspired this).
static func xp_for_kill(id: String, player_level: int) -> int:
	var entry: Dictionary = ENTRIES.get(id, {})
	var base: int = int(entry.get("xp", 0))
	var enemy_lvl: int = int(entry.get("level", 1))
	var diff: int = player_level - enemy_lvl
	var mult: float = 1.0
	if diff > 5:
		# Dwindle to zero by 10 levels above.
		mult = clampf(1.0 - float(diff - 5) * 0.2, 0.0, 1.0)
	elif diff < -5:
		# Bonus for killing 5+ levels above you. Capped tighter than
		# before (1.5x instead of 2.5x) so the L1 player one-shotting
		# a L14 boss doesn't get a full level's worth of XP.
		mult = clampf(1.0 + float(-diff - 5) * 0.08, 1.0, 1.5)
	return int(round(float(base) * mult))

# Resolve a Skeleton.Kind enum value or a goblin/boss flag into the
# matching ENTRIES key. Falls back to "" if unknown.
static func id_for_skeleton_kind(kind: int) -> String:
	# Mirrors skeleton.gd's Kind enum order. Keep in sync.
	match kind:
		0: return "skel_warrior"      # Kind.WARRIOR
		1: return "skel_archer"       # Kind.ARCHER
		2: return "skel_wizard"       # Kind.WIZARD
		3: return "skel_brute"        # Kind.BRUTE
		4: return "skel_deathlord"    # Kind.DEATHLORD
		5: return "skel_dark_knight"  # Kind.DARK_KNIGHT
		6: return "skel_berserker"    # Kind.BERSERKER
		7: return "skel_dark_archer"  # Kind.DARK_ARCHER
		8: return "skel_necromancer"  # Kind.NECROMANCER
		_: return ""
