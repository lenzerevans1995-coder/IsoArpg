extends Node2D
class_name Goblin

# A scrappy melee or ranged goblin enemy. Drives its own 8-direction
# Fantasy-tileset spritesheets (Idle / Run / Attack* / Die / TakeDamage)
# loaded from assets/charachters/Sprites/goblins/goblin_<n>/.
#
# AI:
#   - Idle until they spot the player.
#   - Melee variants close to attack_range and swing on cooldown,
#     stuttering left/right so they don't bunch up.
#   - Archer keeps a desired_range gap, kites if the player closes,
#     fires a Special1/Attack2 anim with a deferred ranged hit.
#   - Spreads damage over a windup so the player can react.

const FRAME_W := 128
const FRAME_H := 128
const COLS := 15
const ROWS := 8
const DEFAULT_FPS := 12.0
const ATTACK_FPS := 18.0

# Direction index (0=E, CCW going through SE/S/SW/W/NW/N/NE).
const DIR_VECS := [
	Vector2( 1,  0),         # 0 E
	Vector2( 0.7,  0.5),     # 1 SE (iso south-east on screen)
	Vector2( 0,  1),         # 2 S
	Vector2(-0.7, 0.5),      # 3 SW
	Vector2(-1, 0),          # 4 W
	Vector2(-0.7,-0.5),      # 5 NW
	Vector2( 0, -1),          # 6 N
	Vector2( 0.7,-0.5),      # 7 NE
]

@export var goblin_kind: int = 1   # 1, 2, 3 (archer), or 4 (boss)
@export var max_hp: int = 28
@export var damage: int = 6
@export var move_speed: float = 130.0
@export var attack_range: float = 56.0
@export var desired_range: float = 0.0   # archer only — keeps gap
@export var attack_cooldown: float = 1.0
@export var attack_windup: float = 0.4
@export var ranged: bool = false
@export var is_boss: bool = false
@export var aoe_attack_range: float = 96.0  # boss slam radius
# Boss-only state. Enrage triggers under enrage_hp_threshold * max_hp; below
# that the boss flashes red, gets a speed/cooldown buff, and unlocks a
# stronger ranged-slam special on a longer cooldown.
@export var enrage_hp_threshold: float = 0.5
# Body collision shape — drives push-collision (player & peer) AND is
# read by arrows for hit detection. Boss multiplies the radius ×1.6.
@export var body_offset: Vector2 = Vector2(0, -32) :
	set(v):
		body_offset = v
		if _body_shape: _body_shape.position = v
@export var body_radius: float = 28.0 :
	set(v):
		body_radius = v
		_apply_body_radius()

const COLLISION_LAYER_PLAYER: int = 1
const COLLISION_LAYER_ENEMY: int = 2

var body_area: Area2D = null
var attack_area: Area2D = null
var _body_shape: CollisionShape2D = null
var _body_circle: CircleShape2D = null
var _attack_shape: CollisionShape2D = null
var _attack_circle: CircleShape2D = null

var enraged: bool = false
var _special_timer: float = 0.0
const BOSS_SPECIAL_COOLDOWN := 4.0

# Pack coordination: only N goblins commit to the inner attack ring at a
# time. The rest hold an outer orbit so the player isn't dogpiled.
@export var max_committed_attackers: int = 2
const SEPARATION_RADIUS := 64.0      # personal-bubble radius for clumping avoid
const ORBIT_RADIUS := 110.0          # outer-ring distance when not committed
const ATTACK_FACING_LERP := 12.0     # snappy face-to-target during attacks

var hp: int
var dead: bool = false
var target: Node2D = null
var _sprite: Sprite2D
var _anim_path_cache: Dictionary = {}   # anim_name -> Texture2D
var _current_anim: String = ""
var _frame_t: float = 0.0
var _frame_count: int = COLS
var _direction: int = 2
var _attack_timer: float = 0.0
var _windup_left: float = 0.0
var _strafe_left: float = 0.0
var _strafe_dir: float = 1.0
var _hit_flash_left: float = 0.0
var _hit_flash_color: Color = Color(1.5, 0.6, 0.6)
var _anim_locked_until: float = 0.0
signal died(goblin)

func _ready() -> void:
	hp = max_hp
	_setup_collision_shapes()
	_sprite = Sprite2D.new()
	_sprite.centered = true
	_sprite.region_enabled = true
	# 64x64 demo: 128px source frames -> 0.5 = 64. Boss kept slightly
	# larger (0.6 -> ~77) so it reads as a boss without breaking the
	# tile-aligned silhouette of regular grunts.
	_sprite.scale = Vector2(0.5, 0.5) if goblin_kind <= 2 else Vector2(0.6, 0.6)
	_sprite.offset = Vector2(0, -42)   # foot anchor so y-sort lines up
	add_child(_sprite)
	# Global enemy rule: +1 above parent tile layer so tall grass / flora
	# tiles never swallow the silhouette. Player uses the same lift so
	# the two still y-sort against each other on equal footing.
	z_index = 1
	z_as_relative = true
	_play("Idle", DEFAULT_FPS, true)

var _outline_node: Node2D = null

class _OutlineRing extends Node2D:
	# Pixel-art iso ellipse: traces the 2:1 ring on a coarse pixel grid
	# (snaps every point to PIXEL_SNAP-sized blocks) and draws each
	# segment as a small filled rect — looks chunky / blocky to match
	# the rest of the game's pixel aesthetic.
	var radius: float = 32.0
	const PIXEL_SNAP := 2.0
	func _draw() -> void:
		var seg: int = 64
		var col := Color(1.0, 0.18, 0.18, 1.0)
		var seen := {}
		for i in range(seg):
			var a: float = float(i) / float(seg) * TAU
			var x: float = cos(a) * radius
			var y: float = sin(a) * radius * 0.5
			var sx: int = int(round(x / PIXEL_SNAP)) * int(PIXEL_SNAP)
			var sy: int = int(round(y / PIXEL_SNAP)) * int(PIXEL_SNAP)
			var key := Vector2i(sx, sy)
			if seen.has(key):
				continue
			seen[key] = true
			draw_rect(Rect2(Vector2(sx, sy) - Vector2(PIXEL_SNAP * 0.5, PIXEL_SNAP * 0.5),
					Vector2(PIXEL_SNAP, PIXEL_SNAP)), col, true)

const HIGHLIGHT_TEX_PATH := "res://assets/drops/highlight/highlight_yellow.png"

func _ensure_outline() -> void:
	# Hover highlight uses the shipped assets/drops/highlight asset
	# recoloured red for enemies. Replaces the previous procedural
	# pixel-ring. Boss gets a larger scale so the silhouette reads.
	if _outline_node and is_instance_valid(_outline_node):
		return
	var s := Sprite2D.new()
	if ResourceLoader.exists(HIGHLIGHT_TEX_PATH):
		s.texture = load(HIGHLIGHT_TEX_PATH)
	s.centered = true
	s.modulate = Color(1.4, 0.30, 0.30, 0.9)   # red enemy tint
	# Slightly larger than body so the ring reads outside the silhouette.
	s.scale = Vector2(2.4, 2.4) if is_boss else Vector2(1.6, 1.6)
	s.position = Vector2(0, -4)
	s.z_index = -1
	add_child(s)
	_outline_node = s

func _clear_outline() -> void:
	if _outline_node and is_instance_valid(_outline_node):
		_outline_node.queue_free()
	_outline_node = null

func _sync_outline() -> void:
	pass   # ring doesn't need per-frame sync

func _kind_folder() -> String:
	# Asset folders are goblin_1 / 2 / 3 / boss — kind 4 (or anything
	# flagged as boss) reads from goblin_boss instead of goblin_4 (which
	# doesn't exist; that's why kind 4 was rendering invisible before).
	if goblin_kind == 4 or is_boss:
		return "goblin_boss"
	if goblin_kind <= 0:
		return "goblin_1"
	return "goblin_%d" % goblin_kind

func _anim_tex(anim: String) -> Texture2D:
	if _anim_path_cache.has(anim):
		return _anim_path_cache[anim]
	var path := "res://assets/charachters/Sprites/goblins/%s/%s.png" % [_kind_folder(), anim]
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_anim_path_cache[anim] = tex
	return tex

func _play(anim: String, fps: float, looping: bool, locked_dur: float = 0.0) -> void:
	# Don't restart the animation if it's already playing — only reset
	# frame_t when the anim actually changes. Otherwise Run/Idle would
	# stay frozen on frame 0 because every _process call re-requested
	# the same anim and snapped frame_t back to zero.
	if _current_anim == anim and locked_dur <= 0.0:
		return
	var tex := _anim_tex(anim)
	if tex == null:
		if anim != "Idle":
			_play("Idle", DEFAULT_FPS, true)
		return
	_sprite.texture = tex
	_current_anim = anim
	_frame_t = 0.0
	_frame_count = COLS
	if locked_dur > 0.0:
		_anim_locked_until = locked_dur
	_update_region()

func _update_region() -> void:
	var col: int = int(floor(_frame_t)) % _frame_count
	var row: int = clampi(_direction, 0, ROWS - 1)
	_sprite.region_rect = Rect2(col * FRAME_W, row * FRAME_H, FRAME_W, FRAME_H)

func _process(delta: float) -> void:
	if dead:
		_frame_t += delta * DEFAULT_FPS
		_update_region()
		return
	if _hit_flash_left > 0.0:
		_hit_flash_left -= delta
		_sprite.modulate = _hit_flash_color if _hit_flash_left > 0.0 else _base_modulate()
	else:
		_sprite.modulate = _base_modulate()
	# Hover-only outline: red iso ring whenever the cursor is over this
	# goblin. Tab targeting was removed — hover IS the target.
	var main2 := get_tree().root.get_node_or_null("Main")
	var is_target: bool = main2 != null and main2.get("_hovered_enemy") == self
	if is_target:
		_ensure_outline()
	else:
		_clear_outline()
	_special_timer = max(0.0, _special_timer - delta)
	_attack_timer = max(0.0, _attack_timer - delta)
	_anim_locked_until = max(0.0, _anim_locked_until - delta)
	_strafe_left = max(0.0, _strafe_left - delta)

	var fps: float = ATTACK_FPS if _current_anim.begins_with("Attack") else DEFAULT_FPS
	_frame_t += delta * fps
	_update_region()

	# Windup → land hit at the tail of the attack anim.
	if _windup_left > 0.0:
		_windup_left -= delta
		if _windup_left <= 0.0:
			_land_attack()

	if target == null or not is_instance_valid(target):
		return

	# Aim at the player's visible body (foot + body_offset), not the
	# foot dot. Otherwise a ring of goblins forms around an invisible
	# spot at ground level and the player sprite floats above the
	# circle of attackers. With body-targeting the goblins surround
	# the visible torso.
	var p_body_off: Vector2 = target.get("body_offset") if "body_offset" in target else Vector2.ZERO
	var target_pos: Vector2 = target.global_position + p_body_off
	var to_target: Vector2 = target_pos - global_position
	var dist := to_target.length()
	_direction = _vec_to_dir(to_target)

	# Locked while attacking — let the swing play out, but keep facing
	# the target so the swing animation lines up.
	if _anim_locked_until > 0.0:
		return

	# Archer: kite if too close. Hold fire until clear of melee ring.
	var min_keep: float = desired_range if ranged else 0.0
	if ranged and dist < min_keep:
		var away_vec := (-to_target.normalized()).normalized()
		_step_movement(away_vec * move_speed * 0.9, delta)
		if _last_move_velocity > 0.0:
			_play("Run", DEFAULT_FPS, true)
		else:
			_play("Idle", DEFAULT_FPS, true)
		_committed = false
		return
	# Pack-orbit logic removed — goblins now overlap freely (no peer
	# separation), so every melee goblin commits to the attack ring as
	# soon as they're in reach. Previously a `max_committed_attackers`
	# cap kept extras in an outer orbit, but combined with the no-overlap
	# rule it left the back of the pack running forever in place.

	# Use the AttackArea overlap to decide if we're actually in melee
	# reach. This respects body_offset/body_radius shapes on both the
	# goblin and the player so swings register at body-height instead
	# of foot-to-foot like the old `dist > attack_range` math.
	if not player_in_attack_range(target):
		# Commit: push toward the player with a slight strafe so two
		# goblins don't trace the exact same line, plus separation so
		# they don't overlap each other.
		var dir_vec := to_target.normalized()
		if _strafe_left <= 0.0:
			_strafe_dir = -1.0 if randf() < 0.5 else 1.0
			_strafe_left = randf_range(0.4, 1.1)
		var perp := Vector2(-dir_vec.y, dir_vec.x) * _strafe_dir
		var v := (dir_vec * 1.0 + perp * 0.35 + _separation_force()).normalized() * move_speed
		_step_movement(v, delta)
		# If _step_movement rejected the move (blocked by player body /
		# wall), _last_move_velocity decays to 0 — show Idle instead of
		# a static Run frame pointing the wrong way.
		if _last_move_velocity > 0.0:
			_play("Run", DEFAULT_FPS, true)
		else:
			_play("Idle", DEFAULT_FPS, true)
		_committed = true
		return

	_committed = true
	if is_boss and _special_timer <= 0.0 and _attack_timer <= 0.0:
		_start_boss_slam()
	elif _attack_timer <= 0.0:
		_start_attack()
	else:
		# Cooldown wait: hold Idle steadily. Even if separation produces
		# a tiny step every few frames, we keep the anim consistent so
		# the pack doesn't flicker Run/Idle next to each other.
		_step_movement(_separation_force() * move_speed * 0.3, delta)
		_play("Idle", DEFAULT_FPS, true)

var _committed: bool = false
# Tracks last-known move distance to smooth Run vs Idle picks. Without
# this, packs that orbit at the attack-ring edge spam _play("Run") and
# _play("Idle") on consecutive frames as their _step_movement happens to
# zero out, which resets the anim every frame and looks glitchy.
var _last_move_velocity: float = 0.0
const RUN_TO_IDLE_DELAY := 0.18   # seconds of standstill before idle

# Peer separation removed — goblins are allowed to fully overlap each
# other so a pack can converge on the player without jamming up. The
# only hard collision left in _step_movement is "don't enter the
# player's body". Returning ZERO here keeps existing call-sites that
# add this into their move vector working without any push effect.
func _separation_force() -> Vector2:
	return Vector2.ZERO

# Line-of-sight test from this goblin to a target. Sweeps along the segment
# at iso-cell granularity and returns false if any cell is blocked. Used by
# the archer so it doesn't waste arrows shooting through walls.
func _has_line_of_sight(to_pos: Vector2) -> bool:
	var main := get_tree().root.get_node_or_null("Main")
	if main == null or not main.has_method("is_blocked"):
		return true
	var diff: Vector2 = to_pos - global_position
	var steps: int = max(1, int(diff.length() / 32.0))
	for i in range(1, steps):
		var t: float = float(i) / float(steps)
		var p: Vector2 = global_position + diff * t
		var c: Vector2i = main._screen_to_grid(p) if main.has_method("_screen_to_grid") else Vector2i.ZERO
		if main.is_blocked(c):
			return false
		if main.terrain_lift and main.terrain_lift.is_blocked_at_pos(p):
			return false
	return true

func _setup_collision_shapes() -> void:
	# Body shape — used by player push-collision, peer separation, and
	# arrow hit detection. Boss radius is multiplied ×1.6.
	body_area = Area2D.new()
	body_area.name = "BodyArea"
	body_area.collision_layer = COLLISION_LAYER_ENEMY
	body_area.collision_mask = 0
	body_area.monitorable = true
	body_area.monitoring = false
	add_child(body_area)
	_body_shape = CollisionShape2D.new()
	_body_shape.position = body_offset
	_body_circle = CircleShape2D.new()
	_apply_body_radius()
	_body_shape.shape = _body_circle
	body_area.add_child(_body_shape)

	# Solid footprint — StaticBody on physics layer 1 so the player's
	# move_and_slide is blocked by the goblin instead of walking through
	# it. Child of the goblin Node2D so it follows position.
	var solid := StaticBody2D.new()
	solid.name = "SolidBody"
	solid.collision_layer = 1
	solid.collision_mask = 0
	add_child(solid)
	var solid_shape := CollisionShape2D.new()
	# Full-body capsule covering the rendered silhouette feet-to-head,
	# not just a foot disc. Boss is bumped to keep the wider footprint.
	var solid_caps := CapsuleShape2D.new()
	solid_caps.radius = 14.0 * (1.6 if is_boss else 1.0)
	solid_caps.height = 36.0
	solid_shape.position = Vector2(0, -32)
	solid_shape.shape = solid_caps
	solid.add_child(solid_shape)

	# Attack reach is computed mathematically in player_in_attack_range
	# (foot-to-foot + summed body radii). The old AttackArea CollisionShape
	# was leftover from an earlier overlap-based design and only served to
	# render a second debug circle in the editor — removed.

func _apply_body_radius() -> void:
	if _body_circle == null:
		return
	_body_circle.radius = body_radius * (1.6 if is_boss else 1.0)

# Returns true if the player is currently inside this goblin's attack
# reach. Uses GROUND distance (foot-to-foot) plus the player's body
# radius — Area2D overlap math factors in vertical shape offsets which
# breaks when characters have different body heights (player torso at
# y=-110, goblin at y=-32). Ground distance is the right metric for
# iso melee since both characters stand on the same plane.
func player_in_attack_range(player: Node) -> bool:
	if player == null or not is_instance_valid(player) or not (player is Node2D):
		return false
	var p2d: Node2D = player as Node2D
	var p_body_off: Vector2 = p2d.get("body_offset") if "body_offset" in p2d else Vector2.ZERO
	# Distance from goblin foot to the player's BODY centre (ground +
	# body_offset). The chase target is also the body, so this matches
	# where the goblin actually parks at the end of the chase.
	var dist_to_body: float = global_position.distance_to(p2d.global_position + p_body_off)
	var p_radius: float = p2d.body_radius if "body_radius" in p2d else 24.0
	return dist_to_body < attack_range + p_radius

const PEER_BODY_RADIUS := 28.0     # how close two goblins are allowed to stand

func _step_movement(velocity: Vector2, delta: float) -> void:
	var step := velocity * delta
	var next_pos := global_position + step
	var main := get_tree().root.get_node_or_null("Main")
	if main and main.has_method("is_blocked"):
		var cell: Vector2i = main._screen_to_grid(next_pos) if main.has_method("_screen_to_grid") else Vector2i.ZERO
		if main.is_blocked(cell):
			_last_move_velocity = max(0.0, _last_move_velocity - delta)
			return
		# Editor-painted G18-G21 cave walls register pixel-perfect collision
		# in terrain_lift. _can_path_to() already checks this for path
		# planning, but per-frame chase steps were skipping it, letting
		# goblins drift through walls when crowding the player.
		if main.terrain_lift and main.terrain_lift.is_blocked_at_pos(next_pos):
			_last_move_velocity = max(0.0, _last_move_velocity - delta)
			return
	# Goblins are allowed to overlap each other freely (the soft
	# _separation_force still discourages perfect stacking, but it's no
	# longer a hard reject). The hard rule is they cannot overlap the
	# PLAYER's body — use foot-to-foot distance plus summed body radii so
	# the player isn't shoved through the goblin sprite.
	if target != null and is_instance_valid(target) and target is Node2D:
		var p: Node2D = target as Node2D
		var p_radius: float = float(p.get("body_radius")) if "body_radius" in p else 24.0
		var p_body_off: Vector2 = p.get("body_offset") if "body_offset" in p else Vector2.ZERO
		var my_r: float = body_radius * (1.6 if is_boss else 1.0)
		# Reject moves whose foot would enter the player's BODY circle
		# (foot + body_offset). This forms the ring around the visible
		# sprite torso instead of around the empty foot dot.
		var min_gap: float = p_radius + my_r
		var player_body: Vector2 = p.global_position + p_body_off
		if next_pos.distance_squared_to(player_body) < min_gap * min_gap:
			_last_move_velocity = max(0.0, _last_move_velocity - delta)
			return
	_last_move_velocity = RUN_TO_IDLE_DELAY if step.length_squared() > 0.05 else max(0.0, _last_move_velocity - delta)
	global_position = next_pos

func _base_modulate() -> Color:
	# Enraged boss tints red so the phase change is obvious to the player.
	if is_boss and enraged:
		return Color(1.6, 0.55, 0.55, 1.0)
	return Color(1, 1, 1, 1)

func _start_boss_slam() -> void:
	# Boss-only second ability: long-windup slam that hits in a wide arc
	# (aoe_attack_range). Uses Attack3 anim if available, else Special1.
	_attack_timer = attack_cooldown
	_special_timer = BOSS_SPECIAL_COOLDOWN * (0.5 if enraged else 1.0)
	_windup_left = attack_windup * 1.5
	var slam_anim: String = "Attack3" if _anim_tex("Attack3") != null else "Special1"
	_play(slam_anim, ATTACK_FPS, false, _windup_left + 0.4)
	_pending_aoe = true

var _pending_aoe: bool = false

func _start_attack() -> void:
	# Archer holds fire if a wall is in the way — repositions instead of
	# wasting an arrow.
	if ranged and not _has_line_of_sight(target.global_position):
		_attack_timer = 0.25   # short cooldown to retry after move
		return
	_attack_timer = attack_cooldown
	_windup_left = attack_windup
	if ranged:
		# Archer's bow-draw is Attack2 in the Fantasy tileset goblin
		# spritesheets; Special1 was a magic cast pose, which is why the
		# archer didn't read as one. Fall back to Special1 only if a
		# specific goblin is missing Attack2.
		var bow_anim: String = "Attack2" if _anim_tex("Attack2") != null else "Special1"
		_play(bow_anim, ATTACK_FPS, false, attack_windup + 0.3)
	else:
		_play("Attack1", ATTACK_FPS, false, attack_windup + 0.3)

func _land_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	# Refresh facing at hit-frame so the swing animation always points at
	# the player's BODY (where the visible sprite is) — not the foot dot.
	var p_body_off: Vector2 = target.get("body_offset") if "body_offset" in target else Vector2.ZERO
	var target_body: Vector2 = target.global_position + p_body_off
	_direction = _vec_to_dir(target_body - global_position)
	# Hit reach measured to the body centre, matching where chase parks
	# the goblin and where the swing is now aimed.
	var p_radius: float = float(target.get("body_radius")) if "body_radius" in target else 24.0
	var ground_dist: float = global_position.distance_to(target_body)
	if _pending_aoe and is_boss:
		_pending_aoe = false
		if ground_dist < aoe_attack_range + p_radius:
			var aoe_dmg: int = damage * 2 if enraged else int(damage * 1.5)
			var main := get_tree().root.get_node_or_null("Main")
			if main and main.has_method("take_player_damage"):
				main.take_player_damage(aoe_dmg)
		return
	var reach: float = (attack_range * 1.5) if ranged else (attack_range + 8.0)
	if ground_dist < reach + p_radius:
		_apply_hit(target)

func _apply_hit(t: Node2D) -> void:
	var main := get_tree().root.get_node_or_null("Main")
	if main and main.has_method("take_player_damage"):
		main.take_player_damage(damage)

func take_damage(amount: int, flash_color: Color = Color(1.5, 0.6, 0.6)) -> void:
	if dead:
		return
	hp -= amount
	_hit_flash_left = 0.12
	_hit_flash_color = flash_color
	# Boss enrage: the first time HP drops below threshold, flip the
	# enraged flag, gain a permanent speed/cooldown buff, refund the
	# special timer so the boss immediately uses its slam, and play the
	# Taunt anim if available as the visual cue.
	if is_boss and not enraged and hp < int(float(max_hp) * enrage_hp_threshold):
		enraged = true
		move_speed *= 1.4
		attack_cooldown *= 0.7
		_special_timer = 0.2
		_play("Taunt", DEFAULT_FPS, false, 0.6)
	if hp <= 0:
		_die()
	else:
		_play("TakeDamage", DEFAULT_FPS, false, 0.25)

const _LootDropScript := preload("res://loot/loot_drop.gd")
const _EnemyDB := preload("res://enemy_db.gd")

func _die() -> void:
	dead = true
	_play("Die", DEFAULT_FPS, false)
	emit_signal("died", self)
	# XP reward via the central enemy DB.
	var main := get_tree().root.get_node_or_null("Main")
	if main and "stats" in main and main.stats != null:
		var enemy_id: String = "goblin_boss" if is_boss \
				else ("goblin_archer" if ranged else "goblin")
		var amount: int = _EnemyDB.xp_for_kill(enemy_id, main.stats.level)
		main.stats.add_xp(amount)
	# Loot drop chance — boss always, normal goblins ~55%.
	var drop_chance: float = 1.0 if is_boss else 0.55
	if randf() < drop_chance:
		var rarity: int = _LootDropScript.random_rarity()
		if is_boss:
			rarity = _LootDropScript.Rarity.UNIQUE
		_LootDropScript.spawn(get_parent(), global_position, rarity)
	var tween := create_tween()
	tween.tween_interval(1.4)
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_callback(queue_free)

func _vec_to_dir(v: Vector2) -> int:
	if v.length_squared() < 1e-4:
		return _direction
	# Convert iso direction to one of 8 facing rows.
	var ang := atan2(v.y, v.x)
	if ang < 0.0:
		ang += TAU
	return int(round(ang / (TAU / 8.0))) % 8
