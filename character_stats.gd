extends RefCounted
class_name CharacterStats

# Player stat container — holds primary attributes, current resources,
# level + XP, and recomputes derived stats whenever an attribute or
# level changes. Inspired by the Diablo 2 stat layout (Str/Dex/Vit/Eng)
# but the curve and per-point bonuses are our own tuning so we can
# adjust them without dragging in proprietary numbers.

signal level_changed(new_level: int)
signal xp_changed(current: int, needed: int)
signal hp_changed(hp: int, max_hp: int)
signal mp_changed(mp: int, max_mp: int)

# Class id ("warrior", "rogue", ...). Used for class-specific bonuses
# and SkillDB lookups.
var character_class: String = "warrior"
var character_name: String = "Hero"

# Primary attributes (allocated each level + bought via stat points).
# Slice baseline (warrior): Str/Vit drive damage and HP.
# Dex / Energy are stubbed for the slice — allocation works in the
# panel but they have no gameplay effect yet.
# TODO: post-slice — Dex wires into attack speed, dodge chance, ranged damage.
# TODO: post-slice — Energy wires into max MP scaling, magic damage.
var strength: int = 10
var dexterity: int = 5
var vitality: int = 10
var energy: int = 5

# Level / XP.
var level: int = 1
var xp: int = 0
var unspent_stat_points: int = 0
var unspent_skill_points: int = 0

# Resource state — current values, derived max recomputed elsewhere.
var hp: int = 0
var mp: int = 0

func _init(class_id: String = "warrior") -> void:
	character_class = class_id
	# Class kit defaults (subtle differences so each class isn't identical).
	match class_id:
		"warrior":
			strength = 10; dexterity = 5; vitality = 10; energy = 5
		"rogue":
			strength = 7; dexterity = 12; vitality = 8; energy = 5
		"sorcerer":
			strength = 5; dexterity = 5; vitality = 7; energy = 15
		_:
			strength = 8; dexterity = 8; vitality = 8; energy = 8
	hp = max_hp()
	mp = max_mp()

# ---- derived stats ---------------------------------------------------

func max_hp() -> int:
	# Slice formula: base + (vit * 5).
	# Warrior baseline: 50 + 10*5 = 100 HP at level 1.
	# Each Vit point spent: +5 HP. 5 stat points/level → +25 HP if
	# fully invested in Vit, 0 HP if invested elsewhere.
	# Bumped warrior baseline 50 → 80 so the slice's L1 player has more
	# breathing room against multi-skeleton aggro. Still grows linearly
	# with Vit so allocation stays meaningful.
	var base: int = 60
	match character_class:
		"warrior":  base = 80
		"rogue":    base = 60
		"sorcerer": base = 50
	return base + vitality * 5

func max_mp() -> int:
	# Slice: Energy is stubbed but allocation should still grow MP a
	# bit so the orb visibly responds. Warrior baseline 50 + 5*0 = 50.
	# TODO: post-slice — replace with proper magic-damage / mana-cost
	# formula once spell-class skills exist.
	var base: int = 50
	if character_class == "sorcerer":
		base = 70
	return base + energy * 2

func attack_rating() -> int:
	return 5 * dexterity + 5 * level

func defense() -> int:
	return dexterity + level * 2

func damage_bonus_pct() -> float:
	# Strength scales weapon damage. 1% per point, capped at 200%.
	return clampf(float(strength), 0.0, 200.0)

# ---- XP / level ------------------------------------------------------

# XP cost formula — designed to feel like a classic isometric ARPG
# where early levels fly by and late levels stretch. Polynomial keeps
# the curve smooth instead of using a hand-baked table.
#   level 1→2:  about 100
#   level 10:   ~10k
#   level 30:   ~600k
#   level 60:   ~12M
#   level 99:   ~150M (asymptotic feel)
const XP_BASE := 80.0
const XP_GROWTH_LIN := 1.18      # base exponential ramp
const XP_GROWTH_HIGH := 1.06     # slightly different exponent past 60
const XP_HIGH_THRESHOLD := 60

static func xp_for_level(target_level: int) -> int:
	# Returns the TOTAL xp required to reach `target_level` from 0.
	# level 1 = 0 xp; level 2 = first cost; etc.
	if target_level <= 1:
		return 0
	var total: float = 0.0
	for L in range(1, target_level):
		total += _xp_step(L)
	return int(round(total))

static func _xp_step(from_level: int) -> float:
	# XP needed to go from `from_level` → `from_level + 1`.
	var ratio: float = XP_GROWTH_LIN
	if from_level >= XP_HIGH_THRESHOLD:
		ratio = XP_GROWTH_HIGH
	return XP_BASE * pow(ratio, from_level - 1) * (1.0 + float(from_level) * 0.4)

func xp_to_next_level() -> int:
	return xp_for_level(level + 1) - xp

func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp += amount
	# Cascade level-ups in case the kill granted enough for multiple.
	while xp >= xp_for_level(level + 1) and level < 99:
		level += 1
		unspent_stat_points += 5
		unspent_skill_points += 1
		hp = max_hp()
		mp = max_mp()
		emit_signal("level_changed", level)
		emit_signal("hp_changed", hp, max_hp())
		emit_signal("mp_changed", mp, max_mp())
	emit_signal("xp_changed", xp, xp_for_level(level + 1))

func damage_taken(amount: int) -> void:
	hp = max(0, hp - amount)
	emit_signal("hp_changed", hp, max_hp())

func heal(amount: int) -> void:
	hp = min(max_hp(), hp + amount)
	emit_signal("hp_changed", hp, max_hp())

func spend_mp(amount: int) -> bool:
	if mp < amount:
		return false
	mp -= amount
	emit_signal("mp_changed", mp, max_mp())
	return true
