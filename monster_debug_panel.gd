extends PanelContainer

# Live tuner for monster_painterly.gdshader. Toggled with key 2 from main.gd.
# Targets every Monster registered via add_target(); sliders push uniforms
# directly to each monster's ShaderMaterial as you drag.

const PARAMS := [
	{"name": "pixel_size",       "min": 1.0,  "max": 24.0, "step": 0.1, "default": 6.0,  "type": "f"},
	{"name": "palette_levels",   "min": 2.0,  "max": 32.0, "step": 1.0, "default": 9.0,  "type": "i"},
	{"name": "saturation",       "min": 0.0,  "max": 2.0,  "step": 0.01,"default": 1.0,  "type": "f"},
	{"name": "contrast",         "min": 0.5,  "max": 2.0,  "step": 0.01,"default": 1.1,  "type": "f"},
	{"name": "brightness",       "min": -0.5, "max": 0.5,  "step": 0.01,"default": 0.0,  "type": "f"},
	{"name": "outline_strength", "min": 0.0,  "max": 1.0,  "step": 0.01,"default": 0.0,  "type": "f"},
	{"name": "alpha_cutoff",     "min": 0.0,  "max": 1.0,  "step": 0.01,"default": 0.35, "type": "f"},
	{"name": "glow_strength",    "min": 0.0,  "max": 4.0,  "step": 0.05,"default": 0.0,  "type": "f"},
	{"name": "glow_radius",      "min": 0.0,  "max": 16.0, "step": 0.1, "default": 4.0,  "type": "f"},
	{"name": "palette_mix",      "min": 0.0,  "max": 1.0,  "step": 0.01,"default": 1.0,  "type": "f"},
	{"name": "display_size",     "min": 24.0, "max": 384.0,"step": 1.0, "default": 96.0, "type": "size"},
]

const GLOW_PRESETS := [
	["off",     Color(1, 1, 1)],
	["fire",    Color(1.0, 0.55, 0.15)],
	["ember",   Color(1.0, 0.30, 0.10)],
	["holy",    Color(1.0, 0.92, 0.55)],
	["frost",   Color(0.55, 0.85, 1.0)],
	["arcane",  Color(0.65, 0.40, 1.0)],
	["nature",  Color(0.45, 1.00, 0.55)],
	["void",    Color(0.55, 0.20, 0.85)],
	["blood",   Color(0.85, 0.10, 0.10)],
]

var targets: Array = []
var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}
var _glow_index: int = 0
var _glow_label: Label

const ANIM_NAMES := ["Idle", "Walking", "Running", "IdleFidget", "Attack1", "Attack2",
	"UseSkill", "Block", "Evade", "GetHit", "CriticalHP", "DeadToDown", "Behavior"]
const DIRS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
var _anim_index: int = 0
var _anim_label: Label
var _dir_index: int = 2
var _dir_label: Label

const MONSTER_DIR := "res://assets/shader_sprites"
const CONFIG_PATH := "user://monster_configs.json"
var _monster_names: Array[String] = []
var _monster_index: int = 0
var _monster_label: Label

func _ready() -> void:
	custom_minimum_size = Vector2(280, 0)
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -300
	offset_right = -16
	offset_top = 16
	offset_bottom = 16
	mouse_filter = Control.MOUSE_FILTER_STOP

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)

	var title := Label.new()
	title.text = "Monster Shader  (key 2)"
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	vb.add_child(title)

	for p in PARAMS:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		vb.add_child(row)

		var hb := HBoxContainer.new()
		row.add_child(hb)
		var name_lbl := Label.new()
		name_lbl.text = p.name
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(name_lbl)
		var val_lbl := Label.new()
		val_lbl.text = str(p.default)
		hb.add_child(val_lbl)
		_value_labels[p.name] = val_lbl

		var s := HSlider.new()
		s.min_value = p.min
		s.max_value = p.max
		s.step = p.step
		s.value = p.default
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.value_changed.connect(_on_slider_changed.bind(p))
		row.add_child(s)
		_sliders[p.name] = s

	_monster_names = _scan_monster_dir()
	var mon_row := HBoxContainer.new()
	vb.add_child(mon_row)
	var mon_lbl := Label.new()
	mon_lbl.text = "monster"
	mon_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mon_row.add_child(mon_lbl)
	var mp := Button.new()
	mp.text = "<"
	mp.pressed.connect(func(): _cycle_monster(-1))
	mon_row.add_child(mp)
	_monster_label = Label.new()
	_monster_label.text = _monster_names[0] if _monster_names.size() > 0 else "(none)"
	_monster_label.custom_minimum_size = Vector2(120, 0)
	_monster_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mon_row.add_child(_monster_label)
	var mn := Button.new()
	mn.text = ">"
	mn.pressed.connect(func(): _cycle_monster(1))
	mon_row.add_child(mn)

	_anim_label = _add_cycler(vb, "anim", ANIM_NAMES[_anim_index],
		func(): _cycle_anim(-1), func(): _cycle_anim(1), 100)
	_dir_label = _add_cycler(vb, "facing", DIRS[_dir_index],
		func(): _cycle_dir(-1), func(): _cycle_dir(1), 48)

	var save_row := HBoxContainer.new()
	vb.add_child(save_row)
	var save_btn := Button.new()
	save_btn.text = "Save config"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(_save_current_config)
	save_row.add_child(save_btn)
	var import_btn := Button.new()
	import_btn.text = "Import sheet"
	import_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import_btn.pressed.connect(_open_import_dialog)
	save_row.add_child(import_btn)

	var glow_row := HBoxContainer.new()
	vb.add_child(glow_row)
	var glow_lbl := Label.new()
	glow_lbl.text = "glow"
	glow_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	glow_row.add_child(glow_lbl)
	var gp := Button.new()
	gp.text = "<"
	gp.pressed.connect(func(): _cycle_glow(-1))
	glow_row.add_child(gp)
	_glow_label = Label.new()
	_glow_label.text = String(GLOW_PRESETS[0][0])
	_glow_label.custom_minimum_size = Vector2(72, 0)
	_glow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glow_row.add_child(_glow_label)
	var gn := Button.new()
	gn.text = ">"
	gn.pressed.connect(func(): _cycle_glow(1))
	glow_row.add_child(gn)

func _cycle_glow(step: int) -> void:
	_glow_index = (_glow_index + step + GLOW_PRESETS.size()) % GLOW_PRESETS.size()
	var entry: Array = GLOW_PRESETS[_glow_index]
	_glow_label.text = String(entry[0])
	var c: Color = entry[1]
	for t in targets:
		if not is_instance_valid(t):
			continue
		var spr: Sprite2D = null
		for ch in t.get_children():
			if ch is Sprite2D:
				spr = ch
				break
		if spr and spr.material is ShaderMaterial:
			(spr.material as ShaderMaterial).set_shader_parameter("glow_color", Vector3(c.r, c.g, c.b))

func _add_cycler(parent: Container, label: String, value: String, on_prev: Callable, on_next: Callable, value_w: int) -> Label:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var pb := Button.new()
	pb.text = "<"
	pb.pressed.connect(on_prev)
	row.add_child(pb)
	var vlbl := Label.new()
	vlbl.text = value
	vlbl.custom_minimum_size = Vector2(value_w, 0)
	vlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(vlbl)
	var nb := Button.new()
	nb.text = ">"
	nb.pressed.connect(on_next)
	row.add_child(nb)
	return vlbl

func _cycle_anim(step: int) -> void:
	_anim_index = (_anim_index + step + ANIM_NAMES.size()) % ANIM_NAMES.size()
	var name: String = ANIM_NAMES[_anim_index]
	_anim_label.text = name
	for t in targets:
		if is_instance_valid(t) and t.has_method("play_anim"):
			t.play_anim(name, true)

func _cycle_dir(step: int) -> void:
	_dir_index = (_dir_index + step + DIRS.size()) % DIRS.size()
	_dir_label.text = DIRS[_dir_index]
	for t in targets:
		if is_instance_valid(t) and t.has_method("set_direction"):
			t.set_direction(_dir_index)

func _scan_monster_dir() -> Array[String]:
	var names: Array[String] = []
	var d := DirAccess.open(MONSTER_DIR)
	if d == null:
		return names
	d.list_dir_begin()
	while true:
		var entry := d.get_next()
		if entry == "":
			break
		if d.current_is_dir() and not entry.begins_with("."):
			if FileAccess.file_exists("%s/%s/Spritesheet.png" % [MONSTER_DIR, entry]):
				names.append(entry)
	d.list_dir_end()
	names.sort()
	return names

func _cycle_monster(step: int) -> void:
	if _monster_names.is_empty():
		return
	_monster_index = (_monster_index + step + _monster_names.size()) % _monster_names.size()
	var name: String = _monster_names[_monster_index]
	_monster_label.text = name
	var tex: Texture2D = load("%s/%s/Spritesheet.png" % [MONSTER_DIR, name])
	for t in targets:
		if is_instance_valid(t) and t.has_method("set_spritesheet"):
			t.set_spritesheet(tex)
			t.play_anim("Idle", true)
	_apply_saved_config(name)

func _current_monster_name() -> String:
	if _monster_names.is_empty():
		return ""
	return _monster_names[_monster_index]

func _load_all_configs() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		return {}
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

func _save_current_config() -> void:
	var name := _current_monster_name()
	if name == "":
		return
	var configs := _load_all_configs()
	var entry: Dictionary = {}
	for p in PARAMS:
		entry[p.name] = _sliders[p.name].value
	entry["glow_index"] = _glow_index
	configs[name] = entry
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(configs, "  "))
	print("monster_debug_panel: saved config for ", name)

func _open_import_dialog() -> void:
	var dlg := FileDialog.new()
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	dlg.filters = PackedStringArray(["*.png ; PNG sheets"])
	dlg.size = Vector2i(800, 600)
	dlg.use_native_dialog = true
	dlg.files_selected.connect(_import_files)
	get_tree().root.add_child(dlg)
	dlg.popup_centered()

func _import_files(paths: PackedStringArray) -> void:
	var imported := 0
	for src in paths:
		var name: String = src.get_file().get_basename()
		# If the file is named "Spritesheet.png" use the parent folder name.
		if name.to_lower() in ["spritesheet", "sprite_1"]:
			name = src.get_base_dir().get_file()
		var img := Image.new()
		var err := img.load(src)
		if err != OK:
			push_warning("import: could not load %s (err %d)" % [src, err])
			continue
		var dst_dir := "%s/%s" % [MONSTER_DIR, name]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dst_dir))
		var dst := "%s/Spritesheet.png" % dst_dir
		# Image.save_png writes a clean PNG with no GIMP/EXIF chunks.
		err = img.save_png(ProjectSettings.globalize_path(dst))
		if err == OK:
			imported += 1
		else:
			push_warning("import: save failed %s (err %d)" % [dst, err])
	if imported > 0:
		_monster_names = _scan_monster_dir()
		print("imported %d sheet(s); picker refreshed (%d monsters)" % [imported, _monster_names.size()])

func _apply_saved_config(name: String) -> void:
	var configs := _load_all_configs()
	if not configs.has(name):
		return
	var entry: Dictionary = configs[name]
	for p in PARAMS:
		if entry.has(p.name):
			_sliders[p.name].value = float(entry[p.name])
	if entry.has("glow_index"):
		_glow_index = int(entry["glow_index"]) - 1
		_cycle_glow(1)

func add_target(monster: Node) -> void:
	if monster and not targets.has(monster):
		targets.append(monster)
		_apply_all()

func _apply_all() -> void:
	for p in PARAMS:
		_push(p, _sliders[p.name].value)

func _on_slider_changed(value: float, p: Dictionary) -> void:
	_value_labels[p.name].text = "%.2f" % value if p.type == "f" else str(int(value))
	_push(p, value)

func _push(p: Dictionary, value: float) -> void:
	for t in targets:
		if not is_instance_valid(t):
			continue
		if p.type == "size":
			if t.has_method("set_display_size"):
				t.set_display_size(value)
			continue
		var spr: Sprite2D = t.get_node_or_null("Sprite2D")
		if spr == null:
			for ch in t.get_children():
				if ch is Sprite2D:
					spr = ch
					break
		if spr and spr.material is ShaderMaterial:
			var v: Variant = int(value) if p.type == "i" else value
			(spr.material as ShaderMaterial).set_shader_parameter(p.name, v)
