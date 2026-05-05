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
var strength: int = 30
var dexterity: int = 20
var vitality: int = 25
var energy: int = 10

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
			strength = 30; dexterity = 20; vitality = 25; energy = 10
		"rogue":
			strength = 20; dexterity = 30; vitality = 20; energy = 15
		"sorcerer":
			strength = 15; dexterity = 18; vitality = 18; energy = 35
		_:
			strength = 25; dexterity = 25; vitality = 25; energy = 25
	hp = max_hp()
	mp = max_mp()

# ---- derived stats ---------------------------------------------------

func max_hp() -> int:
	# Pure stat-driven: vitality is the only growth knob. Tuned so a
	# warrior starts at ~100 HP at level 1 (Vit 25, base 50) and each
	# Vit point gives +2 HP. Level grants 5 stat points; spending them
	# into Vit gives +10 HP per level — visible but not free.
	var base: int = 40
	match character_class:
		"warrior":  base = 50
		"rogue":    base = 35
		"sorcerer": base = 25
	return base + vitality * 2

func max_mp() -> int:
	# Same shape as HP. Warrior starts ~50 MP (Energy 10, base 30).
	# Sorcerer doubles per-point return so the class still feels
	# mana-rich at high investment.
	var base: int = 30
	var energy_mult: int = 2
	if character_class == "sorcerer":
		base = 30
		energy_mult = 4
	return base + energy * energy_mult

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
