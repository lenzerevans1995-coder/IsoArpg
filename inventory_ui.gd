extends Control
class_name InventoryUI

# "Foundry" inventory panel — paper-doll + tabbed backpack grid.
# Style mirrors the skill editor and the HUD bar so the UI reads as a
# single family of surfaces. Renders on a CanvasLayer at native res so
# its icons stay crisp (LINEAR filter) while the world below stays
# pixel-art.

const Inventory := preload("res://inventory.gd")

signal closed()

# --- Foundry tokens -----------------------------------------------------
const COL_BG          := Color("#0E1116")
const COL_PANEL       := Color("#161A21")
const COL_RAISED      := Color("#1F252E")
const COL_RAISED_HOV  := Color("#262E3A")
const COL_RULE        := Color("#2A3340")
const COL_TEXT        := Color("#E8E2D2")
const COL_TEXT_DIM    := Color("#8B8676")
const COL_TEXT_FAINT  := Color("#5A5448")
const COL_AMBER       := Color("#D9A85A")
const COL_AMBER_DIM   := Color("#7C5F33")
const COL_VELLUM      := Color("#0A0D12")

const TABS := ["Weapons", "Armor", "Consumables", "Misc"]
const PAPERDOLL_SLOTS := [
	["",         ""],         ["HEAD",     "head"],     ["",         ""],
	["NECK",     "neck"],     ["CHEST",    "chest"],    ["HANDS",    "hands"],
	["MAINHAND", "mainhand"], ["BELT",     "belt"],     ["OFFHAND",  "offhand"],
	["",         ""],         ["LEGS",     "legs"],     ["RING",     "ring"],
	["",         ""],         ["SHOES",    "shoes"],    ["",         ""],
]

var _loadout: Dictionary = {}
var _active_tab: int = 0
var _gold_label: Label
var _bag_grid: GridContainer
var _doll_slots: Dictionary = {}
var _selected_id: String = ""

func open_with(loadout: Dictionary) -> void:
	_loadout = loadout
	if is_inside_tree():
		_refresh_all()

func _ready() -> void:
	anchor_right = 1.0; anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_panel()
	_refresh_all()

func _build_panel() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.anchor_right = 1.0; dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.anchor_right = 1.0; center.anchor_bottom = 1.0
	add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.custom_minimum_size = Vector2(760, 560)
	center.add_child(panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 24)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_theme_constant_override("margin_top", 18)
	pad.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(pad)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	pad.add_child(page)

	page.add_child(_build_header())

	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 14)
	page.add_child(split)

	var doll := _build_paperdoll()
	doll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	doll.size_flags_stretch_ratio = 0.85
	split.add_child(doll)

	var bag := _build_backpack()
	bag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag.size_flags_stretch_ratio = 1.15
	split.add_child(bag)

# --- Styles ---------------------------------------------------------------

func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = COL_RULE
	sb.border_width_left = 1; sb.border_width_top = 1
	sb.border_width_right = 1; sb.border_width_bottom = 1
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 0
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 6)
	return sb

func _vellum_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = COL_RULE
	sb.border_width_left = 1; sb.border_width_top = 1
	sb.border_width_right = 1; sb.border_width_bottom = 1
	sb.corner_radius_top_left = 0; sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4; sb.corner_radius_bottom_right = 0
	sb.content_margin_left = 16; sb.content_margin_right = 16
	sb.content_margin_top = 14; sb.content_margin_bottom = 14
	return sb

func _slot_style_empty() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_RAISED
	sb.border_color = COL_RULE
	sb.border_width_left = 1; sb.border_width_top = 1
	sb.border_width_right = 1; sb.border_width_bottom = 1
	sb.corner_radius_top_left = 0; sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4; sb.corner_radius_bottom_right = 0
	return sb

func _slot_style_filled() -> StyleBoxFlat:
	var sb := _slot_style_empty()
	sb.bg_color = COL_PANEL
	sb.border_color = COL_AMBER_DIM
	return sb

func _slot_style_hover() -> StyleBoxFlat:
	var sb := _slot_style_filled()
	sb.bg_color = COL_RAISED_HOV
	sb.border_color = COL_AMBER
	sb.border_width_left = 2; sb.border_width_top = 2
	sb.border_width_right = 2; sb.border_width_bottom = 2
	return sb

# --- Header ---------------------------------------------------------------

func _build_header() -> Control:
	var hdr := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = COL_RULE
	sb.border_width_bottom = 1
	sb.content_margin_left = 14; sb.content_margin_right = 14
	sb.content_margin_top = 10; sb.content_margin_bottom = 10
	hdr.add_theme_stylebox_override("panel", sb)
	hdr.custom_minimum_size = Vector2(0, 56)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	hdr.add_child(hb)

	var mark := Label.new(); mark.text = "✦"
	mark.add_theme_color_override("font_color", COL_AMBER)
	mark.add_theme_font_size_override("font_size", 20)
	hb.add_child(mark)

	var title := Label.new(); title.text = "EQUIPMENT"
	title.add_theme_color_override("font_color", COL_TEXT)
	title.add_theme_font_size_override("font_size", 18)
	hb.add_child(title)

	var tabs := TabBar.new()
	for t in TABS: tabs.add_tab(t)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_tabbar(tabs)
	tabs.tab_changed.connect(_on_tab_changed)
	hb.add_child(tabs)

	_gold_label = Label.new(); _gold_label.text = "0g"
	_gold_label.add_theme_color_override("font_color", COL_AMBER)
	_gold_label.add_theme_font_size_override("font_size", 13)
	_gold_label.custom_minimum_size = Vector2(60, 0)
	hb.add_child(_gold_label)

	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.add_theme_color_override("font_color", COL_TEXT_DIM)
	close.add_theme_color_override("font_hover_color", COL_AMBER)
	close.add_theme_font_size_override("font_size", 18)
	close.custom_minimum_size = Vector2(28, 28)
	close.pressed.connect(_on_close)
	hb.add_child(close)
	return hdr

func _style_tabbar(tb: TabBar) -> void:
	var unsel := StyleBoxFlat.new()
	unsel.bg_color = COL_RAISED
	unsel.border_color = COL_RULE
	unsel.border_width_bottom = 1
	unsel.content_margin_left = 14; unsel.content_margin_right = 14
	unsel.content_margin_top = 6; unsel.content_margin_bottom = 6
	tb.add_theme_stylebox_override("tab_unselected", unsel)
	var hov := unsel.duplicate() as StyleBoxFlat
	hov.bg_color = COL_RAISED_HOV
	tb.add_theme_stylebox_override("tab_hovered", hov)
	var sel := StyleBoxFlat.new()
	sel.bg_color = COL_PANEL
	sel.border_color = COL_AMBER
	sel.border_width_bottom = 2
	sel.content_margin_left = 14; sel.content_margin_right = 14
	sel.content_margin_top = 6; sel.content_margin_bottom = 6
	tb.add_theme_stylebox_override("tab_selected", sel)
	tb.add_theme_color_override("font_unselected_color", COL_TEXT_DIM)
	tb.add_theme_color_override("font_hovered_color", COL_TEXT)
	tb.add_theme_color_override("font_selected_color", COL_AMBER)
	tb.add_theme_font_size_override("font_size", 12)

# --- Paper-doll -----------------------------------------------------------

func _build_paperdoll() -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _vellum_style())
	card.custom_minimum_size = Vector2(300, 0)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	v.add_child(_section_header("01", "PAPER DOLL"))

	var pane := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = COL_BG
	ps.border_color = COL_RULE
	ps.border_width_left = 1; ps.border_width_top = 1
	ps.border_width_right = 1; ps.border_width_bottom = 1
	ps.corner_radius_top_left = 0; ps.corner_radius_top_right = 4
	ps.corner_radius_bottom_left = 4; ps.corner_radius_bottom_right = 0
	pane.add_theme_stylebox_override("panel", ps)
	pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(pane)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	pane.add_child(grid)

	for entry in PAPERDOLL_SLOTS:
		var label_text: String = entry[0]
		var slot_id: String = entry[1]
		if slot_id == "":
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(50, 64)
			grid.add_child(spacer)
		else:
			grid.add_child(_make_paperdoll_slot(label_text, slot_id))
	return card

func _make_paperdoll_slot(label_text: String, slot_id: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var btn := Button.new()
	btn.flat = true
	btn.custom_minimum_size = Vector2(48, 48)
	btn.add_theme_stylebox_override("normal", _slot_style_empty())
	btn.add_theme_stylebox_override("hover", _slot_style_hover())
	btn.add_theme_stylebox_override("pressed", _slot_style_hover())
	btn.set_meta("slot_id", slot_id)
	btn.pressed.connect(_on_doll_slot_pressed.bind(slot_id))
	v.add_child(btn)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_color_override("font_color", COL_TEXT_FAINT)
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(lbl)
	_doll_slots[slot_id] = btn
	return v

# --- Backpack -------------------------------------------------------------

func _build_backpack() -> Control:
	var card := PanelContainer.new()
	var sb := _panel_style()
	sb.shadow_size = 0
	sb.content_margin_left = 14; sb.content_margin_right = 14
	sb.content_margin_top = 14; sb.content_margin_bottom = 14
	card.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	v.add_child(_section_header("02", "BACKPACK"))

	_bag_grid = GridContainer.new()
	_bag_grid.columns = 8
	_bag_grid.add_theme_constant_override("h_separation", 6)
	_bag_grid.add_theme_constant_override("v_separation", 6)
	v.add_child(_bag_grid)
	return card

func _section_header(num: String, title: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var n := Label.new(); n.text = "%s  —" % num
	n.add_theme_color_override("font_color", COL_AMBER)
	n.add_theme_font_size_override("font_size", 11)
	hb.add_child(n)
	var t := Label.new(); t.text = title.to_upper()
	t.add_theme_color_override("font_color", COL_TEXT)
	t.add_theme_font_size_override("font_size", 13)
	hb.add_child(t)
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
	return hb

# --- Refresh / data ------------------------------------------------------

func _refresh_all() -> void:
	if _gold_label == null:
		return
	_gold_label.text = "%dg" % Inventory.get_gold(_loadout)
	_refresh_paperdoll()
	_refresh_backpack()

func _refresh_paperdoll() -> void:
	for slot_id in _doll_slots.keys():
		var btn: Button = _doll_slots[slot_id]
		var folder: String = String(_loadout.get(slot_id, ""))
		for c in btn.get_children():
			c.queue_free()
		if folder == "":
			btn.add_theme_stylebox_override("normal", _slot_style_empty())
		else:
			btn.add_theme_stylebox_override("normal", _slot_style_filled())
			var icon := _make_item_icon(_item_id_for_folder(slot_id, folder))
			if icon:
				icon.anchor_right = 1.0; icon.anchor_bottom = 1.0
				icon.offset_left = 4; icon.offset_top = 4
				icon.offset_right = -4; icon.offset_bottom = -4
				btn.add_child(icon)

func _refresh_backpack() -> void:
	if _bag_grid == null:
		return
	for c in _bag_grid.get_children():
		c.queue_free()
	var items: Array = Inventory.get_items(_loadout)
	var filtered: Array = []
	for iid in items:
		if _matches_tab(String(iid), _active_tab):
			filtered.append(iid)
	var idx: int = 0
	for iid in filtered:
		_bag_grid.add_child(_make_backpack_cell(String(iid)))
		idx += 1
	for i in range(idx, 48):
		_bag_grid.add_child(_make_backpack_cell(""))

func _make_backpack_cell(item_id: String) -> Control:
	var btn := Button.new()
	btn.flat = true
	btn.custom_minimum_size = Vector2(48, 48)
	btn.add_theme_stylebox_override("hover", _slot_style_hover())
	btn.add_theme_stylebox_override("pressed", _slot_style_hover())
	if item_id == "":
		btn.add_theme_stylebox_override("normal", _slot_style_empty())
	else:
		btn.add_theme_stylebox_override("normal", _slot_style_filled())
		var icon := _make_item_icon(item_id)
		if icon:
			icon.anchor_right = 1.0; icon.anchor_bottom = 1.0
			icon.offset_left = 4; icon.offset_top = 4
			icon.offset_right = -4; icon.offset_bottom = -4
			btn.add_child(icon)
		btn.set_meta("item_id", item_id)
		btn.pressed.connect(_on_bag_slot_pressed.bind(item_id))
	return btn

func _make_item_icon(item_id: String) -> TextureRect:
	if item_id == "":
		return null
	var paths := [
		"res://assets/generated/icons/%s.png" % item_id,
		"res://assets/generated/ground/%s.png" % item_id,
	]
	for p in paths:
		if ResourceLoader.exists(p):
			var t: Texture2D = load(p)
			if t != null:
				var r := TextureRect.new()
				r.texture = t
				r.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
				r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				# HD item icons — explicit LINEAR override so they
				# bypass the project's NEAREST default and render crisp.
				r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
				r.mouse_filter = Control.MOUSE_FILTER_IGNORE
				return r
	return null

func _item_id_for_folder(slot_id: String, folder: String) -> String:
	for e in ItemsDB.build_catalog():
		if String(e.get("folder", "")) == folder:
			return String(e.get("id", ""))
	return ""

func _matches_tab(item_id: String, tab: int) -> bool:
	var entry: Dictionary = {}
	for e in ItemsDB.build_catalog():
		if String(e.get("id", "")) == item_id:
			entry = e
			break
	if entry.is_empty():
		return tab == 3
	var slot: int = int(entry.get("slot", -1))
	match tab:
		0: return slot in [ItemsDB.Slot.MAINHAND, ItemsDB.Slot.OFFHAND, ItemsDB.Slot.SHIELD]
		1: return slot in [ItemsDB.Slot.HEAD, ItemsDB.Slot.CHEST, ItemsDB.Slot.LEGS,
				ItemsDB.Slot.SHOES, ItemsDB.Slot.HANDS, ItemsDB.Slot.BELT, ItemsDB.Slot.BAG]
		2: return false
		3: return slot in [ItemsDB.Slot.MOUNT]
	return false

# --- Signals --------------------------------------------------------------

func _on_tab_changed(idx: int) -> void:
	_active_tab = idx
	_refresh_backpack()

func _on_close() -> void:
	closed.emit()
	queue_free()

func _on_doll_slot_pressed(slot_id: String) -> void:
	var folder: String = String(_loadout.get(slot_id, ""))
	if folder == "":
		return
	var iid: String = _item_id_for_folder(slot_id, folder)
	if iid == "":
		return
	_loadout[slot_id] = ""
	Inventory.add_item(_loadout, iid)
	_save_and_refresh()

func _on_bag_slot_pressed(item_id: String) -> void:
	if not _can_player_use(item_id):
		return
	if Inventory.equip(_loadout, item_id):
		_save_and_refresh()

func _can_player_use(item_id: String) -> bool:
	var entry: Dictionary = {}
	for e in ItemsDB.build_catalog():
		if String(e.get("id", "")) == item_id:
			entry = e; break
	if entry.is_empty():
		return false
	var slot: int = int(entry.get("slot", -1))
	if slot != ItemsDB.Slot.MAINHAND:
		return true
	var folder: String = String(entry.get("folder", ""))
	var cls: String = String(_loadout.get("class", "warrior"))
	if cls == "warrior":
		return ItemsDB.is_warrior_weapon(folder)
	return true

func _save_and_refresh() -> void:
	var L := preload("res://loadout.gd")
	L.save(_loadout)
	var main := get_tree().root.get_node_or_null("Main")
	if main and main.player and main.player.has_method("reload_loadout"):
		main.player.reload_loadout()
	_refresh_all()
