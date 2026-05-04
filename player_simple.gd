extends Node2D

# Drop-in player driver that renders the pre-built Fantasy tileset
# Player spritesheets directly (no LayeredCharacter / equipment slots).
# Reuses the same anim layout the goblins use: 1920×1024 sheets at
# 15 cols × 8 rows of 128px frames, rows = 8 directions.

const FRAME_W := 128
const FRAME_H := 128
const COLS := 15
const ROWS := 8
const DEFAULT_FPS := 12.0
const ATTACK_FPS := 18.0
const RUN_FPS := 16.0
const SPEED := 320.0
const SPRINT_SPEED_MULT := 1.4

const ZOOM_MIN := 0.15
const ZOOM_MAX := 3.0
const ZOOM_STEP := 1.12

const ASSET_DIR := "res://assets/tilesets/Fantasy tileset - 2D Isometric V1.1/Fantasy tileset - 2D Isometric/Characters/Player"

@export var spawn_camera: bool = true
@export var spawn_lantern: bool = true

var main = null
var direction: int = 2
var _sprite: Sprite2D
var _anim_cache: Dictionary = {}
var _current_anim: String = ""
var _frame_t: float = 0.0
var _anim_locked: float = 0.0
var attacking: bool = false
var camera: Camera2D
var lantern: PointLight2D
var manual_lift_debug: float = 0.0
var mouse_held: bool = false
var right_mouse_held: bool = false
var click_target: Vector2 = Vector2.ZERO
var has_click_target: bool = false
const CLICK_ARRIVE_RADIUS := 6.0
var attack_cooldown: float = 0.0
var _attack_chain_idx: int = 0
# Tighter recovery so held right-click chains swings briskly. Swing anim
# is 15 frames @ 22 fps ≈ 0.68s, so we recover slightly before then to
# overlap the windup of the next swing for a fluid combo feel.
const ATTACK_RECOVER := 0.18
const ATTACK_LOCK := 0.55   # how long the swing anim "owns" the body
const ATTACK_FPS_FAST := 22.0

func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = true
	_sprite.region_enabled = true
	_sprite.offset = Vector2(0, -42)
	add_child(_sprite)
	_play("Idle", DEFAULT_FPS)
	z_index = 250
	if spawn_camera:
		camera = Camera2D.new()
		camera.name = "Camera2D"
		camera.zoom = Vector2(1.5, 1.5)
		add_child(camera)
		camera.make_current()

func _anim_tex(name: String) -> Texture2D:
	if _anim_cache.has(name):
		return _anim_cache[name]
	var path := "%s/%s.png" % [ASSET_DIR, name]
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_anim_cache[name] = t
	return t

func _play(name: String, fps: float, locked: float = 0.0) -> void:
	if _current_anim == name and locked <= 0.0:
		return
	var t := _anim_tex(name)
	if t == null:
		if name != "Idle":
			_play("Idle", DEFAULT_FPS)
		return
	_sprite.texture = t
	_current_anim = name
	_frame_t = 0.0
	if locked > 0.0:
		_anim_locked = locked
	_update_region()

func _update_region() -> void:
	var col: int = int(floor(_frame_t)) % COLS
	var row: int = clampi(direction, 0, ROWS - 1)
	_sprite.region_rect = Rect2(col * FRAME_W, row * FRAME_H, FRAME_W, FRAME_H)

func _process(delta: float) -> void:
	_anim_locked = max(0.0, _anim_locked - delta)
	attack_cooldown = max(0.0, attack_cooldown - delta)
	# Continuous attacks while right-mouse is held — re-fire as soon as
	# the swing recovery has elapsed.
	if right_mouse_held and not attacking and attack_cooldown <= 0.0:
		_start_attack()
	var fps: float = ATTACK_FPS if _current_anim.begins_with("Attack") \
			else (RUN_FPS if _current_anim == "Run" else DEFAULT_FPS)
	_frame_t += delta * fps
	_update_region()

	if _anim_locked > 0.0:
		return

	# Movement input. WASD wins over the click target — pressing a key
	# overrides any pending mouse-walk.
	var v := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	if v.length() <= 0.001 and (mouse_held or has_click_target):
		# Click-to-move: walk toward the latest left-click position. While
		# the button is held, retarget every frame to follow the cursor.
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
		var blocked_by_cell: bool = false
		if main and main.has_method("is_blocked"):
			var c: Vector2i = main._screen_to_grid(next_pos)
			blocked_by_cell = main.is_blocked(c)
		# Body-radius collision against living goblins so the player can't
		# walk through them. Slide along the contact instead of stopping
		# dead so movement still feels responsive.
		if not blocked_by_cell and not _goblin_blocks(next_pos):
			position = next_pos
		elif not blocked_by_cell:
			# Try sliding on each axis separately so the player skims past
			# along walls of bodies rather than freezing.
			var slide_x := position + Vector2(step.x, 0)
			if not _goblin_blocks(slide_x):
				position = slide_x
			else:
				var slide_y := position + Vector2(0, step.y)
				if not _goblin_blocks(slide_y):
					position = slide_y
		direction = _vec_to_dir(v)
		_play("Run", RUN_FPS)
	else:
		_play("Idle", DEFAULT_FPS)

	# Constant +48 lift to clear ground tiles + manual debug nudge.
	const FIXED_LIFT := 48.0
	_sprite.position.y = -(FIXED_LIFT + manual_lift_debug)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_PAGEUP:
			manual_lift_debug += 8.0
		elif event.keycode == KEY_PAGEDOWN:
			manual_lift_debug -= 8.0
		elif event.keycode == KEY_HOME:
			manual_lift_debug = 0.0
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				mouse_held = event.pressed
				if event.pressed:
					click_target = get_global_mouse_position()
					has_click_target = true
			MOUSE_BUTTON_RIGHT:
				right_mouse_held = event.pressed
				if event.pressed and not attacking and attack_cooldown <= 0.0:
					_start_attack()
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom(ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom(1.0 / ZOOM_STEP)

func _start_attack() -> void:
	if attacking:
		return
	attacking = true
	attack_cooldown = ATTACK_RECOVER
	# Combo cycle. Attack3 = bow, Attack5 = block/parry — both excluded so
	# held right-click stays a pure melee chain.
	const COMBO := ["Attack1", "Attack2", "Attack4"]
	_attack_chain_idx = (_attack_chain_idx + 1) % COMBO.size()
	var anim_name: String = COMBO[_attack_chain_idx]
	_play(anim_name, ATTACK_FPS_FAST, ATTACK_LOCK)
	# Mouse-driven targeting: face the cursor and aim the swing at the
	# hovered goblin specifically. Falls back to the cone-in-front cone
	# attack if no enemy is hovered.
	var aim: Vector2 = (get_global_mouse_position() - position)
	if aim.length() > 0.001:
		direction = _vec_to_dir(aim)
	if main and main.has_method("attack_at"):
		var facing: Vector2 = aim.normalized() if aim.length() > 0.001 else _dir_to_vec(direction)
		var hovered = main.get("_hovered_enemy")
		if hovered != null and is_instance_valid(hovered) and not hovered.dead:
			# Only land the hit if the hovered enemy is within swing range.
			var d := position.distance_to(hovered.global_position)
			if d < 110.0 and hovered.has_method("take_damage"):
				hovered.take_damage(main.PLAYER_ATTACK_DAMAGE)
				if main.has_method("_spawn_damage_number"):
					main._spawn_damage_number(hovered.global_position + Vector2(0, -32), main.PLAYER_ATTACK_DAMAGE)
				if main.has_method("_camera_shake"):
					main._camera_shake(4.0, 0.18)
		else:
			main.attack_at(position, facing)
	get_tree().create_timer(ATTACK_LOCK).timeout.connect(func(): attacking = false)

const GOBLIN_BODY_RADIUS := 32.0

func _goblin_blocks(pos: Vector2) -> bool:
	if main == null or not ("goblins" in main):
		return false
	for g in main.goblins:
		if g == null or not is_instance_valid(g) or g.dead:
			continue
		# Boss has a bigger personal bubble.
		var r: float = GOBLIN_BODY_RADIUS * (1.6 if g.is_boss else 1.0)
		if pos.distance_squared_to(g.global_position) < r * r:
			return true
	return false

func _zoom(factor: float) -> void:
	if camera == null:
		return
	var z := camera.zoom.x * factor
	z = clamp(z, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)

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
