extends Control
class_name CharacterCreator

# Modal character creator. Single-column list of slots with < / > cyclers, a
# live preview that auto-rotates through the 8 directions so the player can see
# the back/sides, and a name field. Saves to user://profile.json on confirm.
#
# Built procedurally in _ready() — no .tscn required, all theme/styling here.

signal confirmed(loadout: Dictionary)
signal cancelled()

const PREVIEW_SCALE := 1.8

# Slot rows shown in the creator (cosmetic starters only).
const SLOT_ROWS := [
	{"key": "body",  "label": "Skin Tone", "options_method": "_options_body"},
	{"key": "head",  "label": "Head",      "options_method": "_options_head"},
	{"key": "hands", "label": "Hands",     "options_method": "_options_hands"},
	{"key": "chest", "label": "Chest",     "options_method": "_options_chest"},
	{"key": "legs",  "label": "Legs",      "options_method": "_options_legs"},
	{"key": "shoes", "label": "Shoes",     "options_method": "_options_shoes"},
]

# Palette: dark slate UI with warm gold accents — fits a fantasy game.
const COL_BG := Color(0.06, 0.07, 0.10, 0.96)
const COL_PANEL := Color(0.12, 0.14, 0.18)
const COL_PANEL_EDGE := Color(0.28, 0.24, 0.16)
const COL_ROW := Color(0.16, 0.18, 0.22)
const COL_ROW_HOVER := Color(0.20, 0.22, 0.28)
const COL_TEXT := Color(0.92, 0.90, 0.85)
const COL_MUTED := Color(0.65, 0.62, 0.55)
const COL_ACCENT := Color(0.86, 0.72, 0.36)
const COL_ACCENT_HI := Color(1.0, 0.86, 0.46)

var _loadout: Dictionary = {}
var _preview: LayeredCharacter
var _name_edit: LineEdit
var _slot_value_labels: Dictionary = {}    # slot_key -> Label
var _slot_options: Dictionary = {}         # slot_key -> Array of folder names
var _slot_index: Dictionary = {}           # slot_key -> int
var _swatch_buttons: Dictionary = {}       # slot_key -> Array of Buttons (for selected-state ring)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_loadout = Loadout.load_or_default()
	for row in SLOT_ROWS:
		var key: String = row["key"]
		var opts: Array = call(row["options_method"])
		_slot_options[key] = opts
		var current: String = String(_loadout.get(key, ""))
		var idx: int = max(0, opts.find(current))
		if idx < 0:
			idx = 0
		_slot_index[key] = idx
		_loadout[key] = opts[idx]

	_build_ui()
	_refresh_preview()

# --- Option lists -----------------------------------------------------------

func _options_body() -> Array:  return ItemsDB.STARTER_BODIES.duplicate()
func _options_head() -> Array:
	var a := []
	for n in range(1, ItemsDB.STARTER_HEADS + 1): a.append("Head%d" % n)
	return a
func _options_hands() -> Array:
	var a := []
	for n in ItemsDB.STARTER_HANDS: a.append("Hands%d" % n)
	return a
func _options_chest() -> Array:
	var a := []
	for n in ItemsDB.STARTER_CHESTS: a.append("Chest%d" % n)
	return a
func _options_legs() -> Array:
	var a := []
	for n in ItemsDB.STARTER_LEGS: a.append("Legs%d" % n)
	return a
func _options_shoes() -> Array:
	var a := []
	for n in ItemsDB.STARTER_SHOES: a.append("Shoes%d" % n)
	return a

# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	# Full-screen dim backdrop.
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Center the panel via a full-rect CenterContainer so it tracks any
	# viewport size and stays perfectly centered (manual offsets drifted
	# off-screen on non-1080p resolutions).
	var center_root := CenterContainer.new()
	center_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	center_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center_root)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 540)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	center_root.add_child(panel)

	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 18)
	panel.add_child(root_v)

	# Title bar.
	var title := Label.new()
	title.text = "CREATE YOUR CHARACTER"
	title.add_theme_color_override("font_color", COL_ACCENT)
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title_pad := MarginContainer.new()
	title_pad.add_theme_constant_override("margin_top", 18)
	title_pad.add_theme_constant_override("margin_left", 24)
	title_pad.add_theme_constant_override("margin_right", 24)
	title_pad.add_theme_constant_override("margin_bottom", 4)
	title_pad.add_child(title)
	root_v.add_child(title_pad)

	# Two-column body: preview (left) and slot list (right).
	var body_pad := MarginContainer.new()
	body_pad.add_theme_constant_override("margin_left", 24)
	body_pad.add_theme_constant_override("margin_right", 24)
	body_pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_v.add_child(body_pad)

	var body_h := HBoxContainer.new()
	body_h.add_theme_constant_override("separation", 24)
	body_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_pad.add_child(body_h)

	body_h.add_child(_build_preview_panel())
	body_h.add_child(_build_slot_column())

	# Footer: name + buttons.
	root_v.add_child(_build_footer())

func _build_preview_panel() -> Control:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(240, 360)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Preview backdrop is lighter than the panel so the greyscale templates
	# read clearly against it.
	var preview_bg := StyleBoxFlat.new()
	preview_bg.bg_color = Color(0.32, 0.34, 0.40)
	preview_bg.border_color = Color(0.20, 0.20, 0.24)
	preview_bg.set_border_width_all(1)
	preview_bg.set_corner_radius_all(4)
	box.add_theme_stylebox_override("panel", preview_bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_child(center)

	var vp_container := SubViewportContainer.new()
	vp_container.stretch = true
	vp_container.custom_minimum_size = Vector2(220, 340)
	center.add_child(vp_container)

	var vp := SubViewport.new()
	vp.size = Vector2i(220, 340)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp_container.add_child(vp)

	_preview = LayeredCharacter.new()
	_preview.position = Vector2(110, 240)
	_preview.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	vp.add_child(_preview)

	# Run a process tick the LayeredCharacter listens to.
	_preview.play_anim("Idle", 12.0, true)
	return box

func _build_slot_column() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Preset picker: 15 shipped Unity presets, each applies a full color set.
	var preset_row := _build_preset_row()
	if preset_row:
		col.add_child(preset_row)

	for row in SLOT_ROWS:
		col.add_child(_build_slot_row(row))
	return col

func _build_preset_row() -> Control:
	var ps: Array = Loadout.presets()
	if ps.is_empty():
		return null
	var bg := PanelContainer.new()
	bg.custom_minimum_size = Vector2(0, 46)
	bg.add_theme_stylebox_override("panel", _make_row_style())

	var h := HBoxContainer.new()
	bg.add_child(h)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 8)
	h.add_child(pad)
	var lbl := Label.new()
	lbl.text = "Preset"
	lbl.add_theme_color_override("font_color", COL_TEXT)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pad.add_child(lbl)

	var swatch_row := HBoxContainer.new()
	swatch_row.add_theme_constant_override("separation", 3)
	h.add_child(swatch_row)
	for i in range(ps.size()):
		var p: Dictionary = ps[i]
		var c := Color(String(p.get("body", "#888888")))
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(20, 24)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_stylebox_override("normal", _make_swatch_style(c, false))
		btn.add_theme_stylebox_override("hover", _make_swatch_style(c, true))
		btn.add_theme_stylebox_override("pressed", _make_swatch_style(c, true))
		btn.pressed.connect(func(): _apply_preset(i))
		swatch_row.add_child(btn)
	return bg

func _apply_preset(index: int) -> void:
	Loadout.apply_preset(_loadout, index)
	# Refresh swatch row selections to match new tints.
	for slot_key in _swatch_buttons.keys():
		var palette: Array = Loadout.palette_for(slot_key)
		var current_hex: String = String(_loadout.get("tints", {}).get(slot_key, ""))
		var btns: Array = _swatch_buttons[slot_key]
		for i in range(btns.size()):
			var pc: Color = palette[i]
			var sel: bool = pc.to_html() == current_hex
			btns[i].add_theme_stylebox_override("normal", _make_swatch_style(pc, sel))
	_refresh_preview()

func _build_slot_row(row: Dictionary) -> Control:
	var key: String = row["key"]
	var label_text: String = row["label"]
	var opts: Array = _slot_options[key]

	var bg := PanelContainer.new()
	bg.custom_minimum_size = Vector2(0, 46)
	bg.add_theme_stylebox_override("panel", _make_row_style())

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	bg.add_child(h)

	# Slot label (left).
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 8)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(pad)

	var name_label := Label.new()
	name_label.text = label_text
	name_label.add_theme_color_override("font_color", COL_TEXT)
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pad.add_child(name_label)

	# Cycler: < value > .
	var prev := Button.new()
	prev.text = "<"
	prev.custom_minimum_size = Vector2(40, 40)
	prev.flat = true
	prev.add_theme_font_size_override("font_size", 18)
	prev.add_theme_color_override("font_color", COL_ACCENT)
	prev.add_theme_color_override("font_hover_color", COL_ACCENT_HI)
	prev.pressed.connect(func(): _cycle_slot(key, -1))
	h.add_child(prev)

	var value := Label.new()
	value.custom_minimum_size = Vector2(90, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.add_theme_color_override("font_color", COL_ACCENT_HI)
	value.add_theme_font_size_override("font_size", 16)
	value.text = "%s  (%d / %d)" % [opts[_slot_index[key]], _slot_index[key] + 1, opts.size()]
	_slot_value_labels[key] = value
	h.add_child(value)

	var nxt := Button.new()
	nxt.text = ">"
	nxt.custom_minimum_size = Vector2(40, 40)
	nxt.flat = true
	nxt.add_theme_font_size_override("font_size", 18)
	nxt.add_theme_color_override("font_color", COL_ACCENT)
	nxt.add_theme_color_override("font_hover_color", COL_ACCENT_HI)
	nxt.pressed.connect(func(): _cycle_slot(key, 1))
	h.add_child(nxt)

	# Color swatches for layers that support tinting.
	var palette: Array = Loadout.palette_for(key)
	if palette.size() > 1:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(8, 0)
		h.add_child(spacer)
		var swatch_row := HBoxContainer.new()
		swatch_row.add_theme_constant_override("separation", 4)
		h.add_child(swatch_row)
		var btns: Array = []
		var current_hex: String = String(_loadout.get("tints", {}).get(key, palette[0].to_html()))
		for i in range(palette.size()):
			var c: Color = palette[i]
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(22, 22)
			btn.flat = false
			btn.focus_mode = Control.FOCUS_NONE
			var selected: bool = c.to_html() == current_hex
			btn.add_theme_stylebox_override("normal", _make_swatch_style(c, selected))
			btn.add_theme_stylebox_override("hover", _make_swatch_style(c, true))
			btn.add_theme_stylebox_override("pressed", _make_swatch_style(c, true))
			btn.pressed.connect(func(): _pick_tint(key, c))
			swatch_row.add_child(btn)
			btns.append(btn)
		_swatch_buttons[key] = btns

	var trail := Control.new()
	trail.custom_minimum_size = Vector2(12, 0)
	h.add_child(trail)

	return bg

func _pick_tint(slot_key: String, c: Color) -> void:
	if not _loadout.has("tints"):
		_loadout["tints"] = {}
	_loadout["tints"][slot_key] = c.to_html()
	# Refresh swatch outlines.
	if _swatch_buttons.has(slot_key):
		var palette: Array = Loadout.palette_for(slot_key)
		var btns: Array = _swatch_buttons[slot_key]
		for i in range(btns.size()):
			var pc: Color = palette[i]
			var sel: bool = pc.to_html() == c.to_html()
			btns[i].add_theme_stylebox_override("normal", _make_swatch_style(pc, sel))
	_refresh_preview()

func _make_swatch_style(c: Color, selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(3)
	s.border_color = COL_ACCENT_HI if selected else Color(0.0, 0.0, 0.0, 0.45)
	s.set_border_width_all(2 if selected else 1)
	return s

func _build_footer() -> Control:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 24)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_theme_constant_override("margin_bottom", 18)
	pad.add_theme_constant_override("margin_top", 6)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	pad.add_child(h)

	var name_label := Label.new()
	name_label.text = "Name"
	name_label.add_theme_color_override("font_color", COL_MUTED)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(name_label)

	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(260, 40)
	_name_edit.placeholder_text = "Adventurer"
	_name_edit.text = String(_loadout.get("name", ""))
	_name_edit.add_theme_color_override("font_color", COL_TEXT)
	_name_edit.add_theme_color_override("font_placeholder_color", COL_MUTED)
	_name_edit.add_theme_color_override("caret_color", COL_ACCENT)
	_name_edit.add_theme_stylebox_override("normal", _make_inset_style())
	_name_edit.add_theme_stylebox_override("focus", _make_inset_style(true))
	h.add_child(_name_edit)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(120, 44)
	cancel_btn.add_theme_color_override("font_color", COL_MUTED)
	cancel_btn.add_theme_color_override("font_hover_color", COL_TEXT)
	cancel_btn.flat = true
	cancel_btn.pressed.connect(_on_cancel)
	h.add_child(cancel_btn)

	var confirm_btn := Button.new()
	confirm_btn.text = "Begin Adventure"
	confirm_btn.custom_minimum_size = Vector2(180, 44)
	confirm_btn.add_theme_color_override("font_color", Color.BLACK)
	confirm_btn.add_theme_color_override("font_hover_color", Color.BLACK)
	confirm_btn.add_theme_font_size_override("font_size", 16)
	confirm_btn.add_theme_stylebox_override("normal", _make_button_style(COL_ACCENT))
	confirm_btn.add_theme_stylebox_override("hover", _make_button_style(COL_ACCENT_HI))
	confirm_btn.add_theme_stylebox_override("pressed", _make_button_style(COL_ACCENT))
	confirm_btn.pressed.connect(_on_confirm)
	h.add_child(confirm_btn)

	return pad

# --- Stylebox helpers ------------------------------------------------------

func _make_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COL_PANEL
	s.border_color = COL_PANEL_EDGE
	s.set_border_width_all(2)
	s.set_corner_radius_all(8)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 8
	return s

func _make_inset_style(focused: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.05, 0.07)
	s.border_color = COL_ACCENT if focused else Color(0.20, 0.20, 0.24)
	s.set_border_width_all(2 if focused else 1)
	s.set_corner_radius_all(4)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

func _make_row_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COL_ROW
	s.set_corner_radius_all(6)
	s.border_color = Color(0.06, 0.07, 0.09)
	s.set_border_width_all(1)
	return s

func _make_button_style(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(6)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

# --- Interaction -----------------------------------------------------------

func _cycle_slot(key: String, dir: int) -> void:
	var opts: Array = _slot_options[key]
	var idx: int = (_slot_index[key] + dir + opts.size()) % opts.size()
	_slot_index[key] = idx
	_loadout[key] = opts[idx]
	_slot_value_labels[key].text = "%s  (%d / %d)" % [opts[idx], idx + 1, opts.size()]
	_refresh_preview()

func _refresh_preview() -> void:
	if _preview == null:
		return
	Loadout.apply(_preview, _loadout)

func _on_confirm() -> void:
	_loadout["name"] = _name_edit.text.strip_edges()
	if _loadout["name"] == "":
		_loadout["name"] = "Adventurer"
	Loadout.save(_loadout)
	confirmed.emit(_loadout)
	queue_free()

func _on_cancel() -> void:
	cancelled.emit()
	queue_free()
