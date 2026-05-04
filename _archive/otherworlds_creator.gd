extends CanvasLayer

# Full-screen modal character creator. Aesthetic: dark forge / ritual chamber.
# Black slate ground, ember-gold accents, parchment text, ornate iconographic
# dividers. The character stands on a pillar of light at the center; equipment
# is selected from "stations" on the right.
#
# Opened via main.gd's KEY_C, or automatically on first run when
# user://otherworlds_profile.json is missing.

const MANIFEST_PATH := "res://data/character_kit_manifest.json"
const PROFILE_PATH := "user://otherworlds_profile.json"
const CATALOG_PATH := "res://data/character_pieces_catalog.json"

# Northfolk pieces are merged into the base male/female kits, but they add
# the Accessories slot, so female/male slot lists include it too.
const SLOT_LIST_FEMALE := ["Base", "Head", "Hair", "Top", "Bottom", "Accessories", "Weapons"]
const SLOT_LIST_MALE   := ["Base", "Head", "Hair", "FacialHair", "Top", "Bottom", "Accessories", "Weapons"]
const SLOT_LIST_GOBLIN := ["Base", "Head", "Hair", "FacialHair", "Top", "Bottom", "Weapons"]
# Backer-only kits: characters from PVGames Backer Reward packs converted to
# the OtherWorlds layout. Their pieces only fit Backer bases (different body
# proportions) so they live in their own kit pool.
const SLOT_LIST_BACKER := ["Base", "Head", "Hair", "Top", "Bottom", "Accessories", "Weapons"]

# Ritual sections: each is a "station" with its own altar header.
const STATIONS := [
	{"name": "FLESH",     "icon": "✦",  "slots": ["Base", "Head"]},
	{"name": "MANE",      "icon": "❖",  "slots": ["Hair", "FacialHair"]},
	{"name": "GARMENTS",  "icon": "◈",  "slots": ["Top", "Bottom"]},
	{"name": "ARMS",      "icon": "⚔",  "slots": ["Weapons"]},
]

const DIRS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]

# Palette — committed dark forge.
const C_INK         := Color("#0a0908")
const C_SLATE       := Color("#14110f")
const C_SLATE_HI    := Color("#1c1815")
const C_IRON        := Color("#2a2520")
const C_PARCHMENT   := Color("#e8d6b3")
const C_BONE        := Color("#cdc1a6")
const C_DUST        := Color("#7a7166")
const C_EMBER       := Color("#c08552")    # primary accent
const C_EMBER_HI    := Color("#dba26a")
const C_BLOOD       := Color("#7a2e22")    # secondary accent
const C_GOLD        := Color("#dcb46a")

const ORNAMENT_TOP := "⟡  ⸻  ⸻  ⟡"
const ORNAMENT_BOT := "⟡  ⸺  ⟡  ⸺  ⟡"

var main_ref: Node

var preview_viewport: SubViewport
var preview_world: Node2D
var character: Node2D                    # LayeredOtherworldsCharacter
var slot_rows: Dictionary = {}           # slot -> {label, color_btn}
var anim_label: Label
var dir_label: Label
var status_label: Label
var stations_box: VBoxContainer

var _manifest: Dictionary = {}
var _kit: String = "female"
var _slot_index: Dictionary = {}
var _all_anims: Array[String] = []
var _anim_idx: int = 0
var _dir_idx: int = 2

func _ready() -> void:
	layer = 100
	visible = false
	_load_manifest()
	_load_anim_list()
	_build_ui()

func toggle() -> void:
	visible = not visible
	if visible:
		if character == null:
			_spawn_preview_character(280, 380)
		_apply_initial_selection()
	else:
		# Free the layered-preview's 9 textures when the panel is closed —
		# they're the heaviest VRAM cost in the game when not creating.
		if character and is_instance_valid(character):
			character.queue_free()
		character = null

func _spawn_preview_character(vw: int, vh: int) -> void:
	if preview_world == null:
		return
	var Layered := load("res://layered_otherworlds_character.gd")
	character = Layered.new()
	character.kit = _kit
	character.display_size = 240.0
	preview_world.add_child(character)
	character.position = Vector2(vw * 0.5, vh - 48)
	character.set_direction(_dir_idx)
	if _all_anims.size() > 0:
		character.play_anim(_all_anims[_anim_idx], true)
	character.add_to_group("no_world_shader")
	character.add_to_group("placed_shader_asset")

func _input(event: InputEvent) -> void:
	if not visible or character == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			# Preview the dodge anim (50x50 catalog) or its closest equivalent
			# in the 21x21 catalog (Evade for monster-style kits).
			var anims: Dictionary = character._catalog.get("animations", {})
			for n in ["Evade Roll", "Evade", "Evade Roll Diag", "Crouch"]:
				if anims.has(n):
					character.play_anim(n, false)
					get_viewport().set_input_as_handled()
					return

# ============================== UI BUILD ==============================

func _build_ui() -> void:
	_build_atmosphere()
	_build_header()
	_build_main_grid()
	_build_bottom_bar()

func _build_atmosphere() -> void:
	# Pitch background — opaque inky slab.
	var bg := ColorRect.new()
	bg.color = C_INK
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# Subtle vignette: soft central glow via a radial gradient ColorRect using
	# Godot's GradientTexture2D piped through a TextureRect.
	var grad := GradientTexture2D.new()
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.45)
	grad.fill_to = Vector2(1.0, 1.0)
	grad.width = 256
	grad.height = 256
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(C_EMBER.r, C_EMBER.g, C_EMBER.b, 0.10), Color(0, 0, 0, 0)])
	gr.offsets = PackedFloat32Array([0.0, 1.0])
	grad.gradient = gr
	var tr := TextureRect.new()
	tr.texture = grad
	tr.anchor_right = 1.0
	tr.anchor_bottom = 1.0
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(tr)

	# Top + bottom hairline accents — ember at the top, dim at the bottom.
	var top_rule := ColorRect.new()
	top_rule.color = C_EMBER
	top_rule.anchor_right = 1.0
	top_rule.offset_left = 64
	top_rule.offset_right = -64
	top_rule.offset_top = 4
	top_rule.offset_bottom = 5
	add_child(top_rule)

func _build_header() -> void:
	var ornament_top := Label.new()
	ornament_top.text = ORNAMENT_TOP
	ornament_top.anchor_left = 0.5
	ornament_top.anchor_right = 0.5
	ornament_top.offset_left = -200
	ornament_top.offset_right = 200
	ornament_top.offset_top = 22
	ornament_top.offset_bottom = 42
	ornament_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ornament_top.add_theme_color_override("font_color", C_EMBER)
	ornament_top.add_theme_font_size_override("font_size", 18)
	add_child(ornament_top)

	var title := Label.new()
	title.text = "FORGE  THE  VESSEL"
	title.anchor_left = 0.5
	title.anchor_right = 0.5
	title.offset_left = -300
	title.offset_right = 300
	title.offset_top = 38
	title.offset_bottom = 78
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", C_PARCHMENT)
	title.add_theme_font_size_override("font_size", 32)
	add_child(title)

	var subtitle := Label.new()
	subtitle.text = "—  every choice carved into the bone  —"
	subtitle.anchor_left = 0.5
	subtitle.anchor_right = 0.5
	subtitle.offset_left = -300
	subtitle.offset_right = 300
	subtitle.offset_top = 78
	subtitle.offset_bottom = 94
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", C_DUST)
	subtitle.add_theme_font_size_override("font_size", 12)
	add_child(subtitle)

func _build_main_grid() -> void:
	var grid := HBoxContainer.new()
	grid.anchor_left = 0.0
	grid.anchor_right = 1.0
	grid.anchor_top = 0.0
	grid.anchor_bottom = 1.0
	grid.offset_left = 32
	grid.offset_right = -32
	grid.offset_top = 110
	grid.offset_bottom = -84
	grid.add_theme_constant_override("separation", 20)
	add_child(grid)

	grid.add_child(_build_pedestal())
	grid.add_child(_build_stations_pane())

# Center stage: character standing on a beam of light.
func _build_pedestal() -> Control:
	var slab := PanelContainer.new()
	slab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slab.size_flags_stretch_ratio = 1.4
	slab.add_theme_stylebox_override("panel", _stylebox(C_SLATE, C_EMBER, 1, 0))

	var stack := MarginContainer.new()
	stack.add_theme_constant_override("margin_left", 24)
	stack.add_theme_constant_override("margin_right", 24)
	stack.add_theme_constant_override("margin_top", 24)
	stack.add_theme_constant_override("margin_bottom", 24)
	slab.add_child(stack)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	stack.add_child(inner)

	# Vessel label
	var hdr := Label.new()
	hdr.text = "·  T H E   V E S S E L  ·"
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.add_theme_color_override("font_color", C_DUST)
	hdr.add_theme_font_size_override("font_size", 11)
	inner.add_child(hdr)

	# Light-beam preview.
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(center)

	# Stack: beam (back) + viewport (front)
	var viewport_w := 280
	var viewport_h := 380
	var beam_holder := Control.new()
	beam_holder.custom_minimum_size = Vector2(viewport_w, viewport_h)
	center.add_child(beam_holder)

	# Light beam: a vertical gradient rectangle behind the character.
	var beam := TextureRect.new()
	var beam_grad := GradientTexture2D.new()
	beam_grad.fill = GradientTexture2D.FILL_LINEAR
	beam_grad.fill_from = Vector2(0.5, 0.0)
	beam_grad.fill_to = Vector2(0.5, 1.0)
	beam_grad.width = 4
	beam_grad.height = 256
	var bg2 := Gradient.new()
	bg2.colors = PackedColorArray([
		Color(0, 0, 0, 0),
		Color(C_EMBER.r, C_EMBER.g, C_EMBER.b, 0.18),
		Color(C_EMBER.r, C_EMBER.g, C_EMBER.b, 0.06),
		Color(0, 0, 0, 0)])
	bg2.offsets = PackedFloat32Array([0.0, 0.35, 0.85, 1.0])
	beam_grad.gradient = bg2
	beam.texture = beam_grad
	beam.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	beam.stretch_mode = TextureRect.STRETCH_SCALE
	beam.anchor_left = 0.5
	beam.anchor_right = 0.5
	beam.offset_left = -90
	beam.offset_right = 90
	beam.anchor_top = 0.0
	beam.anchor_bottom = 1.0
	beam_holder.add_child(beam)

	# Viewport with character.
	var svc := SubViewportContainer.new()
	svc.stretch = false
	svc.custom_minimum_size = Vector2(viewport_w, viewport_h)
	svc.anchor_left = 0
	svc.anchor_right = 1
	svc.anchor_top = 0
	svc.anchor_bottom = 1
	beam_holder.add_child(svc)

	preview_viewport = SubViewport.new()
	preview_viewport.size = Vector2i(viewport_w, viewport_h)
	preview_viewport.disable_3d = true
	preview_viewport.transparent_bg = true
	preview_viewport.handle_input_locally = false
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(preview_viewport)

	preview_world = Node2D.new()
	preview_viewport.add_child(preview_world)

	# Pedestal disc under the feet.
	var disc := _draw_pedestal_disc()
	disc.position = Vector2(viewport_w * 0.5, viewport_h - 44)
	preview_world.add_child(disc)

	_spawn_preview_character(viewport_w, viewport_h)

	# Foot caption
	var foot := Label.new()
	foot.text = "·  awaken  ·"
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_theme_color_override("font_color", C_DUST)
	foot.add_theme_font_size_override("font_size", 10)
	inner.add_child(foot)

	return slab

# Right pane: tabs/stations with slot rows.
func _build_stations_pane() -> Control:
	var slab := PanelContainer.new()
	slab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slab.size_flags_stretch_ratio = 1.0
	slab.custom_minimum_size = Vector2(340, 0)
	slab.add_theme_stylebox_override("panel", _stylebox(C_SLATE, C_IRON, 1, 0))

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 22)
	pad.add_theme_constant_override("margin_right", 22)
	pad.add_theme_constant_override("margin_top", 18)
	pad.add_theme_constant_override("margin_bottom", 18)
	slab.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	pad.add_child(col)

	# Kit ribbon.
	var ribbon := HBoxContainer.new()
	ribbon.add_theme_constant_override("separation", 0)
	col.add_child(ribbon)
	var ribbon_group := ButtonGroup.new()
	for entry in [["FEMALE", "female"], ["MALE", "male"], ["GOBLIN", "goblin"],
		["BACKER♀", "backer_female"], ["BACKER♂", "backer_male"]]:
		var tab := Button.new()
		tab.text = String(entry[0])
		tab.toggle_mode = true
		tab.button_group = ribbon_group
		tab.button_pressed = (entry[1] == _kit)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size = Vector2(0, 38)
		tab.add_theme_color_override("font_color", C_BONE)
		tab.add_theme_color_override("font_pressed_color", C_GOLD)
		tab.add_theme_color_override("font_hover_color", C_PARCHMENT)
		tab.add_theme_font_size_override("font_size", 13)
		var sb_normal := _stylebox(C_SLATE_HI, C_IRON, 1, 0)
		var sb_pressed := _stylebox(C_IRON, C_EMBER, 1, 0)
		var sb_hover := _stylebox(C_SLATE_HI, C_EMBER, 1, 0)
		tab.add_theme_stylebox_override("normal", sb_normal)
		tab.add_theme_stylebox_override("pressed", sb_pressed)
		tab.add_theme_stylebox_override("hover", sb_hover)
		tab.add_theme_stylebox_override("focus", sb_pressed)
		tab.pressed.connect(func(): _set_kit(String(entry[1])))
		ribbon.add_child(tab)

	# Stations scroll.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	stations_box = VBoxContainer.new()
	stations_box.add_theme_constant_override("separation", 16)
	stations_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(stations_box)

	_rebuild_stations()
	return slab

func _rebuild_stations() -> void:
	for c in stations_box.get_children():
		c.queue_free()
	slot_rows.clear()
	var available_slots := _slots_for_kit()
	for st in STATIONS:
		# Header for this station.
		var anchor := VBoxContainer.new()
		anchor.add_theme_constant_override("separation", 4)
		stations_box.add_child(anchor)
		var hdr_row := HBoxContainer.new()
		hdr_row.add_theme_constant_override("separation", 8)
		anchor.add_child(hdr_row)
		var icon := Label.new()
		icon.text = String(st.icon)
		icon.add_theme_color_override("font_color", C_EMBER)
		icon.add_theme_font_size_override("font_size", 18)
		hdr_row.add_child(icon)
		var hdr := Label.new()
		hdr.text = String(st.name)
		hdr.add_theme_color_override("font_color", C_PARCHMENT)
		hdr.add_theme_font_size_override("font_size", 14)
		hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hdr_row.add_child(hdr)
		var rule := ColorRect.new()
		rule.color = C_IRON
		rule.custom_minimum_size = Vector2(0, 1)
		anchor.add_child(rule)

		# Slot rows for this station.
		for slot in st.slots:
			if not (slot in available_slots):
				continue
			anchor.add_child(_build_slot_card(slot))

# Slot card: tight row with label + < name > + ember swatch.
func _build_slot_card(slot: String) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _stylebox(C_SLATE_HI, C_IRON, 1, 0))
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	card.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	pad.add_child(row)

	var slot_lbl := Label.new()
	slot_lbl.text = slot.to_upper()
	slot_lbl.custom_minimum_size = Vector2(80, 0)
	slot_lbl.add_theme_color_override("font_color", C_DUST)
	slot_lbl.add_theme_font_size_override("font_size", 11)
	row.add_child(slot_lbl)

	var prev := _make_chevron("‹", func(): _cycle_slot(slot, -1))
	row.add_child(prev)

	var name_lbl := Label.new()
	name_lbl.text = _label_for(slot, int(_slot_index.get(slot, 0)))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", C_PARCHMENT)
	name_lbl.add_theme_font_size_override("font_size", 13)
	row.add_child(name_lbl)

	var nxt := _make_chevron("›", func(): _cycle_slot(slot, 1))
	row.add_child(nxt)

	var color_btn := ColorPickerButton.new()
	color_btn.color = Color.WHITE
	color_btn.custom_minimum_size = Vector2(28, 28)
	color_btn.add_theme_stylebox_override("normal", _stylebox(C_BONE, C_EMBER, 1, 0))
	color_btn.color_changed.connect(func(c: Color): _on_color_changed(slot, c))
	row.add_child(color_btn)

	slot_rows[slot] = {"label": name_lbl, "color_btn": color_btn}
	return card

func _make_chevron(glyph: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = glyph
	b.flat = false
	b.custom_minimum_size = Vector2(28, 28)
	b.add_theme_color_override("font_color", C_EMBER)
	b.add_theme_color_override("font_hover_color", C_GOLD)
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_stylebox_override("normal", _stylebox(C_INK, C_IRON, 1, 0))
	b.add_theme_stylebox_override("hover", _stylebox(C_SLATE, C_EMBER, 1, 0))
	b.add_theme_stylebox_override("pressed", _stylebox(C_IRON, C_EMBER, 1, 0))
	b.pressed.connect(on_pressed)
	return b

func _build_bottom_bar() -> void:
	var bar := PanelContainer.new()
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = 32
	bar.offset_right = -32
	bar.offset_top = -70
	bar.offset_bottom = -16
	bar.add_theme_stylebox_override("panel", _stylebox(C_SLATE, C_EMBER, 1, 0))
	add_child(bar)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 18)
	pad.add_theme_constant_override("margin_right", 18)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 12)
	bar.add_child(pad)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 22)
	pad.add_child(hb)

	hb.add_child(_inline_cycler("ANIMATION", func(): _cycle_anim(-1), func(): _cycle_anim(1), 150, "anim"))
	hb.add_child(_inline_cycler("FACING",    func(): _cycle_dir(-1),  func(): _cycle_dir(1),  56,  "dir"))
	hb.add_child(_inline_slider("PIXELATE",    1.0, 16.0, 0.1, 1.3, func(v: float):
		if character: character.set_shader_pixel_size(v)))
	hb.add_child(_inline_slider("PALETTE", 0.0, 1.0, 0.01, 0.0, func(v: float):
		if character: character.set_shader_palette_mix(v)))

	# Status (right-aligned forge log).
	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.text = "·  the anvil waits  ·"
	status_label.add_theme_color_override("font_color", C_DUST)
	status_label.add_theme_font_size_override("font_size", 11)
	hb.add_child(status_label)

	hb.add_child(_iron_button("ABANDON", false, func(): visible = false))
	hb.add_child(_iron_button("FORGE", true, _save_profile_and_reload_player))

func _inline_cycler(label: String, on_prev: Callable, on_next: Callable, value_w: int, kind: String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_color_override("font_color", C_DUST)
	lbl.add_theme_font_size_override("font_size", 10)
	col.add_child(lbl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	col.add_child(row)
	row.add_child(_make_chevron("‹", on_prev))
	var vlbl := Label.new()
	vlbl.custom_minimum_size = Vector2(value_w, 28)
	vlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vlbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vlbl.add_theme_color_override("font_color", C_PARCHMENT)
	vlbl.add_theme_font_size_override("font_size", 12)
	row.add_child(vlbl)
	row.add_child(_make_chevron("›", on_next))
	if kind == "anim":
		anim_label = vlbl
		vlbl.text = _all_anims[_anim_idx] if _all_anims.size() > 0 else "—"
	elif kind == "dir":
		dir_label = vlbl
		vlbl.text = DIRS[_dir_idx]
	return col

func _inline_slider(label: String, lo: float, hi: float, step: float, default: float, on_change: Callable) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	col.add_child(top)
	var lbl := Label.new()
	lbl.text = label
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", C_DUST)
	lbl.add_theme_font_size_override("font_size", 10)
	top.add_child(lbl)
	var vlbl := Label.new()
	vlbl.text = "%.2f" % default
	vlbl.add_theme_color_override("font_color", C_EMBER)
	vlbl.add_theme_font_size_override("font_size", 11)
	top.add_child(vlbl)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = default
	s.custom_minimum_size = Vector2(150, 0)
	s.value_changed.connect(func(v: float):
		vlbl.text = "%.2f" % v
		on_change.call(v))
	col.add_child(s)
	return col

func _iron_button(text: String, primary: bool, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(120 if primary else 100, 38)
	b.add_theme_font_size_override("font_size", 13)
	if primary:
		b.add_theme_color_override("font_color", C_INK)
		b.add_theme_color_override("font_hover_color", C_INK)
		b.add_theme_color_override("font_pressed_color", C_INK)
		b.add_theme_stylebox_override("normal", _stylebox(C_EMBER, C_GOLD, 2, 0))
		b.add_theme_stylebox_override("hover",  _stylebox(C_EMBER_HI, C_GOLD, 2, 0))
		b.add_theme_stylebox_override("pressed",_stylebox(C_GOLD, C_EMBER, 2, 0))
	else:
		b.add_theme_color_override("font_color", C_BONE)
		b.add_theme_color_override("font_hover_color", C_PARCHMENT)
		b.add_theme_stylebox_override("normal", _stylebox(C_INK, C_IRON, 1, 0))
		b.add_theme_stylebox_override("hover",  _stylebox(C_SLATE_HI, C_DUST, 1, 0))
		b.add_theme_stylebox_override("pressed",_stylebox(C_IRON, C_BONE, 1, 0))
	b.pressed.connect(on_pressed)
	return b

func _stylebox(bg: Color, border: Color, border_w: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	return sb

func _draw_pedestal_disc() -> Node2D:
	# Manually drawn ellipse shadow + thin highlight ring; sits behind the feet.
	var node := Node2D.new()
	node.set_script(GDScript.new())
	# Use a custom drawer node (Polygon2D) so we don't need scripts here.
	var shadow := Polygon2D.new()
	var pts := PackedVector2Array()
	var n_pts := 32
	for i in range(n_pts):
		var ang := TAU * float(i) / float(n_pts)
		pts.append(Vector2(cos(ang) * 110.0, sin(ang) * 22.0))
	shadow.polygon = pts
	shadow.color = Color(0, 0, 0, 0.55)
	node.add_child(shadow)
	var ring := Line2D.new()
	var rpts := PackedVector2Array()
	for i in range(n_pts + 1):
		var ang := TAU * float(i) / float(n_pts)
		rpts.append(Vector2(cos(ang) * 100.0, sin(ang) * 20.0))
	ring.points = rpts
	ring.width = 1.5
	ring.default_color = Color(C_EMBER.r, C_EMBER.g, C_EMBER.b, 0.55)
	node.add_child(ring)
	return node

# ============================== DATA ==============================

func _load_manifest() -> void:
	var f := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if f == null:
		return
	_manifest = JSON.parse_string(f.get_as_text())

func _load_anim_list() -> void:
	_reload_anim_list_for_kit()

func _reload_anim_list_for_kit() -> void:
	_all_anims.clear()
	var path := CATALOG_PATH
	if _kit == "goblin":
		path = "res://data/monster_anim_catalog.json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	var keys := (d.get("animations", {}) as Dictionary).keys()
	keys.sort()
	for k in keys:
		_all_anims.append(String(k))
	# Default to whatever idle this catalog ships.
	_anim_idx = 0
	for i in range(_all_anims.size()):
		var n: String = _all_anims[i]
		if n == "Idle 1" or n == "Idle" or n == "idle":
			_anim_idx = i
			break
	if anim_label and _all_anims.size() > 0:
		anim_label.text = _all_anims[_anim_idx]
	if character and _all_anims.size() > 0:
		character.play_anim(_all_anims[_anim_idx], true)

func _slots_for_kit() -> Array:
	match _kit:
		"male":          return SLOT_LIST_MALE
		"goblin":        return SLOT_LIST_GOBLIN
		"backer_female": return SLOT_LIST_BACKER
		"backer_male":   return SLOT_LIST_BACKER
		_:               return SLOT_LIST_FEMALE

func _variants_for(slot: String) -> Array:
	var entries: Array = _manifest.get(_kit, {}).get(slot, [])
	var out: Array = [""]
	for e in entries:
		out.append(String(e.get("name", "")))
	return out

func _label_for(slot: String, idx: int) -> String:
	var v := _variants_for(slot)
	if idx < 0 or idx >= v.size():
		return "—"
	var s: String = v[idx]
	return "(none)" if s == "" else s

# ============================== HANDLERS ==============================

func _cycle_slot(slot: String, step: int) -> void:
	var variants := _variants_for(slot)
	if variants.is_empty():
		return
	var i: int = (int(_slot_index.get(slot, 0)) + step + variants.size()) % variants.size()
	_slot_index[slot] = i
	if slot_rows.has(slot):
		slot_rows[slot].label.text = _label_for(slot, i)
	if character:
		character.set_slot(slot, variants[i])
	status_label.text = "·  %s shifted  ·" % slot.to_lower()

func _on_color_changed(slot: String, c: Color) -> void:
	if character:
		character.set_slot_color(slot, c)
	status_label.text = "·  %s tinted  ·" % slot.to_lower()

func _set_kit(k: String) -> void:
	if k == _kit:
		return
	_kit = k
	_slot_index.clear()
	if character:
		character.kit = _kit
		# Goblin uses a different catalog (21x21 monster format) — reload it.
		if character.has_method("reload_catalog"):
			character.reload_catalog()
		for slot in character._layers.keys():
			character.set_slot(slot, "")
	_reload_anim_list_for_kit()
	_rebuild_stations()
	_apply_initial_selection()
	# Diagnostic log so we can tell why goblin/etc. doesn't visually appear.
	print("[creator] kit=%s  slots:" % _kit)
	for slot in _slots_for_kit():
		var v: Array = _variants_for(slot)
		var idx: int = int(_slot_index.get(slot, 0))
		var pick: String = v[idx] if idx < v.size() else "?"
		print("  ", slot, " pick=", pick, "  variants=", v.size())
	status_label.text = "·  flesh re-cast  ·"

func _cycle_anim(step: int) -> void:
	if _all_anims.is_empty():
		return
	_anim_idx = (_anim_idx + step + _all_anims.size()) % _all_anims.size()
	anim_label.text = _all_anims[_anim_idx]
	if character:
		character.play_anim(_all_anims[_anim_idx], true)

func _cycle_dir(step: int) -> void:
	_dir_idx = (_dir_idx + step + DIRS.size()) % DIRS.size()
	dir_label.text = DIRS[_dir_idx]
	if character:
		character.set_direction(_dir_idx)

func _apply_initial_selection() -> void:
	if character == null:
		return
	for slot in _slots_for_kit():
		var variants := _variants_for(slot)
		var idx: int = int(_slot_index.get(slot, 0))
		if idx >= variants.size():
			idx = 0
		if variants.size() > 1 and idx == 0 and slot in ["Base", "Head", "Hair", "Top", "Bottom"]:
			idx = 1
			_slot_index[slot] = 1
			if slot_rows.has(slot):
				slot_rows[slot].label.text = _label_for(slot, 1)
		character.set_slot(slot, variants[idx])
	character.set_slot("Shadow", "")

func _save_profile_and_reload_player() -> void:
	var slots: Dictionary = {}
	for slot in _slots_for_kit():
		var variants := _variants_for(slot)
		var i: int = int(_slot_index.get(slot, 0))
		slots[slot] = String(variants[i]) if i < variants.size() else ""
	var colors: Dictionary = {}
	if character:
		for slot in character._layer_colors.keys():
			colors[slot] = (character._layer_colors[slot] as Color).to_html()
	var profile := {
		"kit": _kit,
		"slots": slots,
		"colors": colors,
		"pixel_size": character._shader_pixel_size if character else 1.3,
		"palette_mix": character._shader_palette_mix if character else 0.0,
	}
	var f := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(profile, "  "))
		f.close()
	if main_ref and main_ref.player and main_ref.player.has_method("reload_profile"):
		main_ref.player.reload_profile()
	status_label.text = "·  forged. the world remembers.  ·"
	visible = false
