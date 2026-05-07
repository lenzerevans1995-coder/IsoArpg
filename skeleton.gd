extends Node2D
class_name Skeleton

# Undead pack 1 driver. Drives 8-direction animations sliced from the
# pack's "Spritesheets/With shadow/<class>/<anim>.png" sheets — each
# sheet is laid out as 8 rows (one per direction) × N columns (frames).
# Mirrors goblin.gd's chase / attack loop so the player input + arrow
# hit code carries over without changes.

const PACK := "res://assets/charachters/Sprites/2D HD Undead pack 1/2D HD Undead pack 1"
const SHEETS_BASE := PACK + "/Spritesheets/With shadow"
# Direction letter → row in the spritesheet. Sheet rows go clockwise
# starting from E (E, SE, S, SW, W, NW, N, NE) — matches DIR_LETTERS
# index order, so row index == direction index.
const DIR_TO_ROW := {
	"E": 0, "SE": 1, "S": 2, "SW": 3,
	"W": 4, "NW": 5, "N": 6, "NE": 7,
}
const DIR_LETTERS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
const DIR_VECS := [
	Vector2( 1,  0), Vector2( 0.7,  0.5), Vector2( 0,  1), Vector2(-0.7, 0.5),
	Vector2(-1, 0), Vector2(-0.7,-0.5), Vector2( 0, -1), Vector2( 0.7,-0.5),
]
const DEFAULT_FPS := 12.0
const ATTACK_FPS := 18.0
const RUN_FPS := 16.0

# Per-class kind ids — drives spawn config + ability selection.
enum Kind { WARRIOR, ARCHER, WIZARD, BRUTE, DEATHLORD, DARK_KNIGHT,
		BERSERKER, DARK_ARCHER, NECROMANCER }

const CLASS_FOLDERS := {
	Kind.BRUTE:        "1Brute",
	Kind.DEATHLORD:    "2DeathLord",
	Kind.DARK_KNIGHT:  "3DarkKnight",
	Kind.BERSERKER:    "4Berserker",
	Kind.ARCHER:       "5Archer",
	Kind.WARRIOR:      "6Warrior",
	Kind.DARK_ARCHER:  "7DarkArcher",
	Kind.NECROMANCER:  "8Necromancer",
	Kind.WIZARD:       "9Wizard",
}

@export var kind: int = Kind.WARRIOR
# Slice baseline. Tuned so a regular skeleton survives ~4-5 swings at
# fist damage (10-18) + warrior Str baseline. Elites override via their
# spawn config in the dungeon spawner.
@export var max_hp: int = 110
# Slice baseline: 5 dmg per swing on a 1.2s cooldown. With ~2 skeletons
# in melee that's ~8 dps incoming, which gives the player time to react
# without making fights trivial. Elites override this in their spawn config.
@export var damage: int = 5
@export var move_speed: float = 110.0
@export var attack_range: float = 56.0
@export var desired_range: float = 0.0    # archers/wizards keep gap
@export var attack_cooldown: float = 1.2
@export var attack_windup: float = 0.45
@export var ranged: bool = false
@export var body_offset: Vector2 = Vector2(0, -90)
@export var body_radius: float = 26.0
@export var sprite_scale: float = 1.0
# Room the skeleton was spawned in. AI confines pathfinding + chase to
# this rect so elites and bosses stay in their assigned area.
@export var home_rect: Rect2i = Rect2i()

var hp: int
var dead: bool = false
var target: Node2D = null
var _sprite: Sprite2D
var _direction: int = 2
var _frames: Array[Texture2D] = []
var _frame_t: float = 0.0
var _frame_count: int = 1
var _current_anim: String = ""
var _current_dir_letter: String = ""
var _attack_timer: float = 0.0
var _windup_left: float = 0.0
var _anim_locked_until: float = 0.0
var _hit_flash_left: float = 0.0
var _enraged: bool = false        # berserker rage / dark knight riposte
var _riposte_window: float = 0.0  # dark knight: > 0 means counter-attacks any incoming hit
var _special_cd: float = 0.0      # cooldown for class-specific specials
# Deathlord phase tracking (1 = base, 2 = parry+spell, 3 = bone storm).
var _phase: int = 1
# Tracks the most recent revive used by Necromancer / Deathlord so we
# don't keep cycling the same corpse.
var _revive_history: Dictionary = {}

static var _frames_cache: Dictionary = {}   # "class/anim/dir" -> Array[Texture2D]
static var _sheet_cache: Dictionary = {}    # sheet path -> Texture2D (or null on miss)

signal died(skel)

const HIGHLIGHT_TEX_PATH := "res://assets/drops/highlight/highlight_yellow.png"
var _highlight: Node2D    # code-drawn ring, was Sprite2D legacy
var _main_ref: Node = null    # cached lookup so AI loops don't search root every frame

func _ready() -> void:
	hp = max_hp
	_main_ref = get_tree().root.get_node_or_null("Main")
	_sprite = Sprite2D.new()
	_sprite.centered = true
	_sprite.offset = Vector2(0, -42)
	_sprite.scale = Vector2(sprite_scale, sprite_scale)
	add_child(_sprite)
	add_to_group("skeleton")
	add_to_group("enemy")
	# Global enemy rule: lift one z-step above the parent tile layer so
	# tall-grass / flora tiles never visually swallow the silhouette.
	# Still relative so the player (which uses the same +1 lift) y-sorts
	# against us per ground y-position.
	z_index = 1
	z_as_relative = true
	_setup_body_collision()
	_play("Idle", DEFAULT_FPS)

func _setup_body_collision() -> void:
	# StaticBody2D so the player's move_and_slide blocks against the
	# skeleton's footprint. Child of the skeleton Node2D, so it follows
	# the skeleton as it moves. Radius scales with sprite_scale (10 px
	# at the 0.5 demo scale = 20 px footprint, sized for 64 px sprites).
	var body := StaticBody2D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var shape := CollisionShape2D.new()
	# Capsule dimensions come from KIND_PRESETS (override-able via the
	# enemy_collision_editor dev scene). x/y position the capsule center
	# in skeleton-local space (foot = origin), r/h = capsule radius and
	# middle height (total span = h + 2r).
	var preset: Dictionary = get_kind_preset(kind)
	var cap: Dictionary = preset.get("cap", {})
	var caps := CapsuleShape2D.new()
	caps.radius = float(cap.get("r", 14.0))
	caps.height = float(cap.get("h", 36.0))
	shape.position = Vector2(float(cap.get("x", 0.0)), float(cap.get("y", -32.0)))
	shape.shape = caps
	body.add_child(shape)

func _ensure_highlight() -> void:
	if _highlight and is_instance_valid(_highlight):
		return
	# Code-drawn iso ellipse — direct Node2D with a _draw script so the
	# ring renders without depending on a texture asset. Stored on the
	# `_highlight` field (still typed Sprite2D for compatibility with
	# _clear_highlight, but we treat it as a plain CanvasItem).
	var ring := Node2D.new()
	ring.position = Vector2(0, -4)
	ring.z_index = -1
	# Per-kind size: bigger silhouettes get a wider ring. 28 px x-radius
	# is a good base for a 64-77 px-tall sprite; the y-radius is half
	# for the iso 2:1 ellipse.
	var rx: float = 26.0 * (sprite_scale / 0.6)
	var ry: float = rx * 0.5
	var sc := GDScript.new()
	sc.source_code = """
extends Node2D
var rx: float = 26.0
var ry: float = 13.0
func _ready() -> void:
	queue_redraw()
func _draw() -> void:
	# Soft outer glow — concentric ellipses with falling alpha.
	for i in range(4):
		var bump: float = float(i) * 2.0
		var a: float = 0.16 - 0.03 * float(i)
		_iso_arc(rx + bump, ry + bump * 0.5, Color(1.0, 0.32, 0.30, a), 1.5)
	# Crisp middle ring.
	_iso_arc(rx, ry, Color(1.0, 0.32, 0.30, 0.95), 2.0)
	# Inner shimmer.
	_iso_arc(rx - 3.0, ry - 1.5, Color(1.0, 0.55, 0.50, 0.55), 1.0)
func _iso_arc(rx_: float, ry_: float, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	var n := 56
	for i in range(n + 1):
		var t: float = float(i) / float(n) * TAU
		pts.append(Vector2(cos(t) * rx_, sin(t) * ry_))
	for i in range(pts.size() - 1):
		draw_line(pts[i], pts[i + 1], col, w)
"""
	sc.reload()
	ring.set_script(sc)
	ring.set("rx", rx)
	ring.set("ry", ry)
	add_child(ring)
	_highlight = ring

func _clear_highlight() -> void:
	if _highlight and is_instance_valid(_highlight):
		_highlight.queue_free()
	_highlight = null

# ---- animation -------------------------------------------------------

func _class_folder() -> String:
	return CLASS_FOLDERS.get(kind, "6Warrior")

func _load_sheet(class_folder: String, anim: String) -> Texture2D:
	var path := "%s/%s/%s.png" % [SHEETS_BASE, class_folder, anim]
	if _sheet_cache.has(path):
		return _sheet_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_sheet_cache[path] = tex
	return tex

func _load_frames(anim: String, dir_letter: String) -> Array[Texture2D]:
	var key := "%s/%s/%s" % [_class_folder(), anim, dir_letter]
	if _frames_cache.has(key):
		return _frames_cache[key]
	var out: Array[Texture2D] = []
	var sheet: Texture2D = _load_sheet(_class_folder(), anim)
	if sheet != null:
		var sheet_w: int = sheet.get_width()
		var sheet_h: int = sheet.get_height()
		# 8 rows (one per cardinal/diagonal direction). Frames are square,
		# so frame_w == frame_h == sheet_h / 8.
		var frame: int = sheet_h / 8
		if frame > 0:
			var cols: int = sheet_w / frame
			var row: int = int(DIR_TO_ROW.get(dir_letter, 0))
			for c in range(cols):
				var atlas := AtlasTexture.new()
				atlas.atlas = sheet
				atlas.region = Rect2(c * frame, row * frame, frame, frame)
				out.append(atlas)
	_frames_cache[key] = out
	return out

func _play(anim: String, fps: float, locked_dur: float = 0.0) -> void:
	var dir_letter: String = String(DIR_LETTERS[clampi(_direction, 0, 7)])
	if anim == _current_anim and dir_letter == _current_dir_letter and locked_dur <= 0.0:
		return
	_frames = _load_frames(anim, dir_letter)
	if _frames.is_empty() and anim != "Idle":
		_play("Idle", DEFAULT_FPS)
		return
	_current_anim = anim
	_current_dir_letter = dir_letter
	_frame_t = 0.0
	_frame_count = max(1, _frames.size())
	if locked_dur > 0.0:
		_anim_locked_until = locked_dur
	if not _frames.is_empty():
		_sprite.texture = _frames[0]

func _update_frame(delta: float) -> void:
	if _frames.is_empty():
		return
	var fps: float = ATTACK_FPS if _current_anim.begins_with("Attack") \
			else (RUN_FPS if _current_anim == "Run" else DEFAULT_FPS)
	_frame_t += delta * fps
	var idx: int = int(floor(_frame_t)) % _frame_count
	_sprite.texture = _frames[idx]

# ---- AI loop ---------------------------------------------------------

func _process(delta: float) -> void:
	if dead:
		_update_frame(delta)
		return
	# AI / animation sleep when far from the player. The dungeon can hold
	# 12+ skeletons at once; running BFS + per-frame anim updates on all
	# of them was the main lag source. Anything outside this range stays
	# in Idle and skips work until the player closes in.
	var sleep: bool = false
	if target != null and is_instance_valid(target):
		var sleep_d2: float = 1100.0 * 1100.0
		if global_position.distance_squared_to(target.global_position) > sleep_d2:
			sleep = true
	if sleep:
		# Cheap idle path: hold current frame, decay timers only.
		_attack_timer = max(0.0, _attack_timer - delta)
		_anim_locked_until = max(0.0, _anim_locked_until - delta)
		return
	if _hit_flash_left > 0.0:
		_hit_flash_left -= delta
		_sprite.modulate = Color(1.6, 0.7, 0.7) if _hit_flash_left > 0.0 else Color(1, 1, 1, 1)
	# Self-tint via _base_modulate is now redundant (main applies the
	# transparent-wall tint globally each frame) so we don't fight that
	# pass — _sprite.modulate gets set there. Just clear after hit flash.
	_attack_timer = max(0.0, _attack_timer - delta)
	_anim_locked_until = max(0.0, _anim_locked_until - delta)
	_riposte_window = max(0.0, _riposte_window - delta)
	_special_cd = max(0.0, _special_cd - delta)
	# Deathlord phase transitions based on HP%.
	if kind == Kind.DEATHLORD:
		var pct: float = float(hp) / float(max_hp)
		if pct < 0.33: _phase = 3
		elif pct < 0.66: _phase = 2
		else: _phase = 1
	if _windup_left > 0.0:
		_windup_left -= delta
		if _windup_left <= 0.0:
			_land_attack()
	if target == null or not is_instance_valid(target):
		_play("Idle", DEFAULT_FPS)
		_update_frame(delta)
		return
	# Confine to home room: if the player isn't inside this skeleton's
	# assigned room, stay idle. Bosses + elites stay in their arena.
	var main := _main_ref
	if home_rect.size != Vector2i.ZERO and main \
			and main.has_method("_screen_to_grid"):
		var p_cell: Vector2i = main._screen_to_grid(target.global_position)
		if not home_rect.has_point(p_cell):
			_play("Idle", DEFAULT_FPS)
			_update_frame(delta)
			return
	# Refresh facing toward player every frame.
	var p_body_off: Vector2 = target.get("body_offset") if "body_offset" in target else Vector2.ZERO
	var to_target: Vector2 = (target.global_position + p_body_off) - global_position
	_direction = _vec_to_dir(to_target)
	if _anim_locked_until > 0.0:
		_update_frame(delta)
		return
	var dist := to_target.length()
	# Archer / wizard kite — back away if too close.
	var min_keep: float = desired_range if ranged else 0.0
	if ranged and dist < min_keep:
		_step(-to_target.normalized() * move_speed * 0.9, delta)
		_play("RunBackwards", RUN_FPS)
		_update_frame(delta)
		return
	# Within attack reach — swing.
	if _player_in_attack_reach(target):
		if _attack_timer <= 0.0:
			_start_attack()
		else:
			_play("Idle", DEFAULT_FPS)
		_update_frame(delta)
		return
	# Otherwise pathfind toward the player. Recompute periodically so
	# we can route around walls without doing it every frame.
	_repath_t -= delta
	if main:
		var goal_c: Vector2i = main._screen_to_grid(target.global_position)
		# Recompute the path only when the player has changed cells OR
		# we hit the periodic refresh tick. Keeps BFS from running on
		# every frame for stationary targets.
		if _path.is_empty() or _repath_t <= 0.0 or goal_c != _last_goal_cell:
			_repath_t = REPATH_INTERVAL
			_last_goal_cell = goal_c
			var start_c: Vector2i = main._screen_to_grid(global_position)
			_path = _bfs_path(start_c, goal_c, main)
	# Walk toward the next waypoint if the path has one, else fall
	# back to a straight line (open rooms / no path needed).
	var move_dir: Vector2 = to_target.normalized()
	if _path.size() > 0 and main:
		var next_cell: Vector2i = _path[0]
		var next_world: Vector2 = main.grid_to_screen(next_cell)
		var step_v: Vector2 = (next_world - global_position)
		if step_v.length() < 12.0:
			_path.pop_front()
		else:
			move_dir = step_v.normalized()
	_step(move_dir * move_speed, delta)
	_play("Run", RUN_FPS)
	_update_frame(delta)

func _player_in_attack_reach(p: Node2D) -> bool:
	var p_body_off: Vector2 = p.get("body_offset") if "body_offset" in p else Vector2.ZERO
	var d: float = global_position.distance_to(p.global_position + p_body_off)
	var p_r: float = p.get("body_radius") if "body_radius" in p else 24.0
	return d < attack_range + p_r

func _step(velocity: Vector2, delta: float) -> void:
	var next_pos: Vector2 = global_position + velocity * delta
	var main := _main_ref
	if main and main.has_method("_screen_to_grid"):
		# Skeletons treat ALL wall cells as solid (transparent or not).
		# is_blocked lets the player walk under transparent walls, but
		# enemies must stay strictly inside floor / corridor space.
		if _cell_blocks_skel(main._screen_to_grid(next_pos), main):
			var slide_x: Vector2 = global_position + Vector2(velocity.x * delta, 0.0)
			var slide_y: Vector2 = global_position + Vector2(0.0, velocity.y * delta)
			if not _cell_blocks_skel(main._screen_to_grid(slide_x), main):
				next_pos = slide_x
			elif not _cell_blocks_skel(main._screen_to_grid(slide_y), main):
				next_pos = slide_y
			else:
				return
	if target != null and is_instance_valid(target):
		var p_r: float = target.get("body_radius") if "body_radius" in target else 24.0
		var min_gap: float = p_r + body_radius
		if next_pos.distance_squared_to(target.global_position) < min_gap * min_gap:
			return
	global_position = next_pos

# Strict wall check used by movement + pathfinding for skeletons.
# Treats every wall cell as solid (the player's transparent-wall pass
# is a player-only concession — enemies must respect the geometry).
func _cell_blocks_skel(cell: Vector2i, main: Node) -> bool:
	if main == null or not ("dungeon" in main) or main.dungeon == null:
		return main.is_blocked(cell) if main and main.has_method("is_blocked") else false
	var dng: Node = main.dungeon
	if not dng.floor_cells.has(cell):
		return true
	if dng.wall_cells.has(cell):
		return true
	return false

# BFS pathfinder over dungeon.floor_cells. Returns an array of cells
# from start (exclusive) to goal (inclusive), capped at MAX_PATH steps.
const MAX_PATH := 80

func _bfs_path(start: Vector2i, goal: Vector2i, main: Node) -> Array:
	if main == null or not ("dungeon" in main) or main.dungeon == null:
		return []
	var floors: Dictionary = main.dungeon.floor_cells
	if not floors.has(start) or not floors.has(goal):
		return []
	var came_from: Dictionary = {start: null}
	var frontier: Array = [start]
	var steps: int = 0
	while frontier.size() > 0 and steps < MAX_PATH * 16:
		steps += 1
		var current: Vector2i = frontier.pop_front()
		if current == goal:
			break
		for off in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
				Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var n: Vector2i = current + off
			if came_from.has(n):
				continue
			if not floors.has(n):
				continue
			# Skeletons can NEVER path through walls — even transparent
			# ones. They take the long way around like a normal enemy.
			if main.dungeon.wall_cells.has(n):
				continue
			# Stay inside home room. Lets bosses + elites pace their
			# arena instead of wandering through the whole dungeon.
			if home_rect.size != Vector2i.ZERO and not home_rect.has_point(n):
				continue
			came_from[n] = current
			frontier.append(n)
	if not came_from.has(goal):
		return []
	var path: Array = []
	var cur: Vector2i = goal
	while cur != start:
		path.push_front(cur)
		cur = came_from[cur]
		if path.size() > MAX_PATH:
			break
	return path

# ---- attacks ---------------------------------------------------------

func _attack_anim_for_kind() -> String:
	# Pick which Attack* / CastSpell anim suits the class.
	match kind:
		Kind.WARRIOR, Kind.DARK_KNIGHT, Kind.BRUTE, Kind.BERSERKER, Kind.DEATHLORD:
			return ["Attack1", "Attack2", "Pummel"][randi() % 3]
		Kind.ARCHER, Kind.DARK_ARCHER:
			return "QuickShot" if randf() < 0.4 else "Attack1"
		Kind.WIZARD, Kind.NECROMANCER:
			return "CastSpell"
		_:
			return "Attack1"

func _start_attack() -> void:
	_attack_timer = attack_cooldown
	_windup_left = attack_windup
	# Berserker rage under 60% HP.
	if kind == Kind.BERSERKER and hp < int(float(max_hp) * 0.6):
		_enraged = true
		_attack_timer *= 0.7
		_windup_left *= 0.7
	# Dark Knight riposte stance, 25% chance per swing.
	if kind == Kind.DARK_KNIGHT and randf() < 0.25:
		_play("BlockMid", DEFAULT_FPS, 1.5)
		_riposte_window = 1.5
		return
	# Brute ground slam — long windup, AoE on impact, knockback.
	if kind == Kind.BRUTE and _special_cd <= 0.0:
		_special_cd = 5.0
		_windup_left = 1.0
		_pending_slam = true
		_play("Pummel", ATTACK_FPS, 1.4)
		return
	# Dark Archer shadow-step every 12s — fades alpha, repositions
	# behind the player, then fires the next shot from there.
	if kind == Kind.DARK_ARCHER and _special_cd <= 0.0 and target != null \
			and is_instance_valid(target):
		_special_cd = 12.0
		_pending_shadow_step = true
		# Use Slide for the disappear pose (DarkArcher has Slide).
		_play("Slide", ATTACK_FPS, 0.8)
		_anim_locked_until = 0.8
		_windup_left = 0.5
		modulate = Color(1, 1, 1, 0.15)
		return
	# Necromancer revive: every 8s, if there's a dead Warrior corpse
	# nearby, raise it back to 50% HP. Plays CastSpell with no damage.
	if kind == Kind.NECROMANCER and _special_cd <= 0.0 and _try_necromancer_revive():
		_special_cd = 8.0
		_windup_left = 0.0   # revive resolves on cast, no impact frame
		_play("CastSpell", ATTACK_FPS, attack_windup + 0.5)
		return
	# Deathlord phase 3: every 6s casts Bone Storm (Special2 fan).
	if kind == Kind.DEATHLORD and _phase >= 3 and _special_cd <= 0.0:
		_special_cd = 6.0
		_windup_left = 0.4
		_play("Special2", ATTACK_FPS, 1.0)
		_pending_bone_storm = true
		return
	# Deathlord phase 2: occasional ranged bolt + parry stance mixed
	# into the melee combo.
	if kind == Kind.DEATHLORD and _phase >= 2 and _special_cd <= 0.0:
		_special_cd = 4.0
		if randf() < 0.5:
			_riposte_window = 1.5
			_play("BlockMid", DEFAULT_FPS, 1.5)
			return
		else:
			_play("CastSpell", ATTACK_FPS, attack_windup + 0.4)
			# Treat the cast as the attack — landed at the windup tail.
			return
	var anim: String = _attack_anim_for_kind()
	_play(anim, ATTACK_FPS, attack_windup + 0.4)

# Set true while Deathlord's bone-storm cast is mid-windup; resolved in
# _land_attack to deal a single AoE pulse around the boss room.
var _pending_bone_storm: bool = false
var _pending_slam: bool = false           # Brute ground slam AoE
var _pending_shadow_step: bool = false    # Dark Archer reposition
# Path-finding cache: list of cell waypoints from current position
# toward the player. Recomputed periodically (REPATH_INTERVAL) or when
# the player's cell changes.
var _path: Array = []
var _repath_t: float = 0.0
var _last_goal_cell: Vector2i = Vector2i(99999, 99999)
const REPATH_INTERVAL := 1.2
const ARROW_SCRIPT := preload("res://arrow.gd")
const _LootDropScript := preload("res://loot/loot_drop.gd")
const _LootTablesScript := preload("res://loot/loot_tables.gd")

# Find the nearest dead Warrior corpse (any Skeleton with kind=WARRIOR
# and dead=true), revive to 50% HP and play Die in reverse-ish via the
# existing TakeDamage anim so it visually pops up.
func _try_necromancer_revive() -> bool:
	var best: Node = null
	var best_d: float = 9.0e6
	for n in get_tree().get_nodes_in_group("skeleton"):
		if n == self or not (n is Skeleton):
			continue
		var sk: Skeleton = n
		if not sk.dead or sk.kind != Kind.WARRIOR:
			continue
		if _revive_history.has(sk.get_instance_id()):
			continue
		var d: float = global_position.distance_to(sk.global_position)
		if d < best_d:
			best_d = d
			best = sk
	if best == null:
		return false
	var sk2: Skeleton = best
	sk2.dead = false
	sk2.hp = int(float(sk2.max_hp) * 0.5)
	sk2.modulate = Color(1, 1, 1, 1)
	sk2._play("TakeDamage", DEFAULT_FPS, 0.4)
	_revive_history[sk2.get_instance_id()] = true
	return true

func _land_attack() -> void:
	if target == null or not is_instance_valid(target) or dead:
		return
	# Deathlord bone storm: AoE pulse in a wide radius around the boss.
	if _pending_bone_storm:
		_pending_bone_storm = false
		var d2: float = global_position.distance_to(target.global_position)
		if d2 < 240.0:
			var main := _main_ref
			if main and main.has_method("take_player_damage"):
				main.take_player_damage(int(round(float(damage) * 1.5)))
		return
	# Brute slam: AoE within ~120px, +50% damage, no projectile.
	if _pending_slam:
		_pending_slam = false
		var d3: float = global_position.distance_to(target.global_position)
		if d3 < 120.0:
			var main := _main_ref
			if main and main.has_method("take_player_damage"):
				main.take_player_damage(int(round(float(damage) * 1.5)))
		return
	# Dark Archer shadow-step: teleport 2 cells behind the player and
	# fire an arrow from the new position.
	if _pending_shadow_step:
		_pending_shadow_step = false
		var p_off: Vector2 = target.get("body_offset") if "body_offset" in target else Vector2.ZERO
		var to_p: Vector2 = (target.global_position + p_off) - global_position
		var behind: Vector2 = target.global_position - to_p.normalized() * 96.0
		var main2 := _main_ref
		if main2 and main2.has_method("_screen_to_grid"):
			var c: Vector2i = main2._screen_to_grid(behind)
			# Snap to a valid floor cell inside the home room.
			if not _cell_blocks_skel(c, main2) and (home_rect.size == Vector2i.ZERO \
					or home_rect.has_point(c)):
				global_position = main2.grid_to_screen(c)
		modulate = Color(1, 1, 1, 1)
		_fire_arrow_at_player()
		return
	# Archers fire an actual arrow projectile that flies at the player.
	# Damage is applied on impact via the arrow itself, not here.
	if ranged and (kind == Kind.ARCHER or kind == Kind.DARK_ARCHER):
		_fire_arrow_at_player()
		return
	if _player_in_attack_reach(target):
		var dmg: int = damage
		if _enraged:
			dmg = int(round(float(damage) * 1.25))
		var main := _main_ref
		if main and main.has_method("take_player_damage"):
			main.take_player_damage(dmg)

# Spawns an arrow.gd projectile from the archer's body toward the
# player's body. Reuses the same Arrow class the player uses, so the
# visual + flight + body-radius hit all carry over for free. Damage
# value is taken from this skeleton's `damage` so archer arrows feel
# distinct from melee swings.
func _fire_arrow_at_player() -> void:
	if target == null or not is_instance_valid(target):
		return
	var main := _main_ref
	var parent: Node = main.dungeon if (main and "in_dungeon" in main \
			and main.in_dungeon and "dungeon" in main and main.dungeon) else get_parent()
	if parent == null:
		return
	var p_off: Vector2 = target.get("body_offset") if "body_offset" in target else Vector2(0, -90)
	var aim_to: Vector2 = target.global_position + p_off
	var start: Vector2 = global_position + body_offset
	var dir_v: Vector2 = aim_to - start
	if dir_v.length() < 0.001:
		return
	var arrow := ARROW_SCRIPT.new()
	arrow.direction = dir_v.normalized()
	arrow.aim_target_pos = aim_to
	arrow.damage = damage
	# Mark the arrow as enemy-fired so the goblin/skeleton hit-test
	# inside arrow.gd's _process loop skips friendlies. Currently arrow
	# scans goblins + skeletons for hits, but the player isn't in those
	# groups — so we just intercept impact here when the arrow reaches
	# the target body.
	arrow.set_meta("from_enemy", true)
	parent.add_child(arrow)
	arrow.global_position = start

# ---- damage / death --------------------------------------------------

func take_damage(amount: int, _flash_color: Color = Color(1.6, 0.7, 0.7)) -> void:
	if dead:
		return
	# Dark Knight riposte: any hit during the 1.5s window is countered.
	if kind == Kind.DARK_KNIGHT and _riposte_window > 0.0 \
			and target != null and is_instance_valid(target):
		_riposte_window = 0.0
		var main := _main_ref
		if main and main.has_method("take_player_damage"):
			main.take_player_damage(int(round(float(amount) * 0.75)))
		_play("Special2", ATTACK_FPS, 0.5)
		# Reduced damage taken on the parried hit.
		amount = int(round(float(amount) * 0.4))
	hp -= amount
	_hit_flash_left = 0.12
	# Play GetHit reaction anim — short locked window so it doesn't get
	# overwritten by the AI loop until the flinch resolves. Skipped if
	# the skeleton is mid-attack (don't interrupt windups) or about to
	# die (death anim takes over below).
	if hp > 0 and _anim_locked_until <= 0.0:
		_play("GetHit", DEFAULT_FPS, 0.25)
	if hp <= 0:
		_die()
	else:
		_play("TakeDamage", DEFAULT_FPS, 0.25)

const _EnemyDB := preload("res://enemy_db.gd")

func _die() -> void:
	dead = true
	_play("Die", DEFAULT_FPS, 1.4)
	emit_signal("died", self)
	# Grant XP via main.stats. Skipped silently if main / stats missing.
	var main := get_tree().root.get_node_or_null("Main")
	if main and "stats" in main and main.stats != null:
		var enemy_id: String = _EnemyDB.id_for_skeleton_kind(kind)
		if enemy_id != "":
			var amount: int = _EnemyDB.xp_for_kill(enemy_id, main.stats.level)
			main.stats.add_xp(amount)
			# `_spawn_damage_number` takes only (pos, amount). Color
			# tinting per source isn't supported yet, so just spawn
			# the floating number with the default colour.
			if main.has_method("_spawn_damage_number"):
				main._spawn_damage_number(global_position + Vector2(0, -64), amount)
	# Loot drop via loot_tables — picks rarity, slot, and a specific item
	# weighted by drop_weight. Each entry in the returned array becomes
	# its own LootDrop with the rolled item_id stored for future pickup.
	var enemy_id: String = _EnemyDB.id_for_skeleton_kind(kind)
	var rolls: Array = _LootTablesScript.roll_drops(enemy_id)
	var parent_node: Node = get_parent()
	for r in rolls:
		var rarity: int = int(r.get("rarity", _LootDropScript.Rarity.COMMON))
		var item_id: String = String(r.get("item_id", ""))
		# Spread multiple drops slightly so they don't stack on one tile.
		var jitter: Vector2 = Vector2(randf_range(-12, 12), randf_range(-8, 8))
		_LootDropScript.spawn(parent_node, global_position + jitter, rarity, item_id)
	# Deathlord Death Cry: revive the two nearest dead Warriors so the
	# fight isn't over until the escorts go down too.
	if kind == Kind.DEATHLORD:
		_death_cry()
	var tween := create_tween()
	tween.tween_interval(1.4)
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(queue_free)

func _death_cry() -> void:
	var revives: Array = []
	for n in get_tree().get_nodes_in_group("skeleton"):
		if n == self or not (n is Skeleton):
			continue
		var sk: Skeleton = n
		if not sk.dead or sk.kind != Kind.WARRIOR:
			continue
		revives.append([global_position.distance_to(sk.global_position), sk])
	revives.sort_custom(func(a, b): return a[0] < b[0])
	var raised: int = 0
	for entry in revives:
		if raised >= 2:
			break
		var sk2: Skeleton = entry[1]
		sk2.dead = false
		sk2.hp = sk2.max_hp
		sk2.modulate = Color(1, 1, 1, 1)
		sk2._play("TakeDamage", DEFAULT_FPS, 0.5)
		raised += 1

func _base_modulate() -> Color:
	# When the skeleton stands on a transparent-wall cell, carry the
	# same dark tint the player gets so they read as "behind glass".
	var main := _main_ref
	if main and "in_dungeon" in main and main.in_dungeon \
			and "dungeon" in main and main.dungeon:
		var cell: Vector2i = main._screen_to_grid(global_position)
		if main.dungeon.transparent_walls.has(cell):
			if _enraged:
				return Color(0.85, 0.40, 0.45)
			return Color(0.55, 0.55, 0.62)
	if _enraged:
		return Color(1.6, 0.55, 0.55)
	return Color(1, 1, 1, 1)

# ---- direction -------------------------------------------------------

func _vec_to_dir(v: Vector2) -> int:
	if v.length_squared() < 1e-4:
		return _direction
	var ang := atan2(v.y, v.x)
	if ang < 0.0:
		ang += TAU
	return int(round(ang / (TAU / 8.0))) % 8

# ---- factory ---------------------------------------------------------

# 64x64 demo: source frames are 192x192, so 64/192 ~= 0.33. All kinds
# inherit this; elites with their own bigger silhouette (Brute,
# Deathlord) get their multiplier on top via the per-kind overrides
# below.
const TINY_DEMO_SCALE := 0.5

# Per-kind visual + collision preset. `scale` = Sprite2D.scale used by
# the renderer; `cap` = capsule footprint used by _setup_body_collision
# (x/y in local pixels, r = radius, h = capsule middle height — total
# vertical span = h + 2*r).
#
# Render targets at 64x64 demo:
#   - 128 px source kinds at scale 0.5  -> 64 px
#   - 192 px Brute / Deathlord scaled larger so they READ as the bigger
#     silhouette (Brute ~83 px, Deathlord ~96 px) instead of the size
#     parity that 64/192 forced.
#
# These defaults are overridden at runtime by data/enemy_presets.json
# if that file exists, so dev_scenes/enemy_collision_editor can tune
# them without re-saving the script.
const KIND_PRESETS := {
	Kind.WARRIOR:     {"scale": 0.60, "cap": {"x": 0, "y": -36, "r": 15, "h": 38}},
	Kind.ARCHER:      {"scale": 0.60, "cap": {"x": 0, "y": -36, "r": 14, "h": 38}},
	Kind.WIZARD:      {"scale": 0.60, "cap": {"x": 0, "y": -36, "r": 14, "h": 38}},
	Kind.BRUTE:       {"scale": 0.50, "cap": {"x": 0, "y": -46, "r": 21, "h": 50}},
	Kind.DEATHLORD:   {"scale": 0.58, "cap": {"x": 0, "y": -52, "r": 22, "h": 56}},
	Kind.DARK_KNIGHT: {"scale": 0.62, "cap": {"x": 0, "y": -38, "r": 16, "h": 40}},
	Kind.BERSERKER:   {"scale": 0.65, "cap": {"x": 0, "y": -40, "r": 17, "h": 42}},
	Kind.DARK_ARCHER: {"scale": 0.60, "cap": {"x": 0, "y": -36, "r": 14, "h": 38}},
	Kind.NECROMANCER: {"scale": 0.60, "cap": {"x": 0, "y": -36, "r": 15, "h": 38}},
}
const PRESETS_JSON_PATH := "res://data/enemy_presets.json"
static var _runtime_presets: Dictionary = {}

static func _ensure_presets_loaded() -> void:
	if not _runtime_presets.is_empty():
		return
	if not FileAccess.file_exists(PRESETS_JSON_PATH):
		_runtime_presets = {"_loaded": true}
		return
	var f := FileAccess.open(PRESETS_JSON_PATH, FileAccess.READ)
	if f == null:
		_runtime_presets = {"_loaded": true}
		return
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		_runtime_presets = parsed
	_runtime_presets["_loaded"] = true

static func get_kind_preset(kind_id: int) -> Dictionary:
	_ensure_presets_loaded()
	var defaults: Dictionary = KIND_PRESETS.get(kind_id, {"scale": 0.5, "cap": {"x": 0, "y": -30, "r": 13, "h": 32}})
	var out: Dictionary = defaults.duplicate(true)
	var override: Variant = _runtime_presets.get(str(kind_id), null)
	if override is Dictionary:
		if override.has("scale"):
			out["scale"] = override["scale"]
		if override.has("cap") and override["cap"] is Dictionary:
			for ck in override["cap"]:
				out["cap"][ck] = override["cap"][ck]
	return out

# Spawn config preset per class — keeps dungeon spawner code short.
static func make(kind_id: int, target_player: Node2D = null) -> Skeleton:
	var s := Skeleton.new()
	s.kind = kind_id
	# sprite_scale comes from KIND_PRESETS (overridable via JSON) so the
	# size hierarchy is data-driven and visual.
	var preset: Dictionary = get_kind_preset(kind_id)
	s.sprite_scale = float(preset.get("scale", TINY_DEMO_SCALE))
	# Body offset (where projectiles fire from / aim at) tracks the
	# rendered sprite center. Sprite is drawn with offset (0, -42) in
	# unscaled-frame coords, so at scale `s` the body center sits at
	# y = -42 * s. Old default (0, -90) was tuned for full-scale
	# 128 px characters and floated arrows above the head.
	s.body_offset = Vector2(0, -42.0 * s.sprite_scale)
	match kind_id:
		Kind.WARRIOR:
			s.max_hp = 35;  s.damage = 8;  s.attack_range = 56.0
		Kind.ARCHER:
			s.max_hp = 25;  s.damage = 7;  s.attack_range = 200.0
			s.desired_range = 220.0; s.ranged = true
		Kind.WIZARD:
			s.max_hp = 22;  s.damage = 10; s.attack_range = 240.0
			s.desired_range = 260.0; s.ranged = true
		Kind.BRUTE:
			s.max_hp = 110; s.damage = 18; s.move_speed = 70.0
			s.attack_range = 64.0
		Kind.DEATHLORD:
			s.max_hp = 280; s.damage = 18; s.attack_range = 64.0
		Kind.DARK_KNIGHT:
			s.max_hp = 90;  s.damage = 14; s.attack_range = 60.0
		Kind.BERSERKER:
			s.max_hp = 70;  s.damage = 12; s.attack_range = 56.0
			s.move_speed = 130.0
		Kind.DARK_ARCHER:
			s.max_hp = 35;  s.damage = 10; s.attack_range = 220.0
			s.desired_range = 240.0; s.ranged = true
		Kind.NECROMANCER:
			s.max_hp = 40;  s.damage = 12; s.attack_range = 240.0
			s.desired_range = 260.0; s.ranged = true
	s.target = target_player
	return s
