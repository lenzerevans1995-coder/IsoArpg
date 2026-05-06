extends CharacterBody2D

# Drop-in replacement for player.gd that drives a LayeredCharacter (stacked
# equipment sprites) instead of a single Sprite2D. Loads the saved loadout from
# user://profile.json and uses it to skin the character.
#
# Auto-attack-set per weapon class: mainhand_class drives which Attack anim
# plays (Melee->Attack1, Ranged->Attack2, Magic->Special1).
# Full mount movement: when a mount is equipped, base SPEED * MOUNT_SPEED_MULT
# and the body uses RideIdle/RideRun anims so the rider sits on the mount.
#
# Movement: was Node2D + manual position += step + flora_at-cell pre-check.
# Now CharacterBody2D + velocity + move_and_slide so painted TileMapLayer
# polygons block the player automatically. The legacy _cell_blocked path is
# still consulted as a pre-check for the chunk-streamed world (which has no
# TileSet polygons), so movement works in both worlds.

const FRAME_W := 128
const FRAME_H := 128
const COLS := 15
const FPS := 12.0
const ATTACK_FPS := 18.0
const RUN_FPS := 16.0
const SPEED := 320.0
const MOUNT_SPEED_MULT := 1.6
# Hold Shift to sprint (Run anim + ~40% faster). Tap-to-walk is the default.
const SPRINT_SPEED_MULT := 1.4

const CLICK_ARRIVE_RADIUS := 6.0
const ZOOM_MIN := 0.15
const ZOOM_MAX := 3.0
const ZOOM_STEP := 1.12
const ATTACK_IMPACT_TIME := 0.42
const WATER_RIPPLE_INTERVAL := 0.28

# Dodge: spacebar burst in the current facing direction. Uses AttackRun as the
# dodge anim (the closest visual match in the shipped anim set — quick forward
# lunge) and locks input until it finishes.
const DODGE_DURATION := 0.25
# 230 px/s × 0.20 s ≈ 46 px ≈ 1 iso cell. Was 460 × 0.28 = ~128 px (4 cells).
const DODGE_SPEED := 520.0
const DODGE_COOLDOWN := 0.35
# Dodge anim is picked at trigger time from the dodge direction relative to
# facing: side -> StrafeLeft/Right, backward -> RunBackwards, forward -> CrouchRun.
const DODGE_FPS := 22.0

@export var spawn_camera: bool = true
@export var spawn_lantern: bool = true

var character: LayeredCharacter
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

var _loadout: Dictionary = {}
var _mounted: bool = false
var _running: bool = false
var _current_anim: String = ""

func _ready() -> void:
	# Editor-only body preview lives in the scene so the artist can see
	# the silhouette while positioning the CollisionShape2D. Free it at
	# runtime — LayeredCharacter renders the real layered body instead.
	var preview := get_node_or_null("BodyPreview")
	if preview:
		preview.queue_free()
	character = LayeredCharacter.new()
	add_child(character)
	# Player y-sort: world tiles bump their y by cell.y * 0.001 for SW-priority.
	# To keep the character ON TOP of grass / decor / props at the SAME iso
	# cell, give the player node a much bigger y nudge (~0.5 px) so it always
	# y-sorts after any tile sharing that cell. Sub-pixel; not visible.
	position.y += 0.5
	# Physics body collision: the CollisionShape2D is now a SCENE child
	# of scenes/player_body.tscn so it's visually adjustable in the
	# Godot 2D viewport (drag the handle, change radius). The script
	# only kicks in if the scene wasn't loaded (legacy 'new()' instantiation
	# path), in which case we fall back to a default circle.
	collision_layer = 1
	collision_mask = 1
	var existing_shape := false
	for c in get_children():
		if c is CollisionShape2D:
			existing_shape = true
			break
	if not existing_shape:
		var coll := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 14.0
		coll.shape = shape
		coll.position = Vector2(0, 0)
		add_child(coll)

	_loadout = Loadout.load_or_default()
	Loadout.apply(character, _loadout)
	_mounted = String(_loadout.get("mount", "")) != ""

	if spawn_camera:
		camera = Camera2D.new()
		camera.name = "Camera2D"
		camera.zoom = Vector2(1.5, 1.5)
		add_child(camera)
		camera.make_current()
	if spawn_lantern:
		lantern = PointLight2D.new()
		lantern.name = "Lantern"   # main.gd looks it up by this name
		lantern.texture = _make_radial_light_texture(192)
		lantern.energy = 0.9
		add_child(lantern)

	_play("Idle", FPS, true)

func reload_loadout() -> void:
	_loadout = Loadout.load_or_default()
	Loadout.apply(character, _loadout)
	_mounted = String(_loadout.get("mount", "")) != ""
	_play(_current_anim if _current_anim != "" else "Idle", FPS, true)

var manual_lift_debug: float = 0.0
var _last_grass_cell: Vector2i = Vector2i(99999, 99999)
const MANUAL_LIFT_STEP := 8.0
# Maximum vertical lift speed, in px/s. Bounds the per-frame change in
# character.position.y so cell-to-cell lift transitions read as smooth
# climbing / descending instead of teleporting. 600 px/s ≈ ~6 storeys/s,
# fast enough not to feel laggy on continuous slopes but slow enough that
# a sharp 64 px boundary jump takes ~100 ms to cross.
const LIFT_TRACK_SPEED := 600.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_try_dodge()
		# Manual lift debug nudge: PageUp adds 8 px, PageDown subtracts.
		# HOME resets to 0. Use this to find the correct slope rise by eye —
		# the printed total lift can be plugged into SLOPE_RISE_PER_TILE.
		elif event.keycode == KEY_PAGEUP:
			manual_lift_debug += MANUAL_LIFT_STEP
			print("[manual_lift_debug] +%d (auto+%.1f total: %.1f)" % [int(manual_lift_debug), -character.position.y - manual_lift_debug, -character.position.y])
		elif event.keycode == KEY_PAGEDOWN:
			manual_lift_debug -= MANUAL_LIFT_STEP
			print("[manual_lift_debug] %d (auto+%.1f total: %.1f)" % [int(manual_lift_debug), -character.position.y - manual_lift_debug, -character.position.y])
		elif event.keycode == KEY_HOME:
			manual_lift_debug = 0.0
			print("[manual_lift_debug] reset to 0")
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				mouse_held = event.pressed
			MOUSE_BUTTON_RIGHT:
				right_mouse_held = event.pressed
				if event.pressed and not attacking:
					_start_attack()
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed and camera:
					_zoom(ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed and camera:
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
		character.set_direction(direction)
	attacking = true
	attack_time = 0.0
	attack_hit_fired = false
	var weapon_class: int = int(_loadout.get("mainhand_class", ItemsDB.WeaponClass.NONE))
	var anim: String = ItemsDB.attack_anim_for(weapon_class)
	_play(anim, ATTACK_FPS, false, _on_attack_finished)

func _on_attack_finished() -> void:
	attacking = false
	# Auto-repeat while RMB is held.
	if right_mouse_held and not dodging:
		_start_attack()

func _try_dodge() -> void:
	if dodging or dodge_cooldown_left > 0.0:
		return
	# Pressing space while attacking cancels the swing and dodges in
	# the same direction. Lets the player bail out of a committed
	# attack with a movement burst.
	if attacking:
		attacking = false
		attack_time = 0.0
		attack_hit_fired = false
	# Dodge in the current movement direction if any, else current facing.
	var v := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	# Resolve facing vector (current direction the body is pointed in).
	var facing: Vector2 = main.dir_to_vec(direction) if main and main.has_method("dir_to_vec") else _dir_to_vec(direction)
	if v.length() > 0.1:
		dodge_dir = v.normalized()
	else:
		# No movement input: dodge straight forward in the direction the
		# player is currently facing (not a strafe). Matches user
		# expectation of "jump goes the way I'm pointing".
		dodge_dir = facing.normalized()
	# Pick anim based on dodge_dir relative to facing. Keep direction = facing so
	# the strafe anims read correctly (StrafeLeft means leftward relative to where
	# the character is currently looking).
	var fwd: float = facing.dot(dodge_dir)              # +1 = forward, -1 = backward
	# Spacebar plays the AttackRun animation (closest "rolling forward
	# burst" the layered character pack ships). Backward dodges fall
	# back to RunBackwards since AttackRun only reads going forward.
	var anim: String = "AttackRun" if fwd >= -0.3 else "RunBackwards"
	character.set_direction(direction)
	dodging = true
	dodge_time = 0.0
	_play(anim, DODGE_FPS, false, _on_dodge_finished)

func _dir_to_vec(d: int) -> Vector2:
	var a := float(d) * (TAU / 8.0)
	return Vector2(cos(a), sin(a))

func _on_dodge_finished() -> void:
	dodging = false
	dodge_cooldown_left = DODGE_COOLDOWN

func take_damage(amount: int) -> void:
	if main and main.has_method("take_player_damage"):
		main.take_player_damage(amount)

func _process(delta: float) -> void:
	if dodge_cooldown_left > 0.0:
		dodge_cooldown_left = max(0.0, dodge_cooldown_left - delta)
	if dodging:
		dodge_time += delta
		# Pre-check legacy chunk-world collision; if blocked, zero out
		# the axis manually. Then move_and_slide applies physics on top
		# (so painted-world polygons stop us regardless).
		var dodge_step := dodge_dir * DODGE_SPEED * delta
		var dv := dodge_dir * DODGE_SPEED
		if _cell_blocked(position + dodge_step):
			if not _cell_blocked(position + Vector2(dodge_step.x, 0)):
				dv.y = 0.0
			elif not _cell_blocked(position + Vector2(0, dodge_step.y)):
				dv.x = 0.0
			else:
				dv = Vector2.ZERO
		velocity = dv
		move_and_slide()
		if dodge_time >= DODGE_DURATION:
			# Fallback in case the finished_cb didn't fire (e.g. anim re-triggered).
			_on_dodge_finished()
		return
	if attacking:
		attack_time += delta
		if not attack_hit_fired and attack_time >= ATTACK_IMPACT_TIME:
			attack_hit_fired = true
			if main and main.has_method("attack_at"):
				main.attack_at(position, main.dir_to_vec(direction))
		# Movement is locked during the attack swing.
		return

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
	if _mounted:
		speed *= MOUNT_SPEED_MULT
	elif _running:
		speed *= SPRINT_SPEED_MULT

	if moving:
		direction = _vec_to_dir(move_v)
		character.set_direction(direction)
		# Pre-check legacy chunk-world collision (flora_at lookup) and
		# zero out the axis if blocked. Then move_and_slide handles the
		# painted-world TileMapLayer polygons on top.
		var step := move_v * speed * delta
		var v := move_v * speed
		if _cell_blocked(position + step):
			if not _cell_blocked(position + Vector2(step.x, 0)):
				v.y = 0.0
			elif not _cell_blocked(position + Vector2(0, step.y)):
				v.x = 0.0
			else:
				v = Vector2.ZERO
		velocity = v
		move_and_slide()
	else:
		velocity = Vector2.ZERO

	# Pick anim. Mount swaps to Ride*; otherwise Walk/Run/Idle.
	# Run only triggers while Shift is held; otherwise Walk for both keyboard
	# and mouse-held movement (the previous always-Run behaviour read awkwardly).
	var anim: String
	var anim_fps: float = FPS
	if _mounted:
		anim = "RideRun" if moving else "RideIdle"
	elif moving:
		if _running:
			anim = "Run"
			anim_fps = RUN_FPS
		else:
			anim = "Walk"
	else:
		anim = "Idle"
	if anim != _current_anim:
		_play(anim, anim_fps, true)

	# Lift the visible character when standing on a hill plateau, so the
	# player reads as walking on the elevated surface. Cliff perimeter cells
	# are blocked, so this only fires once the player is genuinely on top.
	# Constant +48 lift: the player floats slightly above ground always so
	# the character draws cleanly over tile pixels, and the only thing that
	# limits movement is the pixel-level wall collision in
	# terrain_lift.is_blocked_at_pos. No slope chains, no rule lookups —
	# the +48 keeps z-sort stable and the world looks the same height-wise
	# everywhere. manual_lift_debug stays so PageUp/Down still nudges for
	# testing.
	const FIXED_LIFT := 48.0
	character.position.y = -(FIXED_LIFT + manual_lift_debug)
	# z_index left at 0 so y-sort governs depth ordering (tiles vs player
	# sort by their screen Y under the painted_world's y_sort_enabled
	# parent). Was 250 in the chunk-streamed world to force the player
	# above explicit layer-z tiles, but that overrides y-sort entirely
	# and made the canopy never hide the player. y-sort + tile
	# y_sort_origin is the correct knob now.

	# Walking-through-grass leaf bursts: small particle pop whenever the
	# player crosses into a NEW tall-grass cell (main.flora_at). Doesn't
	# destroy the grass, just nudges leaves loose for visual feedback.
	if moving and main and "flora_at" in main:
		var grass_cell: Vector2i = _screen_to_grid(position)
		if grass_cell != _last_grass_cell:
			_last_grass_cell = grass_cell
			if main.flora_at.has(grass_cell) and main.has_method("_spawn_grass_burst"):
				main._spawn_grass_burst(position + Vector2(0, -16))
	# Walking-on-water ripples (same as player.gd).
	if moving and main and main.has_method("is_water_cell"):
		water_ripple_timer -= delta
		if water_ripple_timer <= 0.0:
			var cell: Vector2i = _screen_to_grid(position)
			if main.is_water_cell(cell):
				main.spawn_player_ripple(position)
			water_ripple_timer = WATER_RIPPLE_INTERVAL
	else:
		water_ripple_timer = 0.0

func _play(anim: String, fps: float, looping: bool, finished_cb: Callable = Callable()) -> void:
	_current_anim = anim
	character.play_anim(anim, fps, looping, finished_cb)

func _vec_to_dir(v: Vector2) -> int:
	var angle := atan2(v.y, v.x)
	if angle < 0.0:
		angle += TAU
	return int(round(angle / (TAU / 8.0))) % 8

func _cell_blocked(world_pos: Vector2) -> bool:
	if main == null:
		return false
	# Pixel-level wall collision first: only block when the wall sprite's
	# art is actually opaque under our column. That way thin cliffs / cave
	# walls only stop the player on the strip the visible pixels cover,
	# not the whole 128x64 cell footprint.
	if main.terrain_lift and main.terrain_lift.is_blocked_at_pos(world_pos):
		return true
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
