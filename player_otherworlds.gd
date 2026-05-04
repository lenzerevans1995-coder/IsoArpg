extends Node2D

# Player driver using a LayeredOtherworldsCharacter (PVGames OtherWorlds kit).
# Replaces player_layered.gd. Movement, dodge, attack, mount, and ripple logic
# are ported from player_layered.gd; the only difference is the character node
# is a LayeredOtherworldsCharacter and the anim names match the 50x50 catalog.

const PROFILE_PATH := "user://otherworlds_profile.json"

const FRAME_W := 128
const FRAME_H := 128
const FPS := 6.0
const ATTACK_FPS := 10.0
const RUN_FPS := 8.0
const SPEED := 320.0
const SPRINT_SPEED_MULT := 1.4

const CLICK_ARRIVE_RADIUS := 6.0
const ZOOM_MIN := 0.15
const ZOOM_MAX := 3.0
const ZOOM_STEP := 1.12
const ATTACK_IMPACT_TIME := 0.18
const WATER_RIPPLE_INTERVAL := 0.28

const DODGE_DURATION := 0.28
const DODGE_SPEED := 460.0
const DODGE_COOLDOWN := 0.35
const DODGE_FPS := 22.0

# Anim names for the OtherWorlds catalog (matches keys in character_pieces_catalog.json).
const ANIM_IDLE := "Idle 1"
const ANIM_WALK := "Walk"
const ANIM_RUN := "Run"
const ANIM_ATTACK := "1-H Attack 1"
const ANIM_DODGE := "Evade Roll"

@export var spawn_camera: bool = true
@export var spawn_lantern: bool = true

var character: Node2D   # CompositeCharacter — kept loose to avoid class_name load-order issues.
var camera: Camera2D
var lantern: PointLight2D

var direction: int = 2
var moving: bool = false
var attacking: bool = false
var attack_time: float = 0.0
var attack_hit_fired: bool = false
var water_ripple_timer: float = 0.0
var mouse_held: bool = false
var right_mouse_held: bool = false
var main: Node = null
var dodging: bool = false
var dodge_time: float = 0.0
var dodge_cooldown_left: float = 0.0
var dodge_dir: Vector2 = Vector2.ZERO

var _profile: Dictionary = {}
var _running: bool = false
var _current_anim: String = ""

func _ready() -> void:
	var CompositeCharacter := load("res://composite_character.gd")
	character = CompositeCharacter.new()
	add_child(character)
	character.display_size = 96.0
	_load_profile()
	_apply_profile_to_character()

	if spawn_camera:
		camera = Camera2D.new()
		camera.name = "Camera2D"
		camera.zoom = Vector2(1.5, 1.5)
		add_child(camera)
		camera.make_current()
	if spawn_lantern:
		lantern = PointLight2D.new()
		lantern.name = "Lantern"
		lantern.texture = _make_radial_light_texture(192)
		lantern.energy = 0.9
		add_child(lantern)
	_play(ANIM_IDLE, FPS, true)

func _load_profile() -> void:
	if not FileAccess.file_exists(PROFILE_PATH):
		_profile = {
			"kit": "female",
			"slots": {"Base": "OtherWorlds_1", "Bottom": "OtherWorlds_1", "Top": "OtherWorlds_1", "Hair": "OtherWorlds_1"},
			"colors": {},
		}
		return
	var f := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		_profile = d

func _apply_profile_to_character() -> void:
	character.kit = String(_profile.get("kit", "female"))
	character.reload_catalog()
	# Bake-on-equip: the player only ever holds one composite spritesheet.
	# CompositeBaker.ensure_baked is a no-op when the same profile was already
	# baked (it caches by hash), so equip-changes are nearly free.
	var Baker := load("res://composite_baker.gd")
	var path: String = Baker.ensure_baked(_profile)
	if path != "":
		character.set_composite_path(path)
	# Shader params from the saved profile (pixelate + palette quantize).
	if _profile.has("pixel_size"):
		character.set_shader_pixel_size(float(_profile.pixel_size))
	if _profile.has("palette_mix"):
		character.set_shader_palette_mix(float(_profile.palette_mix))

func reload_profile() -> void:
	_load_profile()
	_apply_profile_to_character()
	_play(_current_anim if _current_anim != "" else ANIM_IDLE, FPS, true)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_try_dodge()
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				mouse_held = event.pressed
			MOUSE_BUTTON_RIGHT:
				right_mouse_held = event.pressed
				if event.pressed and not attacking:
					_start_attack()
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed and camera: _zoom(ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed and camera: _zoom(1.0 / ZOOM_STEP)

func _zoom(factor: float) -> void:
	var z: Vector2 = camera.zoom * factor
	z.x = clamp(z.x, ZOOM_MIN, ZOOM_MAX)
	z.y = clamp(z.y, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = z

func _start_attack() -> void:
	# Auto-target the nearest live spider within ~1.4 attack-radius. Falls
	# back to facing the cursor if no enemy is in range.
	var aim: Vector2 = get_global_mouse_position() - position
	if main and main.has_method("nearest_enemy_target"):
		var target: Node2D = main.nearest_enemy_target(position, 220.0)
		if target:
			aim = target.position - position
	if aim.length() > 1.0:
		direction = _vec_to_dir(aim)
		character.set_direction(direction)
	attacking = true
	attack_time = 0.0
	attack_hit_fired = false
	_play(ANIM_ATTACK, ATTACK_FPS, false, _on_attack_finished)
	# Spawn a slash overlay parented to the player so it tracks movement.
	var Effect := load("res://attack_effect.gd")
	var fx: Node2D = Effect.new()
	fx.effect_set = "Slash1"
	fx.anim_name = "Attack1"
	fx.direction = direction
	fx.position = Vector2(0, -32)   # relative to player origin (feet)
	fx.z_index = 10
	add_child(fx)

func _on_attack_finished() -> void:
	attacking = false
	if right_mouse_held and not dodging:
		_start_attack()

func _try_dodge() -> void:
	if dodging or dodge_cooldown_left > 0.0:
		return
	# Dodge interrupts an in-progress attack so the player can bail out of a
	# whiff. The RMB-hold loop will start a fresh swing once the dodge ends.
	if attacking:
		attacking = false
		attack_hit_fired = true
	var v := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	if v.length() > 0.1:
		dodge_dir = v.normalized()
	else:
		# No movement input → dodge toward the cursor (forward).
		var to_cursor: Vector2 = get_global_mouse_position() - position
		if to_cursor.length() > 1.0:
			dodge_dir = to_cursor.normalized()
		else:
			dodge_dir = _dir_to_vec(direction)
	# Face the dodge direction so the anim reads correctly.
	direction = _vec_to_dir(dodge_dir)
	character.set_direction(direction)
	dodging = true
	dodge_time = 0.0
	_play(ANIM_DODGE, DODGE_FPS, false, _on_dodge_finished)

func _dir_to_vec(d: int) -> Vector2:
	var a := float(d) * (TAU / 8.0)
	return Vector2(cos(a), sin(a))

func _on_dodge_finished() -> void:
	dodging = false
	dodge_cooldown_left = DODGE_COOLDOWN
	# Resume auto-attacking if RMB is still held.
	if right_mouse_held and not attacking:
		_start_attack()

func take_damage(amount: int) -> void:
	if main and main.has_method("take_player_damage"):
		main.take_player_damage(amount)

func _process(delta: float) -> void:
	if dodge_cooldown_left > 0.0:
		dodge_cooldown_left = max(0.0, dodge_cooldown_left - delta)
	if dodging:
		dodge_time += delta
		var step := dodge_dir * DODGE_SPEED * delta
		var target_pos := position + step
		if not _cell_blocked(target_pos):
			position = target_pos
		if dodge_time >= DODGE_DURATION:
			_on_dodge_finished()
		return
	if attacking:
		attack_time += delta
		if not attack_hit_fired and attack_time >= ATTACK_IMPACT_TIME:
			attack_hit_fired = true
			if main and main.has_method("attack_at"):
				main.attack_at(position, main.dir_to_vec(direction))
		# NOTE: don't return — let movement keep flowing during attacks.

	var input_v := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	var move_v: Vector2 = Vector2.ZERO
	if input_v.length() > 0.1:
		move_v = input_v.normalized()
	elif mouse_held:
		var to_cursor: Vector2 = get_global_mouse_position() - position
		if to_cursor.length() > CLICK_ARRIVE_RADIUS:
			move_v = to_cursor.normalized()

	moving = move_v != Vector2.ZERO
	_running = Input.is_key_pressed(KEY_SHIFT)
	var speed: float = SPEED
	if _running:
		speed *= SPRINT_SPEED_MULT
	if moving:
		direction = _vec_to_dir(move_v)
		character.set_direction(direction)
		var step := move_v * speed * delta
		var target_pos := position + step
		if not _cell_blocked(target_pos):
			position = target_pos

	# Attacks own the anim until they end; movement keeps flowing under them.
	if not attacking:
		var anim: String = ANIM_IDLE
		var anim_fps: float = FPS
		if moving:
			if _running:
				anim = ANIM_RUN
				anim_fps = RUN_FPS
			else:
				anim = ANIM_WALK
		if anim != _current_anim:
			_play(anim, anim_fps, true)

	if main and main.has_method("is_hill_interior"):
		var cell_now: Vector2i = _screen_to_grid(position)
		var lift: float = float(main.HILL_LIFT) if main.is_hill_interior(cell_now) else 0.0
		character.position.y = -lift

	if moving and main and main.has_method("is_water_cell"):
		water_ripple_timer -= delta
		if water_ripple_timer <= 0.0:
			var cell: Vector2i = _screen_to_grid(position)
			if main.is_water_cell(cell):
				main.spawn_player_ripple(position)
			water_ripple_timer = WATER_RIPPLE_INTERVAL
	else:
		water_ripple_timer = 0.0

func _play(anim: String, anim_fps: float, looping: bool, finished_cb: Callable = Callable()) -> void:
	_current_anim = anim
	character.fps = anim_fps
	character.play_anim(anim, looping, finished_cb)

func _vec_to_dir(v: Vector2) -> int:
	var angle := atan2(v.y, v.x)
	if angle < 0.0:
		angle += TAU
	return int(round(angle / (TAU / 8.0))) % 8

func _cell_blocked(world_pos: Vector2) -> bool:
	if main == null:
		return false
	return main.is_blocked(_screen_to_grid(world_pos))

func _screen_to_grid(p: Vector2) -> Vector2i:
	var tw: float = main.TILE_W * 0.5
	var th: float = main.TILE_H * 0.5
	var gx: float = (p.x / tw + p.y / th) * 0.5
	var gy: float = (p.y / th - p.x / tw) * 0.5
	return Vector2i(int(floor(gx)), int(floor(gy)))

func _make_radial_light_texture(size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	var max_r: float = float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var d: float = Vector2(x, y).distance_to(c)
			var t: float = clamp(d / max_r, 0.0, 1.0)
			var a: float = pow(1.0 - t, 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
