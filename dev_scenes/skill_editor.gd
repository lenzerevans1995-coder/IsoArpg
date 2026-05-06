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
# Cache last-played anim so colour pick doesn't restart playback
# every refresh. play_anim resets _anim_time = 0 — with the shader
# tint repaint piling on, the rig appeared to freeze on frame 0.
var _last_played_anim: String = ""
var _last_played_dir: int = -1
var _last_loadout: Dictionary = {}

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
var _f_open: OptionButton
# Which weapon the preview rig currently holds. Editor-only — not saved.
var _preview_weapon: String = ""

# Color state.
var _palette: Array = []
# Per-effect color buttons — index 0 effect_a, 1 effect_b, 2 slash.
# Each button's StyleBox bg_color reflects the current color.
var _color_btns: Array = []

func _ready() -> void:
	_def = SkillDefScript.new()
	_load_palette()
	_build_ui()
	_refresh_preview()
	_load_fields_from_def()
	# Capture key presses for quick-fire (1-6 for attack anims, 0 for Idle).
	# Doesn't fight LineEdit text input — _input only reads keys when no
	# text field is focused.
	set_process_unhandled_key_input(true)

# Quick-fire keybinds for the preview — match the Unity creator's
# attack-cycle workflow. Updates the trigger anim dropdown so the
# saved SkillDef reflects whatever you last fired.
const _ANIM_KEYMAP := {
	KEY_1: "Attack1",   # primary attack (RMB equivalent)
	KEY_2: "Attack2",   # alt attack
	KEY_3: "Attack3",
	KEY_4: "Attack4",
	KEY_5: "Attack5",
	KEY_6: "Special1",  # cast pose / spell trigger
	KEY_0: "Idle",      # back to rest
}

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var anim: String = String(_ANIM_KEYMAP.get(event.keycode, ""))
	if anim == "":
		return
	_def.trigger_anim = anim
	_set_option_to_value(_f_anim, ANIM_OPTIONS, anim)
	_refresh_preview()

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

	# Open / new selector — drops down a list of every saved skill
	# (.tres files under res://data/skills/) plus a (New) entry that
	# resets the form to a blank SkillDef. Loads the picked skill into
	# the form so it can be edited in-place and re-saved.
	var open_row := HBoxContainer.new()
	left.add_child(open_row)
	var open_lbl := Label.new(); open_lbl.text = "Open"; open_row.add_child(open_lbl)
	_f_open = OptionButton.new()
	_f_open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_f_open.item_selected.connect(_on_open_selected)
	open_row.add_child(_f_open)
	var refresh_btn := Button.new()
	refresh_btn.text = "↻"
	refresh_btn.tooltip_text = "Re-scan data/skills/"
	refresh_btn.pressed.connect(_refresh_open_dropdown)
	open_row.add_child(refresh_btn)
	_refresh_open_dropdown()

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

	# Per-effect color pickers. Each row: a label + a swatch button. The
	# button's fill color is the currently-assigned color for that
	# effect; clicking opens a popup with the 81-swatch palette.
	_add_label(left, "\nColors", 14)
	var color_grid := GridContainer.new(); color_grid.columns = 2
	left.add_child(color_grid)
	_color_btns = [
		_add_color_row(color_grid, "Effect A",
			func(): return _def.effect_a_color,
			func(c): _def.effect_a_color = c),
		_add_color_row(color_grid, "Effect B",
			func(): return _def.effect_b_color,
			func(c): _def.effect_b_color = c),
		_add_color_row(color_grid, "Slash",
			func(): return _def.slash_color,
			func(c): _def.slash_color = c),
	]

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
	# Render every frame so the LayeredCharacter's anim playback shows
	# motion. Default UPDATE_WHEN_VISIBLE only repaints on dirty events
	# and the rig was freezing on its first frame.
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
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

# One label + one swatch button bound to a getter/setter pair on the
# SkillDef. Clicking the button pops up the 81-swatch palette; picking
# a swatch calls the setter, refreshes the preview, and recolors the
# button so you can see at a glance which effect has which color.
func _add_color_row(grid: GridContainer, label: String, getter: Callable, setter: Callable) -> Button:
	var l := Label.new(); l.text = label; grid.add_child(l)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(28, 22)
	btn.text = ""
	_paint_color_button(btn, getter.call())
	btn.pressed.connect(func(): _open_palette_popup(btn, getter, setter))
	grid.add_child(btn)
	return btn

func _paint_color_button(btn: Button, color: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0, 0, 0, 0.5)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)

func _open_palette_popup(anchor_btn: Button, getter: Callable, setter: Callable) -> void:
	var popup := PopupPanel.new()
	add_child(popup)
	var grid := GridContainer.new(); grid.columns = 9
	popup.add_child(grid)
	for hex in _palette:
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(20, 20)
		var col := Color(String(hex))
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sw.add_theme_stylebox_override("normal", sb)
		sw.add_theme_stylebox_override("hover", sb)
		sw.add_theme_stylebox_override("pressed", sb)
		sw.tooltip_text = String(hex)
		sw.pressed.connect(func():
			setter.call(col)
			_paint_color_button(anchor_btn, col)
			_refresh_preview()
			popup.queue_free())
		grid.add_child(sw)
	# Reset cell — clears to white.
	var reset := Button.new()
	reset.text = "✕"
	reset.tooltip_text = "Reset (white)"
	reset.pressed.connect(func():
		setter.call(Color.WHITE)
		_paint_color_button(anchor_btn, Color.WHITE)
		_refresh_preview()
		popup.queue_free())
	grid.add_child(reset)
	# Show next to the anchor button.
	var origin: Vector2 = anchor_btn.global_position + Vector2(0, anchor_btn.size.y + 4)
	popup.popup(Rect2i(int(origin.x), int(origin.y), 0, 0))

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
		_apply_effect_tint("vfx", _def.effect_a_color)
	if String(_def.effect_b_folder) != "":
		_preview_char.call("equip", "vfx2", String(_def.effect_b_folder))
		_apply_effect_tint("vfx2", _def.effect_b_color)
	if String(_def.slash_folder) != "":
		_preview_char.call("equip", "slash", String(_def.slash_folder))
		_apply_effect_tint("slash", _def.slash_color)
	# Set direction + (re)play the anim. Only restart playback if the
	# anim/dir/loadout actually changed — otherwise a color pick would
	# reset _anim_time = 0 every refresh and the rig snaps back to
	# frame 0 each swatch click.
	_preview_char.call("set_direction", _preview_dir)
	var loadout_sig: Dictionary = {
		"a": String(_def.effect_a_folder),
		"b": String(_def.effect_b_folder),
		"s": String(_def.slash_folder),
		"w": _preview_weapon,
	}
	var anim: String = String(_def.trigger_anim)
	if anim != _last_played_anim or _preview_dir != _last_played_dir or loadout_sig != _last_loadout:
		_preview_char.call("play_anim", anim, 12.0, true, Callable())
		_last_played_anim = anim
		_last_played_dir = _preview_dir
		_last_loadout = loadout_sig

# Replaces the layer's color with the picked tint via a luminance-tint
# shader, so the rendered color matches the swatch exactly. modulate
# would multiply with the source's existing color (e.g. Magic1 is
# yellow → red modulate gives orange). The shader collapses to
# luminance first, then recolors. White still shows the source's
# native colors (luminance × white = source brightness only).
const _EFFECT_TINT_SHADER := preload("res://shaders/effect_tint.gdshader")

func _apply_effect_tint(layer: String, tint: Color) -> void:
	var sprite: Sprite2D = _get_layer_sprite(layer)
	if sprite == null:
		return
	# White tint = no recolor (let the source show its native palette).
	if tint == Color.WHITE:
		sprite.material = null
		sprite.modulate = Color.WHITE
		return
	var mat := sprite.material as ShaderMaterial
	if mat == null or mat.shader != _EFFECT_TINT_SHADER:
		mat = ShaderMaterial.new()
		mat.shader = _EFFECT_TINT_SHADER
		sprite.material = mat
	mat.set_shader_parameter("tint", tint)

func _get_layer_sprite(layer: String) -> Sprite2D:
	# LayeredCharacter exposes layers as named child Sprite2Ds.
	if _preview_char == null:
		return null
	return _preview_char.get_node_or_null(layer) as Sprite2D

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
		# Refresh the Open dropdown so a freshly-saved skill appears
		# without the user clicking the ↻ button.
		_refresh_open_dropdown()
	else:
		_info_label.text = "Save FAILED (err=%d)" % err

# Walk data/skills/ and rebuild the Open dropdown. Index 0 is always
# (New) — selecting it resets the form to a blank SkillDef.
func _refresh_open_dropdown() -> void:
	if _f_open == null:
		return
	var current_id: String = String(_def.skill_id) if _def != null else ""
	_f_open.clear()
	_f_open.add_item("(New)", 0)
	var ids: Array[String] = []
	if DirAccess.dir_exists_absolute(SKILLS_DIR):
		var d := DirAccess.open(SKILLS_DIR)
		if d != null:
			d.list_dir_begin()
			var fn := d.get_next()
			while fn != "":
				if fn.ends_with(".tres"):
					ids.append(fn.left(fn.length() - 5))
				fn = d.get_next()
			d.list_dir_end()
	ids.sort()
	for id in ids:
		_f_open.add_item(id)
	# Re-select whatever was active before the refresh so the user
	# doesn't lose their position when they save.
	for i in range(_f_open.item_count):
		if _f_open.get_item_text(i) == current_id:
			_f_open.selected = i
			break

func _on_open_selected(idx: int) -> void:
	if idx <= 0:
		# (New) — fresh blank SkillDef.
		_def = SkillDefScript.new()
		_load_fields_from_def()
		_refresh_preview()
		return
	var id: String = _f_open.get_item_text(idx)
	var path: String = "%s/%s.tres" % [SKILLS_DIR, id]
	if not FileAccess.file_exists(path):
		_info_label.text = "Missing: %s" % path
		return
	var loaded: Resource = load(path)
	if loaded == null or not (loaded is SkillDefScript):
		_info_label.text = "Could not load %s" % path
		return
	# Use a duplicate so unsaved edits don't mutate the on-disk
	# resource until Save is pressed.
	_def = loaded.duplicate(true)
	_load_fields_from_def()
	_refresh_preview()
	_info_label.text = "Loaded %s" % id

func _load_fields_from_def() -> void:
	_f_id.text = String(_def.skill_id)
	_f_name.text = String(_def.display_name)
	_f_dmg.value = float(_def.damage_mult)
	_set_option_to_value(_f_anim, ANIM_OPTIONS, String(_def.trigger_anim))
	_set_option_to_value(_f_effect_a, EFFECT_OPTIONS, String(_def.effect_a_folder))
	_set_option_to_value(_f_effect_b, EFFECT_OPTIONS, String(_def.effect_b_folder))
	_set_option_to_value(_f_slash,    SLASH_OPTIONS,  String(_def.slash_folder))
	# Repaint color buttons so the swatches show current colors when a
	# saved SkillDef is loaded.
	if _color_btns.size() == 3:
		_paint_color_button(_color_btns[0], _def.effect_a_color)
		_paint_color_button(_color_btns[1], _def.effect_b_color)
		_paint_color_button(_color_btns[2], _def.slash_color)

func _set_option_to_value(ob: OptionButton, options: Array, value: String) -> void:
	var idx := options.find(value)
	if idx >= 0:
		ob.selected = idx
