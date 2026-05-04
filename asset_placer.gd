extends CanvasLayer

# Toggled with key 3. Picks any image in res://assets/shader_assets/<folder>/
# and lets the user place it in the world with the painterly shader applied.
# Has its own slider set + preview, independent of the monster debug panel.

const ROOT_DIR := "res://assets/shader_assets"
const SHADER_PATH := "res://shaders/monster_painterly.gdshader"
const ISO_GROUND_SHADER_PATH := "res://shaders/iso_ground.gdshader"
const TILE_W := 128
const TILE_H := 64
const SWATCH_PATH := "res://data/swatch_palette.json"

const PARAMS := [
	{"name": "pixel_size",       "min": 1.0,  "max": 24.0, "step": 0.1, "default": 3.0,  "type": "f"},
	{"name": "palette_levels",   "min": 2.0,  "max": 32.0, "step": 1.0, "default": 9.0,  "type": "i"},
	{"name": "saturation",       "min": 0.0,  "max": 2.0,  "step": 0.01,"default": 1.0,  "type": "f"},
	{"name": "contrast",         "min": 0.5,  "max": 2.0,  "step": 0.01,"default": 1.1,  "type": "f"},
	{"name": "brightness",       "min": -0.5, "max": 0.5,  "step": 0.01,"default": 0.0,  "type": "f"},
	{"name": "outline_strength", "min": 0.0,  "max": 1.0,  "step": 0.01,"default": 0.0,  "type": "f"},
	{"name": "alpha_cutoff",     "min": 0.0,  "max": 1.0,  "step": 0.01,"default": 0.35, "type": "f"},
	{"name": "palette_mix",      "min": 0.0,  "max": 1.0,  "step": 0.01,"default": 1.0,  "type": "f"},
]

var main_ref: Node
var panel: PanelContainer
var folder_picker: OptionButton
var name_picker: OptionButton
var variant_label: Label
var status_label: Label
var place_btn: Button
var preview_rect: TextureRect
var size_slider: HSlider
var size_label: Label

var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}
var _shared_palette_tex: Texture2D = null

var _folders: PackedStringArray = []
var _bases_in_folder: Array[String] = []
var _variants_for_base: Array[String] = []
var _variant_idx: int = 0
var _placing: bool = false
var _grabbed: Node2D = null     # ctrl+clicked sprite being dragged
var _grab_offset: Vector2 = Vector2.ZERO
var _display_size: float = 192.0

func _ready() -> void:
	layer = 45
	visible = false
	_shared_palette_tex = _build_palette_texture()

	panel = PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -340
	panel.offset_right = -16
	panel.offset_top = 16
	panel.offset_bottom = -16
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)

	var title := Label.new()
	title.text = "Asset Placer  (key 3)"
	vb.add_child(title)

	folder_picker = _add_dropdown(vb, "folder")
	folder_picker.item_selected.connect(_on_folder_selected)
	name_picker = _add_dropdown(vb, "name")
	name_picker.item_selected.connect(_on_name_selected)

	var var_row := HBoxContainer.new()
	vb.add_child(var_row)
	var var_lbl := Label.new()
	var_lbl.text = "variant"
	var_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var_row.add_child(var_lbl)
	var prev := Button.new()
	prev.text = "<"
	prev.pressed.connect(func(): _cycle_variant(-1))
	var_row.add_child(prev)
	variant_label = Label.new()
	variant_label.text = "-"
	variant_label.custom_minimum_size = Vector2(40, 0)
	variant_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var_row.add_child(variant_label)
	var nxt := Button.new()
	nxt.text = ">"
	nxt.pressed.connect(func(): _cycle_variant(1))
	var_row.add_child(nxt)

	# Preview
	preview_rect = TextureRect.new()
	preview_rect.custom_minimum_size = Vector2(0, 160)
	preview_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_rect.material = _build_shader_material()
	vb.add_child(preview_rect)

	# Sliders
	for p in PARAMS:
		var hb := HBoxContainer.new()
		vb.add_child(hb)
		var nm := Label.new()
		nm.text = p.name
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(nm)
		var vlbl := Label.new()
		vlbl.text = str(p.default)
		hb.add_child(vlbl)
		_value_labels[p.name] = vlbl
		var s := HSlider.new()
		s.min_value = p.min
		s.max_value = p.max
		s.step = p.step
		s.value = p.default
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.value_changed.connect(_on_slider_changed.bind(p))
		vb.add_child(s)
		_sliders[p.name] = s

	# Display size slider
	var size_row := HBoxContainer.new()
	vb.add_child(size_row)
	var size_name := Label.new()
	size_name.text = "size"
	size_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_row.add_child(size_name)
	size_label = Label.new()
	size_label.text = str(int(_display_size))
	size_row.add_child(size_label)
	size_slider = HSlider.new()
	size_slider.min_value = 32
	size_slider.max_value = 512
	size_slider.step = 1
	size_slider.value = _display_size
	size_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_slider.value_changed.connect(_on_size_changed)
	vb.add_child(size_slider)

	place_btn = Button.new()
	place_btn.toggle_mode = true
	place_btn.text = "Place mode (off)"
	place_btn.pressed.connect(_toggle_place_mode)
	vb.add_child(place_btn)

	status_label = Label.new()
	status_label.text = "LMB place  |  Ctrl+LMB grab/move existing"
	status_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	vb.add_child(status_label)

	_scan_folders()
	_apply_all_to_preview()

func _add_dropdown(parent: Container, label: String) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(180, 0)
	row.add_child(ob)
	return ob

func toggle() -> void:
	visible = not visible
	if not visible:
		_placing = false
		_grabbed = null
		place_btn.button_pressed = false
		place_btn.text = "Place mode (off)"
	# Hide trees while placing so the world reads cleanly.
	for t in get_tree().get_nodes_in_group("tree"):
		if t is CanvasItem:
			t.visible = not visible

func _scan_folders() -> void:
	_folders.clear()
	folder_picker.clear()
	var d := DirAccess.open(ROOT_DIR)
	if d == null:
		status_label.text = "no shader_assets dir"
		return
	d.list_dir_begin()
	while true:
		var entry := d.get_next()
		if entry == "":
			break
		if d.current_is_dir() and not entry.begins_with("."):
			_folders.append(entry)
	d.list_dir_end()
	_folders.sort()
	for f in _folders:
		folder_picker.add_item(f)
	if _folders.size() > 0:
		_on_folder_selected(0)

func _on_folder_selected(idx: int) -> void:
	_bases_in_folder.clear()
	name_picker.clear()
	if idx < 0 or idx >= _folders.size():
		return
	var folder: String = "%s/%s" % [ROOT_DIR, _folders[idx]]
	var d := DirAccess.open(folder)
	if d == null:
		return
	var groups: Dictionary = {}
	d.list_dir_begin()
	while true:
		var entry := d.get_next()
		if entry == "":
			break
		if entry.ends_with(".png"):
			var stem: String = entry.get_basename()
			var base: String = stem
			var us := stem.rfind("_")
			if us > 0 and stem.substr(us + 1).is_valid_int():
				base = stem.substr(0, us)
			if not groups.has(base):
				groups[base] = []
			groups[base].append("%s/%s" % [folder, entry])
	d.list_dir_end()
	var keys := groups.keys()
	keys.sort()
	for k in keys:
		_bases_in_folder.append(String(k))
		name_picker.add_item(String(k))
	set_meta("groups", groups)
	if _bases_in_folder.size() > 0:
		_on_name_selected(0)

func _on_name_selected(idx: int) -> void:
	_variants_for_base.clear()
	_variant_idx = 0
	if idx < 0 or idx >= _bases_in_folder.size():
		variant_label.text = "-"
		_update_preview()
		return
	var groups: Dictionary = get_meta("groups", {})
	var paths: Array = groups.get(_bases_in_folder[idx], [])
	paths.sort()
	for p in paths:
		_variants_for_base.append(String(p))
	_update_variant_label()
	_update_preview()

func _cycle_variant(step: int) -> void:
	if _variants_for_base.is_empty():
		return
	_variant_idx = (_variant_idx + step + _variants_for_base.size()) % _variants_for_base.size()
	_update_variant_label()
	_update_preview()

func _update_variant_label() -> void:
	if _variants_for_base.is_empty():
		variant_label.text = "-"
		return
	variant_label.text = "%d / %d" % [_variant_idx + 1, _variants_for_base.size()]

func _update_preview() -> void:
	if _variants_for_base.is_empty():
		preview_rect.texture = null
		return
	preview_rect.texture = load(_variants_for_base[_variant_idx])

func _toggle_place_mode() -> void:
	_placing = place_btn.button_pressed
	place_btn.text = "Place mode (on)" if _placing else "Place mode (off)"

func _on_slider_changed(value: float, p: Dictionary) -> void:
	_value_labels[p.name].text = "%.2f" % value if p.type == "f" else str(int(value))
	_push_uniform(p.name, value, p.type, preview_rect.material as ShaderMaterial)

func _on_size_changed(value: float) -> void:
	_display_size = value
	size_label.text = str(int(value))

func _push_uniform(uname: String, value: float, type: String, mat: ShaderMaterial) -> void:
	if mat == null:
		return
	var v: Variant = int(value) if type == "i" else value
	mat.set_shader_parameter(uname, v)

func _apply_all_to_preview() -> void:
	var mat: ShaderMaterial = preview_rect.material
	for p in PARAMS:
		_push_uniform(p.name, _sliders[p.name].value, p.type, mat)

func _input(event: InputEvent) -> void:
	if not visible or not _placing:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if panel.get_global_rect().has_point(event.position):
			return
		if event.pressed:
			if event.ctrl_pressed:
				_try_grab()
			elif _grabbed == null:
				_place_at_cursor()
			get_viewport().set_input_as_handled()
		else:
			# Release on left-up, regardless of ctrl state.
			if _grabbed != null:
				_grabbed = null
				status_label.text = "released"
				get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if _grabbed and is_instance_valid(_grabbed):
		var world: Node2D = main_ref.world
		_grabbed.position = world.get_local_mouse_position() + _grab_offset

func _try_grab() -> void:
	if main_ref == null:
		return
	var world: Node2D = main_ref.world
	var mouse_world: Vector2 = world.get_local_mouse_position()
	var best: Node2D = null
	var best_d: float = INF
	for n in get_tree().get_nodes_in_group("placed_shader_asset"):
		if not (n is Node2D) or not is_instance_valid(n):
			continue
		var d: float = n.position.distance_to(mouse_world)
		# Reject anything outside the sprite's visible footprint.
		var radius: float = 64.0
		if n is Sprite2D and n.texture:
			var t: Texture2D = n.texture
			radius = max(t.get_width(), t.get_height()) * 0.5 * n.scale.x
		if d < radius and d < best_d:
			best_d = d
			best = n
	if best:
		_grabbed = best
		_grab_offset = best.position - mouse_world
		status_label.text = "grabbed (release to drop)"
	else:
		status_label.text = "no asset under cursor"

func _place_at_cursor() -> void:
	if _variants_for_base.is_empty() or main_ref == null:
		return
	var path: String = _variants_for_base[_variant_idx]
	var tex: Texture2D = load(path)
	if tex == null:
		status_label.text = "load failed: %s" % path
		return
	var world: Node2D = main_ref.world
	var mouse_world: Vector2 = world.get_local_mouse_position()
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = true
	var folder: String = path.get_base_dir().get_file()
	if folder == "ground":
		# Iso ground tile: stretch any square into a 128x64 diamond and use
		# the masking shader. Snap to the grid cell under the cursor.
		s.scale = Vector2(float(TILE_W) / float(tex.get_width()), float(TILE_H) / float(tex.get_height()))
		var ground_mat := ShaderMaterial.new()
		ground_mat.shader = load(ISO_GROUND_SHADER_PATH)
		s.material = ground_mat
		s.position = _snap_to_iso_grid(mouse_world)
	else:
		var max_dim: float = float(max(tex.get_width(), tex.get_height()))
		if max_dim > 0.0:
			s.scale = Vector2.ONE * (_display_size / max_dim)
		s.material = _build_shader_material()
		_apply_all_to_material(s.material as ShaderMaterial)
		s.position = mouse_world
	s.add_to_group("placed_shader_asset")
	world.add_child(s)
	status_label.text = "placed %s" % path.get_file()

func _snap_to_iso_grid(world_pos: Vector2) -> Vector2:
	# Convert screen-space to iso grid cell, then back. Mirrors main.gd's math.
	var tw: float = float(TILE_W) * 0.5
	var th: float = float(TILE_H) * 0.5
	var gx: float = (world_pos.x / tw + world_pos.y / th) * 0.5
	var gy: float = (world_pos.y / th - world_pos.x / tw) * 0.5
	var cell := Vector2i(int(round(gx)), int(round(gy)))
	return Vector2((cell.x - cell.y) * tw, (cell.x + cell.y) * th)

func _apply_all_to_material(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	for p in PARAMS:
		_push_uniform(p.name, _sliders[p.name].value, p.type, mat)

func _build_shader_material() -> ShaderMaterial:
	var shader := load(SHADER_PATH) as Shader
	if shader == null:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("warm_tint", Vector3(1, 1, 1))
	mat.set_shader_parameter("region_uv_min", Vector2(0, 0))
	mat.set_shader_parameter("region_uv_max", Vector2(1, 1))
	if _shared_palette_tex:
		mat.set_shader_parameter("palette_tex", _shared_palette_tex)
		mat.set_shader_parameter("palette_size", _shared_palette_tex.get_width())
	return mat

func _build_palette_texture() -> Texture2D:
	var f := FileAccess.open(SWATCH_PATH, FileAccess.READ)
	if f == null:
		return null
	var swatches: Array = JSON.parse_string(f.get_as_text())
	if swatches.is_empty():
		return null
	var img := Image.create(swatches.size(), 1, false, Image.FORMAT_RGBA8)
	for i in range(swatches.size()):
		img.set_pixel(i, 0, Color(String(swatches[i])))
	return ImageTexture.create_from_image(img)
