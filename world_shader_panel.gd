extends CanvasLayer

# Toggled with key 5. Applies the painterly shader to every CanvasItem under
# main.world via a single shared ShaderMaterial; tweaking sliders updates the
# whole world live.

const SHADER_PATH := "res://shaders/world_pixelate.gdshader"

const PARAMS := [
	{"name": "pixel_size",       "min": 1.0,  "max": 32.0, "step": 0.1, "default": 5.0,  "type": "f"},
]

const EXEMPT_GROUP := "no_world_shader"

var main_ref: Node
var panel: PanelContainer
var enable_btn: Button
var status_label: Label

var _enabled: bool = false
var _shared_mat: ShaderMaterial = null
var _saved_materials: Dictionary = {}   # CanvasItem -> previous Material
var _refresh_timer: float = 0.0
var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}

func _ready() -> void:
	layer = 46
	visible = false

	panel = PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -320
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
	title.text = "World Shader  (key 5)"
	vb.add_child(title)

	enable_btn = Button.new()
	enable_btn.toggle_mode = true
	enable_btn.text = "Apply to world (off)"
	enable_btn.pressed.connect(_toggle_apply)
	vb.add_child(enable_btn)

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

	status_label = Label.new()
	status_label.text = ""
	vb.add_child(status_label)

	_shared_mat = _build_material()

func toggle() -> void:
	visible = not visible
	if visible and not _enabled:
		# Auto-apply on first open so the user sees the effect immediately.
		enable_btn.button_pressed = true
		_toggle_apply()

func _build_material() -> ShaderMaterial:
	var shader := load(SHADER_PATH) as Shader
	if shader == null:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = shader
	for p in PARAMS:
		var v: Variant = int(p.default) if p.type == "i" else p.default
		mat.set_shader_parameter(p.name, v)
	return mat

func _toggle_apply() -> void:
	_enabled = enable_btn.button_pressed
	enable_btn.text = "Apply to world (on)" if _enabled else "Apply to world (off)"
	if _enabled:
		_apply_to_world()
	else:
		_revert_world()

func _walk_world(node: Node, out: Array) -> void:
	if _is_exempt(node):
		return
	if node is CanvasItem:
		out.append(node)
	for c in node.get_children():
		_walk_world(c, out)

func _is_exempt(node: Node) -> bool:
	if node.is_in_group(EXEMPT_GROUP):
		return true
	if main_ref:
		if main_ref.player and node == main_ref.player:
			return true
		if main_ref.get("test_monsters"):
			for m in main_ref.test_monsters:
				if m == node:
					return true
		if main_ref.get("active_spiders"):
			for s in main_ref.active_spiders:
				if s == node:
					return true
	if node.get_script() and String(node.get_script().resource_path).ends_with("monster.gd"):
		return true
	return false

func _apply_to_world() -> void:
	if main_ref == null or _shared_mat == null:
		return
	_saved_materials.clear()
	var items: Array = []
	_walk_world(main_ref.world, items)
	var n: int = 0
	for ci in items:
		if not (ci is Sprite2D or ci is AnimatedSprite2D or ci is TextureRect):
			continue
		# Sprites with an existing shader (water, flora_wind, breathe) keep
		# their material but get the pixel_size pushed in so they pixelate too.
		if ci.material is ShaderMaterial:
			_push_pixel_size(ci.material as ShaderMaterial, _sliders["pixel_size"].value)
			continue
		_saved_materials[ci] = ci.material
		ci.material = _shared_mat
		n += 1
	status_label.text = "applied to %d sprites" % n

func _revert_world() -> void:
	for ci in _saved_materials.keys():
		if is_instance_valid(ci):
			ci.material = _saved_materials[ci]
	_saved_materials.clear()
	# Reset pixel_size on water/flora/breathe materials back to 1.0 (no snap).
	if main_ref:
		var items: Array = []
		_walk_world(main_ref.world, items)
		for ci in items:
			if ci.material is ShaderMaterial:
				(ci.material as ShaderMaterial).set_shader_parameter("pixel_size", 1.0)
				(ci.material as ShaderMaterial).set_shader_parameter("pixel_size_world", 1.0)
	status_label.text = "reverted"

func _process(delta: float) -> void:
	if not _enabled:
		return
	# Catch newly-streamed chunk sprites every ~0.5s.
	_refresh_timer -= delta
	if _refresh_timer > 0.0:
		return
	_refresh_timer = 2.5
	if main_ref == null:
		return
	var items: Array = []
	_walk_world(main_ref.world, items)
	for ci in items:
		if not (ci is Sprite2D or ci is AnimatedSprite2D or ci is TextureRect):
			continue
		if _saved_materials.has(ci):
			continue
		if ci.material is ShaderMaterial:
			_push_pixel_size(ci.material as ShaderMaterial, _sliders["pixel_size"].value)
			continue
		_saved_materials[ci] = ci.material
		ci.material = _shared_mat

func _push_pixel_size(mat: ShaderMaterial, value: float) -> void:
	mat.set_shader_parameter("pixel_size", value)
	# Water shader also has a separate body-pattern size that drives the
	# world-space chunkiness of the surface. Scale matches the texture-UV
	# pixelation so water looks consistent with everything else.
	mat.set_shader_parameter("pixel_size_world", value)

func _on_slider_changed(value: float, p: Dictionary) -> void:
	_value_labels[p.name].text = "%.2f" % value if p.type == "f" else str(int(value))
	if _shared_mat == null:
		return
	var v: Variant = int(value) if p.type == "i" else value
	_shared_mat.set_shader_parameter(p.name, v)
	# Propagate pixel_size to the existing-shader materials we're sharing with.
	if p.name == "pixel_size" and _enabled and main_ref:
		var items: Array = []
		_walk_world(main_ref.world, items)
		for ci in items:
			if ci.material is ShaderMaterial and not _saved_materials.has(ci):
				_push_pixel_size(ci.material as ShaderMaterial, value)
