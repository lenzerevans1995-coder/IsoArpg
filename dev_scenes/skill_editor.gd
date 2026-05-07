extends Control

# Skill definition editor. Standalone scene — open dev_scenes/skill_editor.tscn
# and F6. Pick a trigger anim, two effect overlays, a slash trail, and
# per-layer colors from the 81-swatch palette. Live preview rig shows
# them combined. Save writes res://data/skills/<id>.tres.

const SkillDefScript := preload("res://skill_def.gd")
const LayeredCharacterScript := preload("res://layered_character.gd")
const LoadoutScript := preload("res://loadout.gd")
const ExplosionAnimScript := preload("res://explosion_anim.gd")
const ProjectileRuntimeScript := preload("res://projectile_runtime.gd")
const PROJECTILES_PATH := "res://data/projectiles.json"
const MOTION_OPTIONS := ["at_player", "at_target", "travel", "arc_rain"]

# --- Foundry theme tokens -----------------------------------------------
const COL_BG         := Color("#0E1116")
const COL_PANEL      := Color("#161A21")
const COL_RAISED     := Color("#1F252E")
const COL_RAISED_HOV := Color("#262E3A")
const COL_RULE       := Color("#2A3340")
const COL_TEXT       := Color("#E8E2D2")
const COL_TEXT_DIM   := Color("#8B8676")
const COL_TEXT_FAINT := Color("#5A5448")
const COL_AMBER      := Color("#D9A85A")
const COL_AMBER_DIM  := Color("#7C5F33")

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
# Auto-fire the projectile whenever the body anim loops back to frame 0,
# so the preview stays in sync without the user pressing Play Skill on
# every cycle. Tracks the previous frame index so we can detect the
# wraparound (current_frame < last_frame).
var _proj_last_frame: int = -1
# Single drag owner so the dummy enemy and the offset markers can't all
# capture the same click — overlapping hit-zones used to make moving
# the enemy also slide the markers (and vice-versa).
var _drag_owner: Node = null

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
var _f_world_fx: OptionButton
# Discovered list of Fantasy tileset effect subfolders, populated at
# _ready by scanning SkillDefScript.FANTASY_FX_ROOT. Index 0 is "" (none).
var _world_fx_options: Array = [""]
# Which weapon the preview rig currently holds. Editor-only — not saved.
var _preview_weapon: String = ""

# Color state.
var _palette: Array = []
# Per-effect color buttons — index 0 effect_a, 1 effect_b, 2 slash.
# Each button's StyleBox bg_color reflects the current color.
var _color_btns: Array = []

# Projectile state + UI refs.
var _projectile_registry: Dictionary = {}
var _f_proj_pack: OptionButton
var _f_proj_cat: OptionButton
var _f_proj_name: OptionButton
var _f_proj_motion: OptionButton
var _f_proj_start: SpinBox
var _f_proj_end: SpinBox
var _f_proj_fps: SpinBox
var _f_proj_speed: SpinBox
var _f_proj_arc_count: SpinBox
var _f_proj_arc_radius: SpinBox
var _f_proj_scale: SpinBox
var _f_proj_color_btn: Button
var _proj_info: Label
var _origin_marker: Node2D    # blue: where projectile spawns (player + origin_offset)
var _target_marker: Node2D    # red:  where projectile lands  (test_target + target_offset)
# Preview SubViewport renders at 1/PREVIEW_SHRINK of the on-screen
# holder size, then NEAREST-upscales — same pattern as the main game's
# 640x360→1280x720 rig. Bumping PREVIEW_SHRINK zooms in (each game
# pixel becomes a bigger screen block).
# Initial preview zoom — mouse wheel over the viewport adjusts at runtime.
var _preview_shrink: int = 4
const _PREVIEW_SHRINK_MIN := 1
const _PREVIEW_SHRINK_MAX := 12
var _preview_holder: SubViewportContainer    # cached so wheel handler can resize it
const _PREVIEW_PLAYER_POS := Vector2(38, 84)
# Live position of the dummy enemy — mutable so dragging it carries the
# red target marker along (and so target_offset stays relative to the
# enemy, not to a fixed point on the canvas).
var _target_ref: Vector2 = Vector2(80, 60)
var _dummy_enemy: Node2D

func _ready() -> void:
	_def = SkillDefScript.new()
	_load_palette()
	_load_world_fx_options()
	_load_projectile_registry()
	_build_ui()
	_refresh_preview()
	_load_fields_from_def()

func _load_projectile_registry() -> void:
	if not FileAccess.file_exists(PROJECTILES_PATH):
		_projectile_registry = {}
		return
	var f := FileAccess.open(PROJECTILES_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_projectile_registry = parsed
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

# Walk the Fantasy tileset Effects/ root and populate _world_fx_options
# with each subfolder. Re-runnable but typically called once on _ready.
func _load_world_fx_options() -> void:
	_world_fx_options = [""]
	var d := DirAccess.open(SkillDefScript.FANTASY_FX_ROOT)
	if d == null:
		return
	d.list_dir_begin()
	var fn := d.get_next()
	var found: Array = []
	while fn != "":
		if d.current_is_dir() and not fn.begins_with("."):
			found.append(fn)
		fn = d.get_next()
	d.list_dir_end()
	found.sort()
	for name in found:
		_world_fx_options.append(name)

func _load_palette() -> void:
	if FileAccess.file_exists(PALETTE_PATH):
		var f := FileAccess.open(PALETTE_PATH, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Array:
			_palette = parsed

func _build_ui() -> void:
	# --- "Foundry" layout: header + tabs + preview, no scrolling --------
	custom_minimum_size = Vector2(960, 600)
	# Backplate fills the editor window with the deepest panel color.
	var back := ColorRect.new()
	back.color = COL_BG
	back.anchor_right = 1.0; back.anchor_bottom = 1.0
	add_child(back)

	# Outer margin around the whole page.
	var pad := MarginContainer.new()
	pad.anchor_right = 1.0; pad.anchor_bottom = 1.0
	pad.add_theme_constant_override("margin_left",   24)
	pad.add_theme_constant_override("margin_right",  24)
	pad.add_theme_constant_override("margin_top",    18)
	pad.add_theme_constant_override("margin_bottom", 24)
	add_child(pad)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 18)
	pad.add_child(page)

	# Header bar.
	page.add_child(_build_header_bar())

	# Tabs (form fields) on the left + always-visible Preview on the right.
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 20)
	page.add_child(split)

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.size_flags_stretch_ratio = 1.0
	_style_tabs(tabs)
	# Each tab is a single column; cards stack inside.
	var t_body := _build_col_identity();    t_body.name = "Body"
	var t_fx   := _build_col_overlays();    t_fx.name   = "Effects"
	var t_proj := _build_col_projectile();  t_proj.name = "Projectile"
	tabs.add_child(t_body)
	tabs.add_child(t_fx)
	tabs.add_child(t_proj)
	split.add_child(tabs)

	var preview_col := _build_col_preview()
	preview_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_col.size_flags_stretch_ratio = 1.4
	split.add_child(preview_col)

	_refresh_open_dropdown()

func _style_tabs(tc: TabContainer) -> void:
	# Tabs styled to match the section cards — same charcoal palette,
	# amber underline on the selected tab.
	var bg := StyleBoxFlat.new()
	bg.bg_color = COL_PANEL
	bg.border_color = COL_RULE
	bg.border_width_left = 1; bg.border_width_top = 1
	bg.border_width_right = 1; bg.border_width_bottom = 1
	bg.corner_radius_top_left = 2; bg.corner_radius_top_right = 2
	bg.corner_radius_bottom_left = 2; bg.corner_radius_bottom_right = 2
	bg.content_margin_left = 18; bg.content_margin_right = 18
	bg.content_margin_top = 18; bg.content_margin_bottom = 18
	tc.add_theme_stylebox_override("panel", bg)

	var tab_unsel := StyleBoxFlat.new()
	tab_unsel.bg_color = COL_RAISED
	tab_unsel.border_color = COL_RULE
	tab_unsel.border_width_bottom = 1
	tab_unsel.content_margin_left = 18; tab_unsel.content_margin_right = 18
	tab_unsel.content_margin_top = 8; tab_unsel.content_margin_bottom = 8
	tc.add_theme_stylebox_override("tab_unselected", tab_unsel)

	var tab_hov := tab_unsel.duplicate() as StyleBoxFlat
	tab_hov.bg_color = COL_RAISED_HOV
	tc.add_theme_stylebox_override("tab_hovered", tab_hov)

	var tab_sel := StyleBoxFlat.new()
	tab_sel.bg_color = COL_PANEL
	tab_sel.border_color = COL_AMBER
	tab_sel.border_width_bottom = 2
	tab_sel.content_margin_left = 18; tab_sel.content_margin_right = 18
	tab_sel.content_margin_top = 8; tab_sel.content_margin_bottom = 8
	tc.add_theme_stylebox_override("tab_selected", tab_sel)

	tc.add_theme_color_override("font_unselected_color", COL_TEXT_DIM)
	tc.add_theme_color_override("font_hovered_color", COL_TEXT)
	tc.add_theme_color_override("font_selected_color", COL_AMBER)
	tc.add_theme_font_size_override("font_size", 12)

# --- Foundry style helpers ---------------------------------------------

func _section_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = COL_RULE
	sb.border_width_left = 1; sb.border_width_top = 1
	sb.border_width_right = 1; sb.border_width_bottom = 1
	sb.corner_radius_top_left = 2; sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2; sb.corner_radius_bottom_right = 2
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	sb.content_margin_left = 14; sb.content_margin_right = 14
	sb.content_margin_top = 12; sb.content_margin_bottom = 12
	return sb

func _input_style(focus: bool = false, hover: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_RAISED_HOV if hover else COL_RAISED
	sb.border_color = COL_AMBER if focus else COL_RULE
	sb.border_width_bottom = 2 if focus else 1
	sb.corner_radius_top_left = 2; sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2; sb.corner_radius_bottom_right = 2
	sb.content_margin_left = 10; sb.content_margin_right = 10
	sb.content_margin_top = 6; sb.content_margin_bottom = 6
	return sb

func _btn_secondary_style(hover: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_RAISED_HOV if hover else COL_RAISED
	sb.border_color = COL_AMBER_DIM if hover else COL_RULE
	sb.border_width_left = 1; sb.border_width_top = 1
	sb.border_width_right = 1; sb.border_width_bottom = 1
	sb.corner_radius_top_left = 2; sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2; sb.corner_radius_bottom_right = 2
	sb.content_margin_left = 12; sb.content_margin_right = 12
	sb.content_margin_top = 6; sb.content_margin_bottom = 6
	return sb

func _btn_primary_style(hover: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_AMBER if not hover else Color(1.05 * COL_AMBER.r, 1.05 * COL_AMBER.g, 1.05 * COL_AMBER.b, 1.0)
	sb.corner_radius_top_left = 2; sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2; sb.corner_radius_bottom_right = 2
	sb.content_margin_left = 16; sb.content_margin_right = 16
	sb.content_margin_top = 8; sb.content_margin_bottom = 8
	return sb

# Apply the input-box style to any LineEdit/SpinBox/OptionButton in one call.
func _style_input(c: Control) -> void:
	c.add_theme_stylebox_override("normal", _input_style())
	c.add_theme_stylebox_override("focus", _input_style(true))
	c.add_theme_stylebox_override("hover", _input_style(false, true))
	c.add_theme_color_override("font_color", COL_TEXT)
	c.add_theme_font_size_override("font_size", 13)

func _style_secondary_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _btn_secondary_style())
	b.add_theme_stylebox_override("hover", _btn_secondary_style(true))
	b.add_theme_stylebox_override("pressed", _btn_secondary_style(true))
	b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_color_override("font_hover_color", COL_AMBER)
	b.add_theme_font_size_override("font_size", 12)

func _style_primary_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _btn_primary_style())
	b.add_theme_stylebox_override("hover", _btn_primary_style(true))
	b.add_theme_stylebox_override("pressed", _btn_primary_style())
	b.add_theme_color_override("font_color", Color("#1A1410"))
	b.add_theme_color_override("font_hover_color", Color("#1A1410"))
	b.add_theme_font_size_override("font_size", 12)

# A label-with-tracking style (uppercase, dim).
func _label_dim(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_color_override("font_color", COL_TEXT_DIM)
	l.add_theme_font_size_override("font_size", 11)
	return l

# Section card factory — wraps content in a styled PanelContainer with a
# numbered header (amber prefix + white title + amber rule to right).
func _section_card(num: String, title: String, body: Control) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _section_panel_style())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	card.add_child(v)

	# Header row.
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var n := Label.new(); n.text = "%s  —" % num
	n.add_theme_color_override("font_color", COL_AMBER)
	n.add_theme_font_size_override("font_size", 11)
	hb.add_child(n)
	var t := Label.new(); t.text = title.to_upper()
	t.add_theme_color_override("font_color", COL_TEXT)
	t.add_theme_font_size_override("font_size", 14)
	hb.add_child(t)
	# Filling amber rule.
	var rule_wrap := CenterContainer.new()
	rule_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rule := Panel.new()
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = COL_AMBER; rsb.bg_color.a = 0.55
	rule.add_theme_stylebox_override("panel", rsb)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule_wrap.add_child(rule)
	hb.add_child(rule_wrap)
	v.add_child(hb)

	# Body content.
	v.add_child(body)
	return card

# Header bar at the top of the editor.
func _build_header_bar() -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = COL_RULE
	sb.border_width_bottom = 1
	sb.content_margin_left = 18; sb.content_margin_right = 18
	sb.content_margin_top = 12; sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(0, 56)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	panel.add_child(hb)

	# Brand mark + title.
	var mark := Label.new()
	mark.text = "✦"
	mark.add_theme_color_override("font_color", COL_AMBER)
	mark.add_theme_font_size_override("font_size", 20)
	hb.add_child(mark)
	var title := Label.new()
	title.text = "FORGE"
	title.add_theme_color_override("font_color", COL_TEXT)
	title.add_theme_font_size_override("font_size", 18)
	hb.add_child(title)

	# Open selector.
	var open_lbl := _label_dim("Open")
	hb.add_child(open_lbl)
	_f_open = OptionButton.new()
	_f_open.custom_minimum_size = Vector2(180, 0)
	_f_open.item_selected.connect(_on_open_selected)
	_style_input(_f_open)
	hb.add_child(_f_open)
	var refresh_btn := Button.new()
	refresh_btn.text = "↻"
	refresh_btn.tooltip_text = "Re-scan data/skills/"
	refresh_btn.pressed.connect(_refresh_open_dropdown)
	_style_secondary_button(refresh_btn)
	hb.add_child(refresh_btn)

	# Identity inline (id + name) so it's always visible.
	var id_lbl := _label_dim("ID")
	hb.add_child(id_lbl)
	_f_id = LineEdit.new()
	_f_id.placeholder_text = "skill_id"
	_f_id.custom_minimum_size = Vector2(140, 0)
	_f_id.text_changed.connect(_on_id_changed)
	_style_input(_f_id)
	hb.add_child(_f_id)

	var name_lbl := _label_dim("Name")
	hb.add_child(name_lbl)
	_f_name = LineEdit.new()
	_f_name.placeholder_text = "Display name"
	_f_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_f_name.text_changed.connect(func(v): _def.display_name = v)
	_style_input(_f_name)
	hb.add_child(_f_name)

	# Spacer
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(8, 0)
	hb.add_child(sep)

	# Status text (e.g. 'Saved -> ...').
	_info_label = Label.new()
	_info_label.text = "Foundry"
	_info_label.add_theme_color_override("font_color", COL_TEXT_FAINT)
	_info_label.add_theme_font_size_override("font_size", 11)
	_info_label.custom_minimum_size = Vector2(220, 0)
	hb.add_child(_info_label)

	# Save CTA.
	var save_btn := Button.new()
	save_btn.text = "  SAVE  "
	save_btn.pressed.connect(_on_save)
	_style_primary_button(save_btn)
	hb.add_child(save_btn)
	return panel

# Helper: standard form row (label left, control right, optional swatch).
func _form_row(label: String, control: Control, swatch: Button = null) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var l := _label_dim(label)
	l.custom_minimum_size = Vector2(82, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(control)
	if swatch != null:
		swatch.custom_minimum_size = Vector2(22, 22)
		hb.add_child(swatch)
	return hb

# Build a swatch button bound to a getter / setter on the SkillDef.
func _swatch(getter: Callable, setter: Callable) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.custom_minimum_size = Vector2(22, 22)
	_paint_color_button(btn, getter.call())
	btn.pressed.connect(func(): _open_palette_popup(btn, getter, setter))
	return btn

# --- Columns -----------------------------------------------------------

func _build_col_identity() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)

	# BODY card (trigger anim + demo weapon + rotate-dir).
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	_f_anim = OptionButton.new()
	for opt in ANIM_OPTIONS: _f_anim.add_item(opt)
	_f_anim.item_selected.connect(func(idx):
		_def.trigger_anim = ANIM_OPTIONS[idx]; _refresh_preview())
	_style_input(_f_anim)
	body.add_child(_form_row("Trigger anim", _f_anim))
	var weapon_labels: Array = []
	for entry in WEAPON_OPTIONS: weapon_labels.append(String(entry[0]))
	_f_weapon = OptionButton.new()
	for opt in weapon_labels: _f_weapon.add_item(opt)
	_f_weapon.item_selected.connect(func(idx):
		_preview_weapon = String(WEAPON_OPTIONS[idx][1]); _refresh_preview())
	_style_input(_f_weapon)
	body.add_child(_form_row("Demo weapon", _f_weapon))
	var rot_btn := Button.new()
	rot_btn.text = "↻ Rotate Direction"
	rot_btn.pressed.connect(func():
		_preview_dir = (_preview_dir + 1) % 8
		if _preview_char: _preview_char.call("set_direction", _preview_dir))
	_style_secondary_button(rot_btn)
	body.add_child(rot_btn)
	col.add_child(_section_card("01", "Body", body))

	# DAMAGE card.
	var dmg := VBoxContainer.new()
	dmg.add_theme_constant_override("separation", 14)
	_f_dmg = SpinBox.new()
	_f_dmg.min_value = 0.1; _f_dmg.max_value = 10.0; _f_dmg.step = 0.1
	_f_dmg.value = 1.0
	_f_dmg.value_changed.connect(func(v): _def.damage_mult = float(v))
	_style_input(_f_dmg)
	dmg.add_child(_form_row("Mult", _f_dmg))
	var hint := Label.new()
	hint.text = "Damage shape, range, and angle live on the SkillDef and are tuned per-skill in the .tres."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_color_override("font_color", COL_TEXT_FAINT)
	hint.add_theme_font_size_override("font_size", 10)
	dmg.add_child(hint)
	col.add_child(_section_card("02", "Damage", dmg))

	# Tips card.
	var tips_v := VBoxContainer.new()
	var tips := Label.new()
	tips.text = "Keys 1-6 fire Attack1-Special1 in the preview.\nKey 0 returns to Idle.\nDrag the blue / red markers in the preview to set spawn / impact offsets.\nDrag the dummy enemy to reposition it."
	tips.autowrap_mode = TextServer.AUTOWRAP_WORD
	tips.add_theme_color_override("font_color", COL_TEXT_FAINT)
	tips.add_theme_font_size_override("font_size", 10)
	tips_v.add_child(tips)
	col.add_child(_section_card("03", "Hotkeys", tips_v))
	return col

func _build_col_overlays() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)

	# OVERLAYS — each row inline: label / dropdown / swatch.
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 14)
	_f_effect_a = OptionButton.new()
	for o in EFFECT_OPTIONS: _f_effect_a.add_item(o if o != "" else "(none)")
	_f_effect_a.item_selected.connect(func(idx):
		_def.effect_a_folder = EFFECT_OPTIONS[idx]; _refresh_preview())
	_style_input(_f_effect_a)
	var sw_a := _swatch(
		func(): return _def.effect_a_color,
		func(c): _def.effect_a_color = c; _refresh_preview())
	ov.add_child(_form_row("Effect A", _f_effect_a, sw_a))

	_f_effect_b = OptionButton.new()
	for o in EFFECT_OPTIONS: _f_effect_b.add_item(o if o != "" else "(none)")
	_f_effect_b.item_selected.connect(func(idx):
		_def.effect_b_folder = EFFECT_OPTIONS[idx]; _refresh_preview())
	_style_input(_f_effect_b)
	var sw_b := _swatch(
		func(): return _def.effect_b_color,
		func(c): _def.effect_b_color = c; _refresh_preview())
	ov.add_child(_form_row("Effect B", _f_effect_b, sw_b))

	_f_slash = OptionButton.new()
	for o in SLASH_OPTIONS: _f_slash.add_item(o if o != "" else "(none)")
	_f_slash.item_selected.connect(func(idx):
		_def.slash_folder = SLASH_OPTIONS[idx]; _refresh_preview())
	_style_input(_f_slash)
	var sw_s := _swatch(
		func(): return _def.slash_color,
		func(c): _def.slash_color = c; _refresh_preview())
	ov.add_child(_form_row("Slash", _f_slash, sw_s))

	_color_btns = [sw_a, sw_b, sw_s]
	col.add_child(_section_card("04", "Overlays", ov))

	# Layer guide.
	var guide_v := VBoxContainer.new()
	var guide := Label.new()
	guide.text = "A and B stack on the body rig. Slash plays on the dedicated weapon-trail layer above the mainhand. Each gets its own palette tint via the luminance-recolor shader."
	guide.autowrap_mode = TextServer.AUTOWRAP_WORD
	guide.add_theme_color_override("font_color", COL_TEXT_FAINT)
	guide.add_theme_font_size_override("font_size", 10)
	guide_v.add_child(guide)
	col.add_child(_section_card("05", "Layer Order", guide_v))
	return col

func _build_col_projectile() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)

	# PROJECTILE — pack/cat/name + color swatch.
	var pj := VBoxContainer.new()
	pj.add_theme_constant_override("separation", 8)
	_f_proj_pack = OptionButton.new()
	for label in _projectile_pack_labels(): _f_proj_pack.add_item(label)
	_f_proj_pack.item_selected.connect(_on_proj_pack_changed)
	_style_input(_f_proj_pack)
	pj.add_child(_form_row("Pack", _f_proj_pack))

	_f_proj_cat = OptionButton.new()
	_f_proj_cat.item_selected.connect(_on_proj_cat_changed)
	_style_input(_f_proj_cat)
	pj.add_child(_form_row("Category", _f_proj_cat))

	_f_proj_name = OptionButton.new()
	_f_proj_name.item_selected.connect(_on_proj_name_changed)
	_style_input(_f_proj_name)
	_f_proj_color_btn = _swatch(
		func(): return _def.projectile_color,
		func(c): _def.projectile_color = c)
	pj.add_child(_form_row("Name", _f_proj_name, _f_proj_color_btn))

	_proj_info = Label.new()
	_proj_info.text = "(no projectile selected)"
	_proj_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_proj_info.add_theme_color_override("font_color", COL_TEXT_FAINT)
	_proj_info.add_theme_font_size_override("font_size", 10)
	pj.add_child(_proj_info)
	col.add_child(_section_card("06", "Projectile", pj))

	# MOTION + TIMING merged.
	var mt := VBoxContainer.new()
	mt.add_theme_constant_override("separation", 8)
	_f_proj_motion = OptionButton.new()
	for o in MOTION_OPTIONS: _f_proj_motion.add_item(o)
	_f_proj_motion.item_selected.connect(func(idx):
		_def.projectile_motion = MOTION_OPTIONS[idx]; _refresh_proj_visibility())
	_style_input(_f_proj_motion)
	mt.add_child(_form_row("Motion", _f_proj_motion))

	_f_proj_scale = SpinBox.new()
	_f_proj_scale.min_value = 0.1; _f_proj_scale.max_value = 4.0; _f_proj_scale.step = 0.05
	_f_proj_scale.value = 0.5
	_f_proj_scale.value_changed.connect(func(v): _def.projectile_scale = float(v))
	_style_input(_f_proj_scale)
	mt.add_child(_form_row("Scale", _f_proj_scale))

	_f_proj_fps = SpinBox.new()
	_f_proj_fps.min_value = 1; _f_proj_fps.max_value = 60; _f_proj_fps.step = 1
	_f_proj_fps.value = 24
	_f_proj_fps.value_changed.connect(func(v): _def.projectile_fps = float(v))
	_style_input(_f_proj_fps)
	mt.add_child(_form_row("FPS", _f_proj_fps))

	_f_proj_speed = SpinBox.new()
	_f_proj_speed.min_value = 50; _f_proj_speed.max_value = 2000; _f_proj_speed.step = 10
	_f_proj_speed.value = 220
	_f_proj_speed.value_changed.connect(func(v): _def.projectile_speed = float(v))
	_style_input(_f_proj_speed)
	mt.add_child(_form_row("Speed", _f_proj_speed))

	col.add_child(_section_card("07", "Motion & Timing", mt))

	# FRAME TRIM + ARC params.
	var ft := VBoxContainer.new()
	ft.add_theme_constant_override("separation", 8)
	_f_proj_start = SpinBox.new()
	_f_proj_start.min_value = 0; _f_proj_start.max_value = 64; _f_proj_start.step = 1
	_f_proj_start.value = 0
	_f_proj_start.value_changed.connect(func(v): _def.projectile_start_frame = int(v))
	_style_input(_f_proj_start)
	ft.add_child(_form_row("Start frame", _f_proj_start))

	_f_proj_end = SpinBox.new()
	_f_proj_end.min_value = -1; _f_proj_end.max_value = 64; _f_proj_end.step = 1
	_f_proj_end.value = -1
	_f_proj_end.value_changed.connect(func(v): _def.projectile_end_frame = int(v))
	_style_input(_f_proj_end)
	ft.add_child(_form_row("End frame", _f_proj_end))

	_f_proj_arc_count = SpinBox.new()
	_f_proj_arc_count.min_value = 1; _f_proj_arc_count.max_value = 32; _f_proj_arc_count.step = 1
	_f_proj_arc_count.value = 8
	_f_proj_arc_count.value_changed.connect(func(v): _def.projectile_arc_count = int(v))
	_style_input(_f_proj_arc_count)
	ft.add_child(_form_row("Arc count", _f_proj_arc_count))

	_f_proj_arc_radius = SpinBox.new()
	_f_proj_arc_radius.min_value = 0; _f_proj_arc_radius.max_value = 600; _f_proj_arc_radius.step = 8
	_f_proj_arc_radius.value = 120
	_f_proj_arc_radius.value_changed.connect(func(v): _def.projectile_arc_radius = float(v))
	_style_input(_f_proj_arc_radius)
	ft.add_child(_form_row("Arc radius", _f_proj_arc_radius))

	col.add_child(_section_card("08", "Trim & Arc", ft))
	return col

func _build_col_preview() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)

	var card := PanelContainer.new()
	var sb := _section_panel_style()
	sb.bg_color = COL_BG    # darker — preview is the "work surface"
	card.add_theme_stylebox_override("panel", sb)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(card)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)

	var hdr := Label.new()
	hdr.text = "PREVIEW"
	hdr.add_theme_color_override("font_color", COL_TEXT_DIM)
	hdr.add_theme_font_size_override("font_size", 11)
	v.add_child(hdr)

	# Toolbar above the viewport.
	var tb := HBoxContainer.new()
	tb.add_theme_constant_override("separation", 8)
	var play_anim_btn := Button.new()
	play_anim_btn.text = "↻ Replay"
	play_anim_btn.pressed.connect(_refresh_preview)
	_style_secondary_button(play_anim_btn)
	tb.add_child(play_anim_btn)
	var fire_btn := Button.new()
	fire_btn.text = "▶ Play Skill"
	fire_btn.tooltip_text = "Plays the trigger anim + spawns the projectile from origin to target."
	fire_btn.pressed.connect(_on_play_skill)
	_style_primary_button(fire_btn)
	tb.add_child(fire_btn)
	v.add_child(tb)

	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.stretch_shrink = _preview_shrink
	# Min size deliberately small so the viewport can shrink to fit
	# narrow / short windows without forcing the editor to overflow.
	holder.custom_minimum_size = Vector2(260, 260)
	holder.mouse_filter = Control.MOUSE_FILTER_PASS  # so wheel events fire
	holder.gui_input.connect(_on_preview_wheel)
	_preview_holder = holder
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	v.add_child(holder)
	_preview_vp = SubViewport.new()
	# Stretch + stretch_shrink will resize the viewport to holder/SHRINK
	# automatically; the explicit size below is just a starting value.
	_preview_vp.size = Vector2i(140, 140)
	_preview_vp.transparent_bg = true
	_preview_vp.disable_3d = true
	_preview_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	# Render every frame so the LayeredCharacter's anim playback shows
	# motion. Default UPDATE_WHEN_VISIBLE only repaints on dirty events
	# and the rig was freezing on its first frame.
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	holder.add_child(_preview_vp)
	_preview_char = LayeredCharacterScript.new()
	(_preview_char as Node2D).position = _PREVIEW_PLAYER_POS
	# Match in-game scale (player_layered.gd uses 0.5 of the 128 px
	# LayeredCharacter sheets so the silhouette is 64 px tall). The
	# SubViewportContainer's stretch_shrink handles the on-screen zoom.
	(_preview_char as Node2D).scale = Vector2(0.5, 0.5)
	_preview_vp.add_child(_preview_char)
	# Two draggable markers: BLUE (origin offset, attached to player) and
	# RED (target offset, attached to a fixed test-target reference).
	# Show/hide is driven by the projectile motion mode. Dragging either
	# updates the corresponding offset on the current SkillDef.
	# Dummy enemy at the target reference so the red marker can be
	# placed relative to a visual silhouette (chest, head, feet) instead
	# of empty space. Draggable — moving it slides the red marker so the
	# saved target_offset stays in the enemy's local frame.
	_dummy_enemy = _make_dummy_enemy()
	_dummy_enemy.position = _target_ref
	_preview_vp.add_child(_dummy_enemy)

	_origin_marker = _make_offset_marker(Color(0.3, 0.6, 1.0, 1.0),
		func(world_pos): _def.projectile_origin_offset = world_pos - _PREVIEW_PLAYER_POS)
	(_origin_marker as Node2D).position = _PREVIEW_PLAYER_POS + Vector2(0, -32)
	_preview_vp.add_child(_origin_marker)

	_target_marker = _make_offset_marker(Color(1.0, 0.25, 0.25, 1.0),
		func(world_pos): _def.projectile_target_offset = world_pos - _target_ref)
	(_target_marker as Node2D).position = _target_ref + Vector2(0, -32)
	_preview_vp.add_child(_target_marker)
	return col

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

# One-shot spawn of the chosen world fx at the rig's preview anchor.
# Triggered when the user picks a fx folder, picks its color, or
# replays. The fx auto-frees on its own (explosion_anim plays once).
func _spawn_world_fx_preview() -> void:
	if _def == null or _preview_char == null: return
	var folder: String = SkillDefScript.world_fx_full_path(String(_def.world_fx_folder))
	if folder == "": return
	var anchor_pos: Vector2 = (_preview_char as Node2D).position
	var fx: Node2D = ExplosionAnimScript.spawn(_preview_vp, anchor_pos, folder)
	if fx and _def.world_fx_color != Color.WHITE:
		# Tint via modulate. Effect frames are typically white/yellow
		# so modulate works without needing the luminance shader.
		fx.modulate = _def.world_fx_color

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
	# Projectile fields.
	_load_projectile_fields_from_def()

func _set_option_to_value(ob: OptionButton, options: Array, value: String) -> void:
	var idx := options.find(value)
	if idx >= 0:
		ob.selected = idx

# ---- Projectile editor (Phases 2-4) ------------------------------------

func _build_projectile_section(parent: Node) -> void:
	_add_label(parent, "\nProjectile", 14)
	var grid := GridContainer.new(); grid.columns = 2
	parent.add_child(grid)

	_f_proj_pack = _add_option_row(grid, "Pack", _projectile_pack_labels(),
		func(idx): _on_proj_pack_changed(idx))
	_f_proj_cat = _add_option_row(grid, "Category", [""],
		func(idx): _on_proj_cat_changed(idx))
	_f_proj_name = _add_option_row(grid, "Name", [""],
		func(idx): _on_proj_name_changed(idx))
	_f_proj_motion = _add_option_row(grid, "Motion", MOTION_OPTIONS,
		func(idx): _def.projectile_motion = MOTION_OPTIONS[idx]; _refresh_proj_visibility())
	_f_proj_start = _add_spin_row(grid, "Start frame", 0, 64, 1,
		func(v): _def.projectile_start_frame = int(v))
	_f_proj_end = _add_spin_row(grid, "End frame (-1=full)", -1, 64, 1,
		func(v): _def.projectile_end_frame = int(v))
	_f_proj_fps = _add_spin_row(grid, "FPS", 1, 60, 1,
		func(v): _def.projectile_fps = float(v))
	_f_proj_speed = _add_spin_row(grid, "Speed (travel)", 50, 2000, 10,
		func(v): _def.projectile_speed = float(v))
	_f_proj_arc_count = _add_spin_row(grid, "Arc count", 1, 32, 1,
		func(v): _def.projectile_arc_count = int(v))
	_f_proj_arc_radius = _add_spin_row(grid, "Arc radius", 0, 600, 8,
		func(v): _def.projectile_arc_radius = float(v))
	_f_proj_scale = _add_spin_row(grid, "Render scale", 0.1, 4.0, 0.05,
		func(v): _def.projectile_scale = float(v))

	# Color row for projectile.
	var color_row := HBoxContainer.new()
	parent.add_child(color_row)
	var clbl := Label.new(); clbl.text = "Projectile Color"; color_row.add_child(clbl)
	_f_proj_color_btn = Button.new()
	_f_proj_color_btn.custom_minimum_size = Vector2(72, 28)
	_f_proj_color_btn.pressed.connect(func():
		_open_palette_popup(_f_proj_color_btn,
			func(): return _def.projectile_color,
			func(c): _def.projectile_color = c))
	color_row.add_child(_f_proj_color_btn)
	_paint_color_button(_f_proj_color_btn, _def.projectile_color)

	_proj_info = Label.new()
	_proj_info.text = "(no projectile selected)"
	_proj_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	parent.add_child(_proj_info)

func _projectile_pack_labels() -> Array:
	var packs: Array = ["(none)"]
	for k in _projectile_registry.keys():
		packs.append(String(k))
	return packs

func _on_proj_pack_changed(idx: int) -> void:
	if idx <= 0:
		_def.projectile_pack = ""
		_def.projectile_category = ""
		_def.projectile_name = ""
		_repopulate_proj_cat([])
		_repopulate_proj_name([])
		_update_proj_info()
		return
	var pack: String = String(_projectile_registry.keys()[idx - 1])
	_def.projectile_pack = pack
	var cats: Array = _projectile_registry[pack].keys()
	_repopulate_proj_cat(cats)
	if cats.size() > 0:
		_def.projectile_category = String(cats[0])
		var names: Array = _projectile_registry[pack][cats[0]].keys()
		_repopulate_proj_name(names)
		# Auto-select first name so the cascading pickers always leave
		# the SkillDef in a valid (and visible) state — otherwise the
		# status label sits on "(no projectile selected)" until the user
		# manually opens the Name dropdown.
		if names.size() > 0:
			_def.projectile_name = String(names[0])
			_f_proj_name.selected = 0
	_update_proj_info()

func _on_proj_cat_changed(idx: int) -> void:
	var pack: String = String(_def.projectile_pack)
	if pack == "" or not _projectile_registry.has(pack): return
	var cats: Array = _projectile_registry[pack].keys()
	if idx < 0 or idx >= cats.size(): return
	_def.projectile_category = String(cats[idx])
	var names: Array = _projectile_registry[pack][cats[idx]].keys()
	_repopulate_proj_name(names)
	# Auto-select the first name in the new category so projectile_name
	# is always populated whenever pack/category change.
	if names.size() > 0:
		_def.projectile_name = String(names[0])
		_f_proj_name.selected = 0
	_update_proj_info()

func _on_proj_name_changed(idx: int) -> void:
	var pack: String = String(_def.projectile_pack)
	var cat: String = String(_def.projectile_category)
	if pack == "" or cat == "": return
	if not _projectile_registry.has(pack): return
	if not _projectile_registry[pack].has(cat): return
	var names: Array = _projectile_registry[pack][cat].keys()
	if idx < 0 or idx >= names.size(): return
	_def.projectile_name = String(names[idx])
	# Auto-pick the registry's motion default if the user hasn't set one.
	var entry: Dictionary = _projectile_registry[pack][cat][names[idx]]
	if String(_def.projectile_motion) == "":
		_def.projectile_motion = String(entry.get("motion_default", "travel"))
		_set_option_to_value(_f_proj_motion, MOTION_OPTIONS, _def.projectile_motion)
	# Clamp end-frame to the entry's frame_count - 1 if out of range.
	var fc: int = int(entry.get("frame_count", 1))
	if int(_def.projectile_end_frame) >= fc:
		_def.projectile_end_frame = -1
		_f_proj_end.value = -1
	_update_proj_info()

func _repopulate_proj_cat(cats: Array) -> void:
	_f_proj_cat.clear()
	for c in cats:
		_f_proj_cat.add_item(String(c))

func _repopulate_proj_name(names: Array) -> void:
	_f_proj_name.clear()
	for n in names:
		_f_proj_name.add_item(String(n))

func _update_proj_info() -> void:
	if _proj_info == null: return
	var pack: String = String(_def.projectile_pack)
	var cat: String = String(_def.projectile_category)
	var name: String = String(_def.projectile_name)
	if pack == "" or cat == "" or name == "":
		_proj_info.text = "(no projectile selected)"
		return
	var entry := ProjectileRuntimeScript.lookup(pack, cat, name)
	if entry.is_empty():
		_proj_info.text = "(missing in registry)"
		return
	_proj_info.text = "%s/%s/%s\n%d frames, default motion: %s" % [
		pack, cat, name, int(entry.get("frame_count", 0)), String(entry.get("motion_default", "?"))]

func _refresh_proj_visibility() -> void:
	# Speed only matters for travel; arc params only for arc_rain. Keep
	# them present but greyed instead of hiding so the layout doesn't jump.
	var motion: String = String(_def.projectile_motion)
	if _f_proj_speed: _f_proj_speed.editable = (motion == "travel")
	if _f_proj_arc_count: _f_proj_arc_count.editable = (motion == "arc_rain")
	if _f_proj_arc_radius: _f_proj_arc_radius.editable = (motion == "arc_rain")
	# Marker visibility:
	#   at_player → blue only (where the FX hugs the caster)
	#   at_target → red  only (where the FX impacts)
	#   travel    → both (origin AND impact)
	#   arc_rain  → red  only (impact center; spread is numeric)
	var show_blue: bool = motion in ["at_player", "travel"]
	var show_red:  bool = motion in ["at_target", "travel", "arc_rain"]
	if _origin_marker: _origin_marker.visible = show_blue
	if _target_marker: _target_marker.visible = show_red

func _load_projectile_fields_from_def() -> void:
	if _f_proj_pack == null: return
	# Pack
	var packs: Array = _projectile_registry.keys()
	var pi: int = packs.find(String(_def.projectile_pack))
	_f_proj_pack.selected = (pi + 1) if pi >= 0 else 0
	# Category + Name
	if String(_def.projectile_pack) != "" and _projectile_registry.has(_def.projectile_pack):
		var cats: Array = _projectile_registry[_def.projectile_pack].keys()
		_repopulate_proj_cat(cats)
		var ci: int = cats.find(String(_def.projectile_category))
		if ci >= 0:
			_f_proj_cat.selected = ci
			var names: Array = _projectile_registry[_def.projectile_pack][cats[ci]].keys()
			_repopulate_proj_name(names)
			var ni: int = names.find(String(_def.projectile_name))
			if ni >= 0:
				_f_proj_name.selected = ni
	_set_option_to_value(_f_proj_motion, MOTION_OPTIONS, String(_def.projectile_motion))
	_f_proj_start.value = int(_def.projectile_start_frame)
	_f_proj_end.value = int(_def.projectile_end_frame)
	_f_proj_fps.value = float(_def.projectile_fps)
	_f_proj_speed.value = float(_def.projectile_speed)
	_f_proj_arc_count.value = int(_def.projectile_arc_count)
	_f_proj_arc_radius.value = float(_def.projectile_arc_radius)
	_f_proj_scale.value = float(_def.projectile_scale)
	_paint_color_button(_f_proj_color_btn, _def.projectile_color)
	# Sync marker positions to the loaded def's saved offsets.
	if _origin_marker:
		(_origin_marker as Node2D).position = _PREVIEW_PLAYER_POS + _def.projectile_origin_offset
	if _target_marker:
		(_target_marker as Node2D).position = _target_ref + _def.projectile_target_offset
	_refresh_proj_visibility()
	_update_proj_info()

# ---- Visual stage (Phase 3) -------------------------------------------

func _make_offset_marker(color: Color, on_moved: Callable) -> Node2D:
	# Configurable spawn / impact marker. Renders as a solid circle
	# outlined in the given color (blue = origin, red = target). Drag
	# with LMB; on_moved is called with the new viewport position so the
	# editor can save the corresponding offset to the SkillDef.
	var marker := Node2D.new()
	var sc := GDScript.new()
	sc.source_code = """
extends Node2D
var marker_color: Color = Color.WHITE
var on_moved: Callable = Callable()
var editor_ref: Node = null
var _drag := false
func _process(_d: float) -> void:
	queue_redraw()
func _draw() -> void:
	var fill := marker_color; fill.a = 0.22
	draw_circle(Vector2.ZERO, 12.0, fill)
	draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 32, marker_color, 2.0)
	draw_line(Vector2(-7, 0), Vector2(7, 0), marker_color, 1.5)
	draw_line(Vector2(0, -7), Vector2(0, 7), marker_color, 1.5)
func _input(ev: InputEvent) -> void:
	if not visible: return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		var lp := get_local_mouse_position()
		if ev.pressed and lp.length() < 22.0:
			# Only claim the click if no one else has already grabbed it.
			if editor_ref and editor_ref._drag_owner == null:
				_drag = true
				editor_ref._drag_owner = self
		elif not ev.pressed:
			if _drag and editor_ref and editor_ref._drag_owner == self:
				editor_ref._drag_owner = null
			_drag = false
	elif ev is InputEventMouseMotion and _drag:
		position += get_local_mouse_position()
		if on_moved.is_valid(): on_moved.call(position)
"""
	sc.reload()
	marker.set_script(sc)
	marker.set("marker_color", color)
	marker.set("on_moved", on_moved)
	marker.set("editor_ref", self)
	return marker

func _make_dummy_enemy() -> Node2D:
	# Static skeleton-warrior idle frame as a visual reference for placing
	# the red target marker. Draggable — clicking on the silhouette and
	# dragging moves the enemy AND its attached red marker so the saved
	# offset stays in the enemy's local frame.
	var n := Node2D.new()
	var sprite := Sprite2D.new()
	var idle_path := "res://assets/charachters/Sprites/2D HD Undead pack 1/2D HD Undead pack 1/Spritesheets/With shadow/6Warrior/Idle.png"
	if ResourceLoader.exists(idle_path):
		var sheet: Texture2D = load(idle_path)
		var fh: int = sheet.get_height() / 8
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(0, 2 * fh, fh, fh)
		sprite.texture = atlas
	sprite.centered = true
	sprite.offset = Vector2(0, -42)
	# Match the in-game 64 px target silhouette (128 px source × 0.5).
	sprite.scale = Vector2(0.5, 0.5)
	n.add_child(sprite)
	# Drag behaviour. Hit zone is a 32 px circle around the body center
	# (offset up so it sits on the silhouette, not at the foot).
	var sc := GDScript.new()
	sc.source_code = """
extends Node2D
var editor_ref: Node = null
var _drag := false
func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		var lp := get_local_mouse_position() - Vector2(0, -28)
		if ev.pressed and lp.length() < 28.0:
			# Don't grab the click if the marker (or anything else) has
			# already claimed it — markers are smaller and sit on top
			# of the silhouette, so we want them to win on overlap.
			if editor_ref and editor_ref._drag_owner == null:
				_drag = true
				editor_ref._drag_owner = self
		elif not ev.pressed:
			if _drag and editor_ref and editor_ref._drag_owner == self:
				editor_ref._drag_owner = null
			_drag = false
	elif ev is InputEventMouseMotion and _drag:
		position += get_local_mouse_position()
		if editor_ref and editor_ref.has_method('_on_dummy_moved'):
			editor_ref._on_dummy_moved(position)
"""
	sc.reload()
	n.set_script(sc)
	n.set("editor_ref", self)
	return n

func _on_dummy_moved(new_pos: Vector2) -> void:
	# Slide the red target marker along with the dummy so its on-screen
	# position relative to the enemy (= projectile_target_offset) stays
	# consistent. _target_ref tracks the enemy's live position.
	_target_ref = new_pos
	if _target_marker:
		(_target_marker as Node2D).position = _target_ref + _def.projectile_target_offset

func _process(_dt: float) -> void:
	# Auto-fire the projectile each time the body anim loops, so the
	# preview shows the skill vfx + projectile in continuous sync. The
	# user no longer has to mash Play Skill to see the loop.
	if _preview_char == null or _def == null:
		return
	if String(_def.projectile_pack) == "" or String(_def.projectile_name) == "":
		_proj_last_frame = -1
		return
	var cur: int = int(_preview_char.get("_frame"))
	if _proj_last_frame >= 0 and cur < _proj_last_frame:
		# Wraparound — anim looped. Fire a fresh projectile.
		ProjectileRuntimeScript.play(_def, _preview_vp, _PREVIEW_PLAYER_POS, _target_ref)
	_proj_last_frame = cur

func _on_preview_wheel(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton): return
	var mb := ev as InputEventMouseButton
	if not mb.pressed: return
	var prev := _preview_shrink
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_preview_shrink = min(_preview_shrink + 1, _PREVIEW_SHRINK_MAX)
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_preview_shrink = max(_preview_shrink - 1, _PREVIEW_SHRINK_MIN)
	else:
		return
	if _preview_shrink != prev and _preview_holder:
		_preview_holder.stretch_shrink = _preview_shrink

func _on_play_skill() -> void:
	# Reset body rig and then fire the projectile with the player at the
	# fixed preview position and the test target at the reference point.
	# ProjectileRuntime adds origin/target offsets internally, so we pass
	# the bare anchors here — the markers' positions ARE the offsets.
	_refresh_preview()
	if _def == null or _preview_vp == null:
		return
	if String(_def.projectile_pack) == "" or String(_def.projectile_name) == "":
		return
	ProjectileRuntimeScript.play(_def, _preview_vp, _PREVIEW_PLAYER_POS, _target_ref)
