extends Node2D

# Standalone effects-test arena. 10×10 isometric ground grid + a Player
# and Enemy marker, plus a HUD that lets you pick any .efkefc from the
# archer-test VFX folder and fire it from any point to any point.
#
# Endpoint modes: PLAYER, ENEMY, CLICK (click anywhere on the grid).
#
# Drop this scene into Godot's Run Specific Scene to test FX without
# loading the full game world. Root node is named "Main" with a `world`
# property so ArcherShotFX's main-world lookup works as expected.

const ArcherShotFX := preload("res://archer_shot_fx.gd")
const VFX_DIR := "res://assets/effects/archer_test/evfxshoot/VFX"

const GRID_W := 10
const GRID_H := 10
const TILE_W := 128       # iso diamond width
const TILE_H := 64        # iso diamond height (2:1 ratio like the main game)

@onready var world: Node2D = $World
@onready var _player: Node2D = $World/Player
@onready var _enemy: Node2D = $World/Enemy
@onready var _camera: Camera2D = $Camera
@onready var _hud: CanvasLayer = $HUD

enum Endpoint { PLAYER, ENEMY, CLICK }
# UI label is "End" → drives _start_mode; user wants End=Enemy as default.
# UI label is "Start" → drives _end_mode; user wants Start=Player as default.
var _start_mode: int = Endpoint.ENEMY
var _end_mode: int = Endpoint.PLAYER
var _click_pos: Vector2 = Vector2.ZERO

var _picker: OptionButton
var _coords_lbl: Label
var _start_btns: Array[Button] = []
var _end_btns: Array[Button] = []
var _scale_slider: HSlider
var _scale_lbl: Label
var _pixel_slider: HSlider
var _pixel_lbl: Label
var _dist_slider: HSlider
var _dist_lbl: Label
var _enemy_drift_t: float = 0.0
var _enemy_anchor: Vector2 = Vector2.ZERO

# Body-centre offsets for sprite-mounted endpoints — match the in-scene
# Sprite2D `offset` so effects spawn at the centre of the visible body.
const PLAYER_BODY_OFFSET := Vector2(0, -42)
const ENEMY_BODY_OFFSET := Vector2(0, -50)

func _ready() -> void:
	name = "Main"
	_build_iso_grid()
	_build_hud()
	_enemy_anchor = _enemy.global_position
	set_process(true)

# Re-place the goblin so that base + distance × factor gives the value
# you'd dial into the Base Scale slider — i.e. dragging the slider drags
# the goblin closer to or further from the player along the original
# anchor direction. With factor = 0 we keep the goblin at its anchor
# (no distance solution exists when factor is zero).
func _sync_goblin_distance() -> void:
	if _scale_slider == null or _dist_slider == null:
		return
	var factor: float = _dist_slider.value
	if factor <= 0.0001:
		return
	# Solve for distance: target_scale = base + dist × factor → dist = base / factor
	# (where the slider value IS the "target scale at the goblin's position")
	var target_scale: float = _scale_slider.value
	var dist: float = max(0.0, target_scale / factor)
	var origin: Vector2 = _player.global_position + PLAYER_BODY_OFFSET
	var direction: Vector2 = (_enemy_anchor + ENEMY_BODY_OFFSET - origin).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	# Subtract body offset so the goblin's foot lands `dist` from player body.
	_enemy.global_position = origin + direction * dist - ENEMY_BODY_OFFSET

func _process(_dt: float) -> void:
	# Goblin drift disabled — tracking already verified working. To
	# re-enable for testing, uncomment the block below.
	# _enemy_drift_t += _dt
	# var radius: float = 64.0
	# _enemy.global_position = _enemy_anchor + Vector2(
	#     cos(_enemy_drift_t * 1.4) * radius,
	#     sin(_enemy_drift_t * 1.4) * radius * 0.5
	# )
	pass

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_click_pos = get_global_mouse_position()
			if _coords_lbl:
				_coords_lbl.text = "Click pos: %.0f, %.0f" % [_click_pos.x, _click_pos.y]
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.zoom *= 1.15
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.zoom /= 1.15

# ---- Grid ----------------------------------------------------------------

func _build_iso_grid() -> void:
	var grid: Node2D = Node2D.new()
	grid.name = "Tiles"
	grid.y_sort_enabled = true
	world.add_child(grid)
	for r in range(GRID_H):
		for c in range(GRID_W):
			var iso: Vector2 = _grid_to_iso(c, r)
			var tile: Polygon2D = Polygon2D.new()
			tile.polygon = PackedVector2Array([
				Vector2(0, -TILE_H * 0.5),
				Vector2(TILE_W * 0.5, 0),
				Vector2(0, TILE_H * 0.5),
				Vector2(-TILE_W * 0.5, 0),
			])
			var checker: bool = (c + r) % 2 == 0
			tile.color = Color(0.32, 0.40, 0.30) if checker else Color(0.26, 0.34, 0.24)
			tile.position = iso
			grid.add_child(tile)
			# Subtle grid-line accent on the edges.
			var lines: Line2D = Line2D.new()
			lines.points = PackedVector2Array([
				Vector2(0, -TILE_H * 0.5),
				Vector2(TILE_W * 0.5, 0),
				Vector2(0, TILE_H * 0.5),
				Vector2(-TILE_W * 0.5, 0),
				Vector2(0, -TILE_H * 0.5),
			])
			lines.width = 1.0
			lines.default_color = Color(0.1, 0.12, 0.1, 0.55)
			lines.position = iso
			grid.add_child(lines)
	# Drop the player/enemy onto sensible cells.
	_player.global_position = _grid_to_iso(2, 5)
	_enemy.global_position = _grid_to_iso(8, 4)
	# Centre the camera on the middle of the grid so everything fits.
	_camera.global_position = _grid_to_iso(GRID_W / 2, GRID_H / 2)
	_camera.make_current()

func _grid_to_iso(c: int, r: int) -> Vector2:
	# Standard 2:1 iso projection centred on (0,0).
	return Vector2((c - r) * TILE_W * 0.5, (c + r) * TILE_H * 0.5)

# ---- HUD -----------------------------------------------------------------

func _build_hud() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.offset_left = 16
	panel.offset_top = 16
	panel.offset_right = 380
	panel.offset_bottom = 360
	_hud.add_child(panel)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	_add_section(vb, "FX Test Arena", 18)

	# Effect picker.
	_add_section(vb, "Effect", 13)
	_picker = OptionButton.new()
	for fn in _list_efkefc(VFX_DIR):
		_picker.add_item(fn)
	if _picker.item_count > 0:
		_picker.selected = 0
	vb.add_child(_picker)

	# Spawn point  (the "Start" var, internally — labels swapped per the
	# user's mapping where what previously was "Start" reads as End).
	_add_section(vb, "End", 13)
	var start_row: HBoxContainer = HBoxContainer.new()
	vb.add_child(start_row)
	_start_btns.append(_make_toggle_btn(start_row, "Player", _on_start_player))
	_start_btns.append(_make_toggle_btn(start_row, "Enemy", _on_start_enemy))
	_start_btns.append(_make_toggle_btn(start_row, "Click", _on_start_click))
	_highlight_btn(_start_btns, _start_mode)

	# Aim point (the "End" var internally — also swapped).
	_add_section(vb, "Start", 13)
	var end_row: HBoxContainer = HBoxContainer.new()
	vb.add_child(end_row)
	_end_btns.append(_make_toggle_btn(end_row, "Player", _on_end_player))
	_end_btns.append(_make_toggle_btn(end_row, "Enemy", _on_end_enemy))
	_end_btns.append(_make_toggle_btn(end_row, "Click", _on_end_click))
	_highlight_btn(_end_btns, _end_mode)

	# Base FX scale (added at zero distance; gets a per-pixel boost via
	# the Distance Scale slider below).
	_add_section(vb, "Base Scale  (at 0 distance)", 13)
	_scale_slider = HSlider.new()
	_scale_slider.min_value = 0.0
	_scale_slider.max_value = 30.0
	_scale_slider.step = 0.5
	_scale_slider.value = 2.5
	_scale_slider.custom_minimum_size = Vector2(0, 24)
	vb.add_child(_scale_slider)
	_scale_lbl = Label.new()
	_scale_lbl.text = "base = 2.5"
	vb.add_child(_scale_lbl)
	_scale_slider.value_changed.connect(func(v: float) -> void:
		_scale_lbl.text = "base = %.1f" % v
		_sync_goblin_distance()
	)

	# Per-pixel distance scaling. Final formula is ADDITIVE so you can
	# tune "minimum size" (base) and "growth per pixel" independently:
	#     final_scale = base + distance × factor
	# Default factor 0.045 gives ≈22 at the test scene's player↔enemy
	# distance (~480 px) — matches what you saw working at scale 20-22.5.
	_add_section(vb, "Distance Scale  (× per pixel)", 13)
	_dist_slider = HSlider.new()
	_dist_slider.min_value = 0.0
	_dist_slider.max_value = 0.50
	_dist_slider.step = 0.001
	_dist_slider.value = 0.24
	_dist_slider.custom_minimum_size = Vector2(0, 24)
	vb.add_child(_dist_slider)
	_dist_lbl = Label.new()
	_dist_lbl.text = "factor = 0.240"
	vb.add_child(_dist_lbl)
	_dist_slider.value_changed.connect(func(v: float) -> void:
		var lbl: String = "  (constant)" if v <= 0.0001 else ""
		_dist_lbl.text = "factor = %.3f%s" % [v, lbl]
		_sync_goblin_distance()
	)

	# Pixelation slider.
	_add_section(vb, "Pixelation", 13)
	_pixel_slider = HSlider.new()
	_pixel_slider.min_value = 1.0
	_pixel_slider.max_value = 2.0
	_pixel_slider.step = 0.1
	_pixel_slider.value = 1.1
	_pixel_slider.custom_minimum_size = Vector2(0, 24)
	vb.add_child(_pixel_slider)
	_pixel_lbl = Label.new()
	_pixel_lbl.text = "pixel size = 1.1"
	vb.add_child(_pixel_lbl)
	_pixel_slider.value_changed.connect(func(v: float) -> void:
		_pixel_lbl.text = "pixel size = %.1f" % v
		ArcherShotFX.set_pixel_size(self, v)
	)

	# Spawn button.
	var spawn_btn: Button = Button.new()
	spawn_btn.text = "FIRE FX  (or press Space)"
	spawn_btn.custom_minimum_size = Vector2(0, 36)
	spawn_btn.pressed.connect(_fire_fx)
	vb.add_child(spawn_btn)

	# Coordinate read-out.
	_coords_lbl = Label.new()
	_coords_lbl.text = "Click anywhere on the grid for the CLICK endpoint."
	_coords_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(_coords_lbl)

	# Hint footer.
	var hint: Label = Label.new()
	hint.text = "Wheel = zoom · LMB = set click pos · Space = fire"
	hint.modulate = Color(1, 1, 1, 0.6)
	vb.add_child(hint)

func _add_section(parent: VBoxContainer, text: String, font_size: int) -> void:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	parent.add_child(lbl)

func _make_toggle_btn(parent: HBoxContainer, text: String, cb: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(80, 28)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _highlight_btn(btns: Array, idx: int) -> void:
	for i in range(btns.size()):
		var b: Button = btns[i]
		b.modulate = Color(1, 1, 0.6) if i == idx else Color(1, 1, 1)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_fire_fx()

# ---- Endpoint pickers ----------------------------------------------------

func _on_start_player() -> void: _start_mode = Endpoint.PLAYER; _highlight_btn(_start_btns, _start_mode)
func _on_start_enemy() -> void:  _start_mode = Endpoint.ENEMY;  _highlight_btn(_start_btns, _start_mode)
func _on_start_click() -> void:  _start_mode = Endpoint.CLICK;  _highlight_btn(_start_btns, _start_mode)
func _on_end_player() -> void:   _end_mode = Endpoint.PLAYER;   _highlight_btn(_end_btns, _end_mode)
func _on_end_enemy() -> void:    _end_mode = Endpoint.ENEMY;    _highlight_btn(_end_btns, _end_mode)
func _on_end_click() -> void:    _end_mode = Endpoint.CLICK;    _highlight_btn(_end_btns, _end_mode)

# ---- Spawn ---------------------------------------------------------------

func _fire_fx() -> void:
	if _picker == null or _picker.selected < 0:
		return
	var fn: String = _picker.get_item_text(_picker.selected)
	var path: String = "%s/%s" % [VFX_DIR, fn]
	# Per the user's mapping: the UI's "End" section drives `_start_mode`
	# (the var actually labelled End on screen) and vice versa, so we pass
	# them swapped to spawn() — `source_pos` is the spawn-point, which
	# corresponds to the on-screen End label.
	var src: Vector2 = _resolve(_start_mode)
	var dst: Vector2 = _resolve(_end_mode)
	var base_scale: float = _scale_slider.value if _scale_slider else 1.0
	var dist_factor: float = _dist_slider.value if _dist_slider else 0.045
	var dist: float = src.distance_to(dst)
	# Additive: final_scale = base + distance × factor. With base=1 and
	# factor=0.045, the goblin at ~476 px gives scale ≈22.4 (matches the
	# 20-22.5 sweet spot you found visually). Closer enemy = lower scale.
	var s: float = base_scale + dist * dist_factor
	# Pass the target's Node2D when the END mode points at Player or Enemy
	# so the runner's _process loop can re-aim the effect each frame.
	var track: Node2D = null
	var track_off: Vector2 = Vector2.ZERO
	match _end_mode:
		Endpoint.PLAYER:
			track = _player
			track_off = PLAYER_BODY_OFFSET
		Endpoint.ENEMY:
			track = _enemy
			track_off = ENEMY_BODY_OFFSET
	print("[fx_test] firing ", fn, " from ", src, " → ", dst,
		"  dist=%.0f" % dist, "  base=%.1f" % base_scale,
		"  factor=%.3f" % dist_factor, "  final_scale=%.1f" % s,
		"  track=", track)
	ArcherShotFX.spawn(world, src, dst, path, s, track, track_off)

func _resolve(mode: int) -> Vector2:
	# Player/Enemy resolve to BODY-CENTRE world positions (not feet) so
	# effects spawn / aim at the visible torso rather than below it.
	match mode:
		Endpoint.PLAYER: return _player.global_position + PLAYER_BODY_OFFSET
		Endpoint.ENEMY:  return _enemy.global_position + ENEMY_BODY_OFFSET
		_:               return _click_pos

# ---- Helpers -------------------------------------------------------------

func _list_efkefc(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d: DirAccess = DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var fn: String = d.get_next()
	while fn != "":
		if fn.ends_with(".efkefc"):
			out.append(fn)
		fn = d.get_next()
	d.list_dir_end()
	out.sort()
	return out
