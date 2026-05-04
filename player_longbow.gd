extends Node2D

# Player driver for the 2D HD Character pack 1 / 9Longbow set.
# Anim layout: <root>/<AnimName>/<DirLetter>/<AnimName>_0_<num>.png
# 8 directions per anim (E/N/NE/NW/S/SE/SW/W), ~15 frames each.

const ANIM_ROOT := "res://assets/charachters/Sprites/Players/2D HD Character pack 1 V1.2/9Longbow"
const ARROW_SCRIPT := preload("res://arrow.gd")
const ArcherShotFX := preload("res://archer_shot_fx.gd")
# Tuning constants for the Effekseer shot effects — calibrated against
# the FX test scene's 480-ish px range. final_scale grows linearly with
# distance up to SHOT_MAX_SCALE so long-range shots don't render huge.
#     final_scale = clamp(base + dist × factor, 0, max)
const SHOT_BASE_SCALE := 0
const SHOT_DIST_FACTOR := 0.24
const SHOT_MAX_SCALE := 18.0
# At/under this range the FX speeds up so we mostly see the END of the
# effect (impact + after-glow) rather than the long fly-through. Above
# this range the effect plays at normal authored speed (1.0).
const FX_FAST_DISTANCE := 250.0
const FX_FAST_SPEED := 5.0      # speed multiplier at distance ≈ 0
const FX_BASE_SPEED := 1.0      # normal-range speed (Effekseer "1.0" = authored)

# One Effekseer VFX per skill — paths to .efkefc shot effects in
# assets/effects/archer_test/evfxshoot/VFX. Effect plays from the player's
# bow toward the target each time the skill fires.
const SHOT_VFX: Dictionary = {
	"Attack1":   "res://assets/effects/archer_test/evfxshoot/VFX/EVFX04_11_NormalShot.efkefc",
	"Attack2":   "res://assets/effects/archer_test/evfxshoot/VFX/EVFX04_14_SnipeShot.efkefc",
	"Attack3":   "res://assets/effects/archer_test/evfxshoot/VFX/EVFX04_13_ScatterShot.efkefc",
	"QuickShot": "res://assets/effects/archer_test/evfxshoot/VFX/EVFX04_18_RapidShot.efkefc",
	"Special1":  "res://assets/effects/archer_test/evfxshoot/VFX/EVFX04_09_ArcaneArrow.efkefc",
	"Special2":  "res://assets/effects/archer_test/evfxshoot/VFX/EVFX04_20_DetonatingShot.efkefc",
}
const DIR_LETTERS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
const DEFAULT_FPS := 14.0
const ATTACK_FPS := 22.0
const RUN_FPS := 18.0
const SPEED := 320.0
const SPRINT_SPEED_MULT := 1.4
const DODGE_DURATION := 0.45
const DODGE_SPEED := 420.0
# Tiny cooldown so the keypress doesn't accidentally trigger twice in one
# frame, but small enough that the user can chain dodges back-to-back.
const DODGE_COOLDOWN := 0.05
# If the user presses Space again during the second half of a roll, queue
# the next dodge to fire immediately when this one ends. Lets you string
# dodges in fluid combos.
const DODGE_REQUEUE_FROM := 0.55   # fraction of duration where requeue allowed

const ZOOM_MIN := 0.15
const ZOOM_MAX := 3.0
const ZOOM_STEP := 1.12

# Hotbar skill bindings → animation name. LMB and RMB fire the basic
# bow shots; 1-4 trigger the special / Q-shot animations from the pack.
const SKILL_LMB     := "Attack1"      # Click-to-attack on hovered enemy.
const SKILL_RMB     := "Attack2"      # Held / right-click attack.
const SKILL_KEY_1   := "Attack3"      # Power shot (different stance).
const SKILL_KEY_2   := "QuickShot"    # Snap shot — short windup.
const SKILL_KEY_3   := "Special1"     # Special A.
const SKILL_KEY_4   := "Special2"     # Special B.
# Legacy combo for code paths that don't pick a specific anim.
const ATTACK_COMBO  := [SKILL_LMB, SKILL_RMB]

# Multishot (key 1 / Attack3): five arrows in a 180° fan around the
# facing direction, fired ~60ms apart so the visual reads as a sweep.
const MULTISHOT_ANGLES: Array[float] = [-PI * 0.5, -PI * 0.25, 0.0, PI * 0.25, PI * 0.5]
const MULTISHOT_STAGGER := 0.06

@export var spawn_camera: bool = true
# Body collision shape — replaces the old GOBLIN_BODY_RADIUS constant.
# Position is in player-local space (foot at 0,0). The longbow archer
# sprite is lifted ~90 px (`_sprite.offset = (0, -42)` + FIXED_LIFT 48),
# so the visible torso centres around (0, -110). Tweak in the inspector
# while running the game (Remote tree → Player → body_offset) and watch
# the Visible Collision Shapes overlay update live.
@export var body_offset: Vector2 = Vector2(0, -110) :
	set(v):
		body_offset = v
		if _body_shape: _body_shape.position = v
@export var body_radius: float = 26.0 :
	set(v):
		body_radius = v
		if _body_circle: _body_circle.radius = v

const COLLISION_LAYER_PLAYER: int = 1
const COLLISION_LAYER_ENEMY: int = 2

var body_area: Area2D = null
var _body_shape: CollisionShape2D = null
var _body_circle: CircleShape2D = null

var main = null
var direction: int = 2
var _sprite: Sprite2D
var _frames_cache: Dictionary = {}    # anim -> dict { dir_index -> Array[Texture2D] }
var _current_anim: String = ""
var _frame_t: float = 0.0
var _anim_locked: float = 0.0
var attacking: bool = false
var dodging: bool = false
var dodge_left: float = 0.0
var dodge_cooldown_left: float = 0.0
var dodge_dir: Vector2 = Vector2.ZERO
var _dodge_requeued: bool = false
var camera: Camera2D
var manual_lift_debug: float = 0.0

var mouse_held: bool = false
var right_mouse_held: bool = false
var click_target: Vector2 = Vector2.ZERO
var has_click_target: bool = false
const CLICK_ARRIVE_RADIUS := 6.0
var attack_cooldown: float = 0.0
var _attack_chain_idx: int = 0
var _arrow_count: int = 0   # every 5th arrow becomes an ice spike
var _current_shot_vfx: String = ""   # .efkefc path for the in-flight skill
const ATTACK_RECOVER := 0.22
const ATTACK_LOCK := 0.55

func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = true
	_sprite.offset = Vector2(0, -42)
	# HD pack frames are bigger than the iso ground tile so they look
	# oversized at full scale — pull them down to ~75 % to sit naturally
	# alongside goblins and tiles.
	_sprite.scale = Vector2(0.75, 0.75)
	add_child(_sprite)
	z_index = 250
	_play("Idle", DEFAULT_FPS)
	# Build the BodyArea + CollisionShape2D so other systems (goblins,
	# arrows, push-collision) can query it via Area2D overlap. The shape
	# size + offset is driven by @export so each character variant can
	# tune them in the inspector.
	body_area = Area2D.new()
	body_area.name = "BodyArea"
	body_area.collision_layer = COLLISION_LAYER_PLAYER
	body_area.collision_mask = 0
	body_area.monitoring = true
	body_area.monitorable = true
	add_child(body_area)
	_body_shape = CollisionShape2D.new()
	_body_shape.position = body_offset
	_body_circle = CircleShape2D.new()
	_body_circle.radius = body_radius
	_body_shape.shape = _body_circle
	body_area.add_child(_body_shape)
	# Tell the FX overlay to hide any particles spawned behind our facing
	# direction so the visual only emerges past us on the forward side.
	ArcherShotFX.set_mask_target(self, 1.0)
	if spawn_camera:
		camera = Camera2D.new()
		camera.name = "Camera2D"
		camera.zoom = Vector2(1.5, 1.5)
		add_child(camera)
		camera.make_current()

# Load all 15 frames for one anim+direction. Cached.
func _frames_for(anim: String, dir_idx: int) -> Array[Texture2D]:
	if not _frames_cache.has(anim):
		_frames_cache[anim] = {}
	if _frames_cache[anim].has(dir_idx):
		return _frames_cache[anim][dir_idx]
	var dir_letter: String = DIR_LETTERS[clampi(dir_idx, 0, 7)]
	var folder := "%s/%s/%s" % [ANIM_ROOT, anim, dir_letter]
	var d := DirAccess.open(folder)
	var arr: Array[Texture2D] = []
	if d == null:
		_frames_cache[anim][dir_idx] = arr
		return arr
	var names: Array = []
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		if fn.ends_with(".png"):
			names.append(fn)
		fn = d.get_next()
	d.list_dir_end()
	names.sort()
	for n in names:
		var t: Texture2D = load("%s/%s" % [folder, n])
		if t != null:
			arr.append(t)
	_frames_cache[anim][dir_idx] = arr
	return arr

func _play(name: String, fps: float, locked: float = 0.0) -> void:
	if _current_anim == name and locked <= 0.0:
		return
	# Make sure frames exist for this anim+direction; if not, fall back.
	if _frames_for(name, direction).is_empty():
		if name != "Idle":
			_play("Idle", DEFAULT_FPS, locked)
		return
	_current_anim = name
	_frame_t = 0.0
	if locked > 0.0:
		_anim_locked = locked
	_update_frame()

func _update_frame() -> void:
	var arr := _frames_for(_current_anim, direction)
	if arr.is_empty():
		return
	var idx: int = int(floor(_frame_t)) % arr.size()
	_sprite.texture = arr[idx]

func _process(delta: float) -> void:
	_anim_locked = max(0.0, _anim_locked - delta)
	attack_cooldown = max(0.0, attack_cooldown - delta)
	dodge_cooldown_left = max(0.0, dodge_cooldown_left - delta)

	# Dodge runs to completion in its own loop, ignoring input.
	if dodging:
		dodge_left -= delta
		var step: Vector2 = dodge_dir * DODGE_SPEED * delta
		var next_pos := position + step
		if not _wall_blocks(next_pos):
			position = next_pos
		_play("Rolling", ATTACK_FPS)
		var fps_d: float = ATTACK_FPS
		_frame_t += delta * fps_d
		_update_frame()
		if dodge_left <= 0.0:
			dodging = false
			dodge_cooldown_left = DODGE_COOLDOWN
			# Chained dodge: if a Space-press came in during the second
			# half of this roll, jump straight into the next one.
			if _dodge_requeued:
				_dodge_requeued = false
				_try_dodge()
		return

	# LMB held over an enemy = continuous attack; LMB held over empty
	# ground stays as the move-to-click behaviour. RMB always attacks.
	if mouse_held and not attacking and attack_cooldown <= 0.0:
		if _is_hovering_enemy():
			has_click_target = false
			_start_attack(SKILL_LMB)
	if right_mouse_held and not attacking and attack_cooldown <= 0.0:
		_start_attack(SKILL_RMB)

	var fps: float = ATTACK_FPS if _current_anim.begins_with("Attack") \
			else (RUN_FPS if _current_anim == "Run" else DEFAULT_FPS)
	_frame_t += delta * fps
	_update_frame()

	if _anim_locked > 0.0:
		return

	# Movement input.
	var v := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	if v.length() <= 0.001 and (mouse_held or has_click_target):
		if mouse_held:
			click_target = get_global_mouse_position()
			has_click_target = true
		var to_target := click_target - position
		if to_target.length() > CLICK_ARRIVE_RADIUS:
			v = to_target.normalized()
		else:
			has_click_target = false
	if v.length() > 0.001:
		var sprint: float = SPRINT_SPEED_MULT if Input.is_key_pressed(KEY_SHIFT) else 1.0
		var step: Vector2 = v.normalized() * SPEED * sprint * delta
		var next_pos := position + step
		var blocked_by_cell: bool = _wall_blocks(next_pos)
		if not blocked_by_cell and not _goblin_blocks(next_pos):
			position = next_pos
		elif not blocked_by_cell:
			var slide_x := position + Vector2(step.x, 0)
			if not _wall_blocks(slide_x) and not _goblin_blocks(slide_x):
				position = slide_x
			else:
				var slide_y := position + Vector2(0, step.y)
				if not _wall_blocks(slide_y) and not _goblin_blocks(slide_y):
					position = slide_y
		direction = _vec_to_dir(v)
		_play("Run", RUN_FPS)
	else:
		_play("Idle", DEFAULT_FPS)

	const FIXED_LIFT := 48.0
	_sprite.position.y = -42 - (FIXED_LIFT + manual_lift_debug)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_try_dodge()
			# Hotbar skills — animation names mapped at the top of the file.
			KEY_1:
				if not attacking and attack_cooldown <= 0.0:
					_start_attack(SKILL_KEY_1)
			KEY_2:
				if not attacking and attack_cooldown <= 0.0:
					_start_attack(SKILL_KEY_2)
			KEY_3:
				if not attacking and attack_cooldown <= 0.0:
					_start_attack(SKILL_KEY_3)
			KEY_4:
				if not attacking and attack_cooldown <= 0.0:
					_start_attack(SKILL_KEY_4)
			KEY_PAGEUP:
				manual_lift_debug += 8.0
			KEY_PAGEDOWN:
				manual_lift_debug -= 8.0
			KEY_HOME:
				manual_lift_debug = 0.0
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				mouse_held = event.pressed
				if event.pressed:
					# LMB on an enemy starts an attack; on empty ground it
					# sets a move-to-click target.
					if _is_hovering_enemy() and not attacking and attack_cooldown <= 0.0:
						_start_attack(SKILL_LMB)
					else:
						click_target = get_global_mouse_position()
						has_click_target = true
			MOUSE_BUTTON_RIGHT:
				right_mouse_held = event.pressed
				if event.pressed and not attacking and attack_cooldown <= 0.0:
					_start_attack(SKILL_RMB)
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom(ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom(1.0 / ZOOM_STEP)

func _is_hovering_enemy() -> bool:
	if main == null:
		return false
	var hovered = main.get("_hovered_enemy")
	return hovered != null and is_instance_valid(hovered)

func _start_attack(anim: String = "") -> void:
	if attacking:
		return
	attacking = true
	attack_cooldown = ATTACK_RECOVER
	# Default: cycle the LMB/RMB combo (legacy callers).
	if anim == "":
		_attack_chain_idx = (_attack_chain_idx + 1) % ATTACK_COMBO.size()
		anim = ATTACK_COMBO[_attack_chain_idx]
	_current_shot_vfx = SHOT_VFX.get(anim, "")
	# Aim toward the cursor so the bow draw + arrow head the right way.
	var aim: Vector2 = get_global_mouse_position() - position
	if aim.length() > 0.001:
		direction = _vec_to_dir(aim)
		# Push the precise (un-snapped) aim into the FX overlay's mask
		# so the half-plane cut aligns with this shot's trajectory.
		ArcherShotFX.set_mask_facing(aim)
	_play(anim, ATTACK_FPS, ATTACK_LOCK)
	# Multishot fans 5 arrows around the facing direction, staggered.
	if anim == SKILL_KEY_1:
		for i in range(MULTISHOT_ANGLES.size()):
			var delay: float = ATTACK_LOCK * 0.5 + float(i) * MULTISHOT_STAGGER
			get_tree().create_timer(delay).timeout.connect(
				_release_arrow_at_angle.bind(MULTISHOT_ANGLES[i])
			)
	else:
		# Single arrow at the END of the windup so the visual matches the draw.
		get_tree().create_timer(ATTACK_LOCK * 0.7).timeout.connect(_release_arrow)
	get_tree().create_timer(ATTACK_LOCK).timeout.connect(_clear_attacking)

func _clear_attacking() -> void:
	if is_instance_valid(self):
		attacking = false

func _release_arrow_at_angle(rel_angle: float) -> void:
	# Multishot helper — fires an arrow rotated by `rel_angle` (radians)
	# from the facing/aim direction. Reuses the same arrow spawn pipeline
	# as `_release_arrow`, just with a rotated direction vector.
	if not is_instance_valid(self):
		return
	var body_y_offset: float = _sprite.position.y if _sprite else -90.0
	var start_pos: Vector2 = global_position + Vector2(0, body_y_offset)
	var aim: Vector2 = get_global_mouse_position() - start_pos
	if aim.length() < 0.001:
		aim = _dir_to_vec(direction)
	aim = aim.normalized().rotated(rel_angle)
	var target_pos: Vector2 = start_pos + aim * 1200.0
	_damage_destructible_at_target(get_global_mouse_position())
	_arrow_count += 1
	var arrow := ARROW_SCRIPT.new()
	arrow.direction = aim
	arrow.is_ice = false
	arrow.aim_target_pos = target_pos
	var fx_parent: Node = main.world if main and main.world else get_tree().root
	fx_parent.add_child(arrow)
	arrow.global_position = start_pos
	# Effekseer shot VFX paired to this skill. Args are swapped (target,
	# then start) to match the FX test scene's verified-correct mapping —
	# the effects fire from their target_location toward the emitter,
	# so the emitter goes at the END of the trajectory.
	if _current_shot_vfx != "":
		var fx_dist: float = start_pos.distance_to(target_pos)
		var fx_scale: float = clamp(
			SHOT_BASE_SCALE + fx_dist * SHOT_DIST_FACTOR, 0.0, SHOT_MAX_SCALE
		)
		# Speed up at close range so the long projectile-flight phase
		# whips by and we mostly see the impact end of the animation.
		var t_close: float = clamp(1.0 - fx_dist / FX_FAST_DISTANCE, 0.0, 1.0)
		var fx_speed: float = lerp(FX_BASE_SPEED, FX_FAST_SPEED, t_close)
		ArcherShotFX.spawn(fx_parent, target_pos, start_pos, _current_shot_vfx,
			fx_scale, null, Vector2.ZERO, fx_speed)

# Damage any destructible at the targeted ground cell. Hit is decided at
# FIRE TIME from the cursor position, not arrow physics — if the cell the
# player aimed at has a registered prop (tree/rock/grass), it takes one
# point of damage immediately and explodes when HP reaches zero.
func _damage_destructible_at_target(target_pos: Vector2) -> void:
	if main == null or not main.has_method("damage_destructible") \
			or not main.has_method("_screen_to_grid") \
			or not ("destructibles" in main):
		return
	var center_cell: Vector2i = main._screen_to_grid(target_pos)
	# Pick the registered cell whose foot is closest to the cursor —
	# tolerates the iso ambiguity when the cursor lands near a cell edge.
	var best_c: Vector2i = center_cell
	var best_d2: float = INF
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var c := Vector2i(center_cell.x + dx, center_cell.y + dy)
			if not main.destructibles.has(c):
				continue
			var foot: Vector2 = main.grid_to_screen(c)
			var d2: float = foot.distance_squared_to(target_pos)
			if d2 < best_d2:
				best_d2 = d2
				best_c = c
	if best_d2 < INF:
		main.damage_destructible(best_c, 1)

func _release_arrow() -> void:
	# Spawn the arrow at the player's visible body — the sprite is shifted
	# up by `_sprite.position.y` (which includes our fixed lift), so the
	# body's centre in world space is global_position + that offset.
	var body_y_offset: float = _sprite.position.y if _sprite else -90.0
	var start_pos: Vector2 = global_position + Vector2(0, body_y_offset)
	var target_pos: Vector2 = get_global_mouse_position()
	if main:
		var hovered = main.get("_hovered_enemy")
		if hovered != null and is_instance_valid(hovered):
			target_pos = (hovered as Node2D).global_position + Vector2(0, -32)
	var aim: Vector2 = target_pos - start_pos
	if aim.length() < 0.001:
		aim = _dir_to_vec(direction)
	# Resolve target-cell destructibles immediately on fire — the user
	# wants the visual prop at the targeted cell to explode, regardless
	# of whether the arrow's flight path actually intersects it.
	_damage_destructible_at_target(target_pos)
	_arrow_count += 1
	var arrow := ARROW_SCRIPT.new()
	arrow.direction = aim.normalized()
	arrow.is_ice = false
	# Hand the eventual world-space target to the arrow so its missile
	# trail can aim the Effekseer projectile properly.
	arrow.aim_target_pos = target_pos
	var fx_parent: Node = main.world if main and main.world else get_tree().root
	fx_parent.add_child(arrow)
	# Use global_position so it lands at the player's chest regardless of
	# whatever transform main.world has.
	arrow.global_position = start_pos
	# Effekseer shot VFX paired to this skill — args swapped to match
	# the FX test scene's verified mapping (emitter at trajectory END).
	if _current_shot_vfx != "":
		var fx_dist: float = start_pos.distance_to(target_pos)
		var fx_scale: float = clamp(
			SHOT_BASE_SCALE + fx_dist * SHOT_DIST_FACTOR, 0.0, SHOT_MAX_SCALE
		)
		# Speed up at close range so the long projectile-flight phase
		# whips by and we mostly see the impact end of the animation.
		var t_close: float = clamp(1.0 - fx_dist / FX_FAST_DISTANCE, 0.0, 1.0)
		var fx_speed: float = lerp(FX_BASE_SPEED, FX_FAST_SPEED, t_close)
		ArcherShotFX.spawn(fx_parent, target_pos, start_pos, _current_shot_vfx,
			fx_scale, null, Vector2.ZERO, fx_speed)

func _try_dodge() -> void:
	# If already dodging and we're past the requeue window, schedule the
	# next dodge to fire automatically when this one finishes.
	if dodging:
		if DODGE_DURATION - dodge_left > DODGE_DURATION * DODGE_REQUEUE_FROM:
			_dodge_requeued = true
		return
	if dodge_cooldown_left > 0.0:
		return
	# Dodge CAN cancel an in-progress attack: clears attack state +
	# unlocks the anim so the roll animation owns the body immediately.
	if attacking:
		attacking = false
		attack_cooldown = 0.0
		_anim_locked = 0.0
	# Dodge in the WASD direction, else current facing.
	var v := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	if v.length() > 0.1:
		dodge_dir = v.normalized()
		direction = _vec_to_dir(v)
	else:
		dodge_dir = _dir_to_vec(direction)
	dodging = true
	dodge_left = DODGE_DURATION
	_play("Rolling", ATTACK_FPS, DODGE_DURATION)

func _zoom(factor: float) -> void:
	if camera == null:
		return
	var z: float = camera.zoom.x * factor
	z = clamp(z, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)

# Static + painted wall collision. Combines:
#   - main.is_blocked(cell) — procedural walls (hedge maze, hill cliff)
#   - terrain_lift.is_blocked_at_pos(pos) — editor-painted G18-G21 cave
#     walls and any blocking tile registered via the paint system, with
#     pixel-perfect alpha collision.
# Goblins already check both; the player did not, so editor-painted
# cave walls were invisible to it.
func _wall_blocks(pos: Vector2) -> bool:
	if main == null:
		return false
	if main.has_method("is_blocked"):
		var c: Vector2i = main._screen_to_grid(pos)
		if main.is_blocked(c):
			return true
	# In dungeon mode terrain_lift's painted-pixel data is from the
	# world (cave walls, hedges, etc.) and overlaps random dungeon
	# cells, freezing the player at coordinates with no actual wall.
	# Skip it entirely while the player is in a dungeon.
	if "in_dungeon" in main and main.in_dungeon:
		return false
	if main.terrain_lift == null:
		return false
	# Test at the FOOT and at several points up through the BODY. The
	# player's body_offset is (0, -110), so a wall whose visual covers the
	# torso would be missed by a foot-only test (the goblin's body sits at
	# (0, -32) so for them the foot test is enough — that's why the player
	# walked through cave walls but goblins didn't). Sampling along the
	# body column blocks the player as soon as any part of their visible
	# torso would intersect a wall pixel.
	var body_top: float = body_offset.y   # -110 by default (negative = up)
	var samples := [0.0, body_top * 0.5, body_top]
	for sy in samples:
		if main.terrain_lift.is_blocked_at_pos(pos + Vector2(0, sy)):
			return true
	return false

func _goblin_blocks(pos: Vector2) -> bool:
	# Push-collision check between two ground-standing characters. We use
	# foot-to-foot (ground) distance because both characters share the
	# same ground plane in iso. Body offsets are purely visual — using
	# them here would falsely register overlaps based on vertical sprite
	# height differences. Combined radii are read from per-instance
	# `body_radius` exports so visuals + math stay in sync.
	if main == null or not ("goblins" in main):
		return false
	var my_r: float = body_radius
	for g in main.goblins:
		if g == null or not is_instance_valid(g) or g.dead:
			continue
		var g_r_base: float = g.body_radius if "body_radius" in g else 28.0
		var g_r: float = g_r_base * (1.6 if g.is_boss else 1.0)
		var combined: float = my_r + g_r
		if pos.distance_squared_to(g.global_position) < combined * combined:
			return true
	return false

func _vec_to_dir(v: Vector2) -> int:
	if v.length_squared() < 1e-4:
		return direction
	var ang := atan2(v.y, v.x)
	if ang < 0.0:
		ang += TAU
	return int(round(ang / (TAU / 8.0))) % 8

func _dir_to_vec(d: int) -> Vector2:
	var ang: float = float(d) * (TAU / 8.0)
	return Vector2(cos(ang), sin(ang))
