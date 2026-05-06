extends Control

# Skill definition editor. Standalone scene — open dev_scenes/skill_editor.tscn
# and F6. Pick a trigger anim, two effect overlays, a slash trail, and
# per-layer colors from the 81-swatch palette. Live preview rig shows
# them combined. Save writes res://data/skills/<id>.tres.

const SkillDefScript := preload("res://skill_def.gd")
const LayeredCharacterScript := preload("res://layered_character.gd")
const LoadoutScript := preload("res://loadout.gd")

const SKILLS_DIR := "res://data/skills"
const PALETTE_PATH := "res://data/swatch_palette.json"

# Effect folder lists — only entries with non-empty PNGs.
const EFFECT_OPTIONS := ["", "Effect1", "Effect2", "Effect3", "Effect4", "Effect5",
		"Magic1", "Magic2", "Magic3"]
const SLASH_OPTIONS := ["", "Slash1", "Slash2"]
const ANIM_OPTIONS := ["Attack1", "Attack2", "Attack3", "Attack4", "Attack5",
		"AttackRun", "AttackRun2", "Special1", "Idle", "Walk", "Run"]
# Demo weapons for the preview — what the rig holds while you tweak the
# skill. Doesn't get saved into the SkillDef; purely visual context so
# you see how the effect reads against different held weapons. Labels
# map to mainhand sheet folder names.
const WEAPON_OPTIONS := [
	["(none)",       ""],
	["Sword",        "Melee2"],     # 'Longsword'
	["Greatsword",   "Melee5"],     # 'Broadsword' (heavy two-hander look)
	["Dagger",       "Melee1"],
	["Mace",         "Melee9"],
	["Bow",          "Ranged1"],
	["Long Bow",     "Ranged2"],
	["Staff",        "Melee19"],    # 'Wizard's Staff'
	["Wand",         "Melee22"],    # 'Wand of the Lich'
	["Magic Hands",  "Magic1"],     # spell-cast pose, no held object
]

# Live state.
var _def: Resource              # current SkillDef being edited
var _preview_vp: SubViewport
var _preview_char: Node2D
var _preview_dir: int = 2

# Field refs.
var _f_id: LineEdit
var _f_name: LineEdit
var _f_anim: OptionButton
var _f_effect_a: OptionButton
var _f_effect_b: OptionButton
var _f_slash: OptionButton
var _f_weapon: OptionButton
var _f_dmg: SpinBox
var _info_label: Label
# Which weapon the preview rig currently holds. Editor-only — not saved.
var _preview_weapon: String = ""

# Color state.
var _palette: Array = []
var _editing_color: String = "effect_color"  # which color the swatch click writes to

func _ready() -> void:
	_def = SkillDefScript.new()
	_load_palette()
	_build_ui()
	_refresh_preview()
	_load_fields_from_def()

func _load_palette() -> void:
	if FileAccess.file_exists(PALETTE_PATH):
		var f := FileAccess.open(PALETTE_PATH, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Array:
			_palette = parsed

func _build_ui() -> void:
	custom_minimum_size = Vector2(960, 600)
	var hbox := HBoxContainer.new()
	hbox.anchor_right = 1.0
	hbox.anchor_bottom = 1.0
	add_child(hbox)

	# --- left: form fields ---
	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(360, 0)
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(left_scroll)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(left)

	_add_label(left, "Skill Editor", 16)
	var grid := GridContainer.new(); grid.columns = 2
	left.add_child(grid)
	_f_id      = _add_str_row(grid, "Skill ID", _on_id_changed)
	_f_name    = _add_str_row(grid, "Display Name", func(v): _def.display_name = v)
	_f_anim    = _add_option_row(grid, "Trigger Anim", ANIM_OPTIONS, func(idx): _def.trigger_anim = ANIM_OPTIONS[idx]; _refresh_preview())
	_f_effect_a= _add_option_row(grid, "Effect A", EFFECT_OPTIONS, func(idx): _def.effect_a_folder = EFFECT_OPTIONS[idx]; _refresh_preview())
	_f_effect_b= _add_option_row(grid, "Effect B", EFFECT_OPTIONS, func(idx): _def.effect_b_folder = EFFECT_OPTIONS[idx]; _refresh_preview())
	_f_slash   = _add_option_row(grid, "Slash",    SLASH_OPTIONS,  func(idx): _def.slash_folder    = SLASH_OPTIONS[idx];  _refresh_preview())
	# Demo weapon: not saved, just gives the preview rig something to
	# hold so you can see how the effect reads against a sword, a bow,
	# magic hands, etc.
	var weapon_labels: Array = []
	for entry in WEAPON_OPTIONS: weapon_labels.append(String(entry[0]))
	_f_weapon  = _add_option_row(grid, "Demo Weapon", weapon_labels, func(idx):
		_preview_weapon = String(WEAPON_OPTIONS[idx][1])
		_refresh_preview())
	_f_dmg     = _add_spin_row(grid, "Damage Mult", 0.1, 10.0, 0.1, func(v): _def.damage_mult = float(v))

	# Color editor — radio for which color to set, plus 81-swatch grid.
	_add_label(left, "\nColors", 14)
	var color_target := HBoxContainer.new(); left.add_child(color_target)
	var radio_a := CheckBox.new(); radio_a.text = "Effect"; radio_a.button_pressed = true
	var radio_b := CheckBox.new(); radio_b.text = "Slash"
	radio_a.toggled.connect(func(v): if v: _editing_color = "effect_color"; radio_b.button_pressed = false)
	radio_b.toggled.connect(func(v): if v: _editing_color = "slash_color"; radio_a.button_pressed = false)
	color_target.add_child(radio_a); color_target.add_child(radio_b)
	left.add_child(_build_swatch_grid())

	# Sticky save bar at the bottom of the form.
	_info_label = Label.new()
	_info_label.text = "Set a Skill ID and Save."
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	left.add_child(_info_label)
	var save_btn := Button.new()
	save_btn.text = "Save Skill"
	save_btn.pressed.connect(_on_save)
	left.add_child(save_btn)

	# --- right: live preview ---
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(right)

	# Toolbar above preview.
	var ctrl_row := HBoxContainer.new()
	right.add_child(ctrl_row)
	var dir_btn := Button.new()
	dir_btn.text = "Rotate Dir"
	dir_btn.pressed.connect(func():
		_preview_dir = (_preview_dir + 1) % 8
		if _preview_char: _preview_char.call("set_direction", _preview_dir))
	ctrl_row.add_child(dir_btn)
	var play_btn := Button.new()
	play_btn.text = "Replay"
	play_btn.pressed.connect(_refresh_preview)
	ctrl_row.add_child(play_btn)

	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.custom_minimum_size = Vector2(420, 420)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	right.add_child(holder)
	_preview_vp = SubViewport.new()
	_preview_vp.size = Vector2i(420, 420)
	_preview_vp.transparent_bg = true
	_preview_vp.disable_3d = true
	_preview_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	holder.add_child(_preview_vp)
	_preview_char = LayeredCharacterScript.new()
	(_preview_char as Node2D).position = Vector2(210, 280)
	(_preview_char as Node2D).scale = Vector2(2, 2)
	_preview_vp.add_child(_preview_char)

# --- field-builder helpers ----------------------------------------

func _add_label(parent: Node, text: String, size: int = 12) -> void:
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)

func _add_str_row(grid: GridContainer, label: String, on_changed: Callable) -> LineEdit:
	var l := Label.new(); l.text = label; grid.add_child(l)
	var le := LineEdit.new()
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.text_changed.connect(on_changed)
	grid.add_child(le)
	return le

func _add_option_row(grid: GridContainer, label: String, options: Array, on_changed: Callable) -> OptionButton:
	var l := Label.new(); l.text = label; grid.add_child(l)
	var ob := OptionButton.new()
	for opt in options:
		ob.add_item(opt if opt != "" else "(none)")
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.item_selected.connect(on_changed)
	grid.add_child(ob)
	return ob

func _add_spin_row(grid: GridContainer, label: String, lo: float, hi: float, step: float, on_changed: Callable) -> SpinBox:
	var l := Label.new(); l.text = label; grid.add_child(l)
	var sb := SpinBox.new()
	sb.min_value = lo; sb.max_value = hi; sb.step = step; sb.value = 1.0
	sb.value_changed.connect(on_changed)
	grid.add_child(sb)
	return sb

func _build_swatch_grid() -> Control:
	var grid := GridContainer.new(); grid.columns = 27
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for hex in _palette:
		var b := Button.new()
		b.custom_minimum_size = Vector2(12, 12)
		b.flat = false
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(String(hex))
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		var col := Color(String(hex))
		b.tooltip_text = String(hex)
		b.pressed.connect(func(): _apply_color(col))
		grid.add_child(b)
	# White-reset cell.
	var reset := Button.new()
	reset.text = "✕"
	reset.tooltip_text = "Reset to white"
	reset.pressed.connect(func(): _apply_color(Color.WHITE))
	grid.add_child(reset)
	return grid

func _apply_color(c: Color) -> void:
	if _def == null: return
	if _editing_color == "slash_color":
		_def.slash_color = c
	else:
		_def.effect_color = c
	_refresh_preview()

# --- preview ------------------------------------------------------

func _refresh_preview() -> void:
	if _preview_char == null: return
	# Clear and re-equip layers each refresh — no leftover state from
	# the previous skill.
	for layer in ["body","head","hands","chest","legs","shoes","belt",
			"bag","mainhand","offhand","mount","slash","vfx","vfx2"]:
		_preview_char.call("clear_layer", layer)
		_preview_char.call("set_tint", layer, Color.WHITE)
	# Show a body so effects read on a character, not in space.
	_preview_char.call("equip", "body", "NakedBody")
	# Demo weapon — drives the held silhouette while you tune. Not part
	# of the saved SkillDef; the actual equipped weapon at runtime
	# comes from the player's loadout.
	if _preview_weapon != "":
		_preview_char.call("equip", "mainhand", _preview_weapon)
	if _def == null: return
	if String(_def.effect_a_folder) != "":
		_preview_char.call("equip", "vfx", String(_def.effect_a_folder))
		_preview_char.call("set_tint", "vfx", _def.effect_color)
	if String(_def.effect_b_folder) != "":
		_preview_char.call("equip", "vfx2", String(_def.effect_b_folder))
		_preview_char.call("set_tint", "vfx2", _def.effect_color)
	if String(_def.slash_folder) != "":
		_preview_char.call("equip", "slash", String(_def.slash_folder))
		_preview_char.call("set_tint", "slash", _def.slash_color)
	_preview_char.call("set_direction", _preview_dir)
	_preview_char.call("play_anim", String(_def.trigger_anim), 12.0, true, Callable())

# --- save / load --------------------------------------------------

func _on_id_changed(v: String) -> void:
	_def.skill_id = v.strip_edges().to_snake_case()
	# Auto-fill display_name on first id-set if name still blank.
	if String(_def.display_name) == "":
		_def.display_name = v.capitalize()
		_f_name.text = _def.display_name

func _on_save() -> void:
	if String(_def.skill_id) == "":
		_info_label.text = "Set a Skill ID first."
		return
	if not DirAccess.dir_exists_absolute(SKILLS_DIR):
		DirAccess.make_dir_recursive_absolute(SKILLS_DIR)
	var path := "%s/%s.tres" % [SKILLS_DIR, String(_def.skill_id)]
	var err := ResourceSaver.save(_def, path)
	if err == OK:
		_info_label.text = "Saved -> %s" % path
	else:
		_info_label.text = "Save FAILED (err=%d)" % err

func _load_fields_from_def() -> void:
	_f_id.text = String(_def.skill_id)
	_f_name.text = String(_def.display_name)
	_f_dmg.value = float(_def.damage_mult)
	_set_option_to_value(_f_anim, ANIM_OPTIONS, String(_def.trigger_anim))
	_set_option_to_value(_f_effect_a, EFFECT_OPTIONS, String(_def.effect_a_folder))
	_set_option_to_value(_f_effect_b, EFFECT_OPTIONS, String(_def.effect_b_folder))
	_set_option_to_value(_f_slash,    SLASH_OPTIONS,  String(_def.slash_folder))

func _set_option_to_value(ob: OptionButton, options: Array, value: String) -> void:
	var idx := options.find(value)
	if idx >= 0:
		ob.selected = idx
