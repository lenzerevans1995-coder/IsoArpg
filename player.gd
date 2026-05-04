extends Node2D

# Animation sheets are 1920x1024 = 15 cols x 8 rows of 128x128 frames.
# The fantasy spritesheet's rows go CLOCKWISE starting at "facing right":
#   0:E (right)  1:SE  2:S (down)  3:SW  4:W (left)  5:NW  6:N (up)  7:NE
const FRAME_W := 128
const FRAME_H := 128
const COLS := 15
const ROWS := 8
const FPS := 12.0
const SPEED := 320.0

const CLICK_ARRIVE_RADIUS := 6.0
const ZOOM_MIN := 0.15
const ZOOM_MAX := 3.0
const ZOOM_STEP := 1.12

const IDLE_PATH   := "res://assets/tilesets/Fantasy tileset - 2D Isometric V1.1/Fantasy tileset - 2D Isometric/Characters/Player/Idle.png"
const WALK_PATH   := "res://assets/tilesets/Fantasy tileset - 2D Isometric V1.1/Fantasy tileset - 2D Isometric/Characters/Player/Walk.png"
const ATTACK_PATH := "res://assets/tilesets/Fantasy tileset - 2D Isometric V1.1/Fantasy tileset - 2D Isometric/Characters/Player/Attack1.png"
const ATTACK_FPS := 18.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var camera: Camera2D = $Camera2D
@onready var lantern: PointLight2D = $Lantern

var idle_tex: Texture2D
var walk_tex: Texture2D
var attack_tex: Texture2D
var direction: int = 0
var anim_time: float = 0.0
var moving: bool = false
var attacking: bool = false
var attack_time: float = 0.0
var attack_hit_fired: bool = false
const ATTACK_IMPACT_TIME := 0.42  # seconds into the swing where the blade lands

# Walking-on-water ripple spawner.
const WATER_RIPPLE_INTERVAL := 0.28
var water_ripple_timer: float = 0.0
var main: Node = null
var mouse_held: bool = false

func _ready() -> void:
	idle_tex = load(IDLE_PATH)
	walk_tex = load(WALK_PATH)
	attack_tex = load(ATTACK_PATH)
	sprite.texture = idle_tex
	sprite.centered = true
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, FRAME_W, FRAME_H)
	sprite.offset = Vector2(0, -26)
	lantern.texture = _make_radial_light_texture(192)
	camera.make_current()

func _make_radial_light_texture(size: int) -> Texture2D:
	# Hand-built radial alpha. GradientTexture2D's FILL_RADIAL leaves the
	# corners outside the radius with the last gradient stop, which Light2D
	# can render as a square halo - this avoids that.
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	var max_r: float = float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var d: float = Vector2(x, y).distance_to(c)
			var t: float = clamp(d / max_r, 0.0, 1.0)
			# pow > 1 gives a softer edge, < 1 gives a harder one.
			var a: float = pow(1.0 - t, 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				mouse_held = event.pressed
			MOUSE_BUTTON_RIGHT:
				if event.pressed and not attacking:
					_start_attack()
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom(ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom(1.0 / ZOOM_STEP)

func _zoom(factor: float) -> void:
	var z: Vector2 = camera.zoom * factor
	z.x = clamp(z.x, ZOOM_MIN, ZOOM_MAX)
	z.y = clamp(z.y, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = z

func _start_attack() -> void:
	var to_cursor: Vector2 = get_global_mouse_position() - position
	if to_cursor.length() > 1.0:
		direction = _vec_to_dir(to_cursor)
	attacking = true
	attack_time = 0.0
	attack_hit_fired = false

func _process(delta: float) -> void:
	# Attack animation locks movement until the swing finishes.
	if attacking:
		attack_time += delta
		# Fire the actual hit at mid-swing, not on key-down, so particles and
		# flora destruction sync with the visible blade contact.
		if not attack_hit_fired and attack_time >= ATTACK_IMPACT_TIME:
			attack_hit_fired = true
			if main and main.has_method("attack_at"):
				main.attack_at(position, main.dir_to_vec(direction))
		var aframe: int = int(attack_time * ATTACK_FPS)
		if aframe >= COLS:
			attacking = false
		else:
			sprite.texture = attack_tex
			sprite.region_rect = Rect2(aframe * FRAME_W, direction * FRAME_H, FRAME_W, FRAME_H)
			moving = false
			return

	# Keyboard takes priority over mouse hold-to-walk.
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
	if moving:
		direction = _vec_to_dir(move_v)
		var step := move_v * SPEED * delta
		var target_pos := position + step
		if not _cell_blocked(target_pos):
			position = target_pos
		else:
			var tx := position + Vector2(step.x, 0)
			if not _cell_blocked(tx):
				position = tx
			else:
				var ty := position + Vector2(0, step.y)
				if not _cell_blocked(ty):
					position = ty

	anim_time += delta
	var frame: int = int(anim_time * FPS) % COLS
	sprite.texture = walk_tex if moving else idle_tex
	sprite.region_rect = Rect2(frame * FRAME_W, direction * FRAME_H, FRAME_W, FRAME_H)

	# Walking on water? Drop a fading ripple at the player position every
	# WATER_RIPPLE_INTERVAL seconds.
	if moving and main and main.has_method("is_water_cell"):
		water_ripple_timer -= delta
		if water_ripple_timer <= 0.0:
			var cell: Vector2i = _screen_to_grid(position)
			if main.is_water_cell(cell):
				main.spawn_player_ripple(position)
			water_ripple_timer = WATER_RIPPLE_INTERVAL
	else:
		water_ripple_timer = 0.0

func _vec_to_dir(v: Vector2) -> int:
	# Sheet row 0 faces right (+x), increasing CLOCKWISE through SE, S, SW, W, NW, N, NE.
	# atan2(y, x): 0 = right, +pi/2 = down (Godot y-down), so this matches directly.
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
