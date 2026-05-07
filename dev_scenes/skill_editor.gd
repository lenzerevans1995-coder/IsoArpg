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
const _PREVIEW_SHRINK := 4
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
	# Fantasy-tileset world-space FX (AoE / Bolt / Buff# / Cone / Dash /
	# Hook / LevelUp). Spawned once at the player's foot when the skill
	# fires. Doesn't loop — explosion_anim auto-frees on completion.
	var world_fx_labels: Array = []
	for opt in _world_fx_options: world_fx_labels.append(opt if opt != "" else "(none)")
	_f_world_fx = _add_option_row(grid, "World FX", world_fx_labels, func(idx):
		_def.world_fx_folder = String(_world_fx_options[idx])
		_spawn_world_fx_preview())
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
		_add_color_row(color_grid, "World FX",
			func(): return _def.world_fx_color,
			func(c): _def.world_fx_color = c; _spawn_world_fx_preview()),
	]

	# Projectile section — pack/cat/name cascading pickers, motion mode,
	# frame trim, fps, speed, and arc-rain params.
	_build_projectile_section(left)

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
	play_btn.text = "Replay Anim"
	play_btn.pressed.connect(_refresh_preview)
	ctrl_row.add_child(play_btn)
	# Phase 3 stage: fire the body anim AND spawn the projectile against
	# the draggable target marker — same path as the in-game caster.
	var fire_btn := Button.new()
	fire_btn.text = "▶ Play Skill"
	fire_btn.tooltip_text = "Plays the trigger anim + spawns the projectile from player to the red target marker (drag the marker with the mouse)."
	fire_btn.pressed.connect(_on_play_skill)
	ctrl_row.add_child(fire_btn)

	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.stretch_shrink = _PREVIEW_SHRINK
	holder.custom_minimum_size = Vector2(560, 560)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	right.add_child(holder)
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
