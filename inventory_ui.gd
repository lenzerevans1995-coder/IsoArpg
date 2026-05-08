extends Control
class_name InventoryUI

# Inventory panel — drawn in the same stone / bronze / gold pixel-art
# style as HUDSkillSquare and HUDStoneButton (the existing UI bar).
# Custom Control._draw() per frame instead of StyleBoxFlat so the
# chunky D2-style frame, gold pinstripe, and corner studs match the
# rest of the HUD exactly.

const Inventory := preload("res://inventory.gd")

signal closed()

# Stone / bronze / gold palette (matches hud_skill_square + hud_stone_button).
const COL_STONE_DARK  := Color(0.10, 0.11, 0.12)
const COL_BRONZE_DARK := Color(0.18, 0.20, 0.22)
const COL_BRONZE_MID  := Color(0.32, 0.34, 0.36)
const COL_GOLD        := Color(0.55, 0.55, 0.52)
const COL_GOLD_HI     := Color(0.78, 0.76, 0.70)
const COL_VOID        := Color(0.05, 0.06, 0.07)
const COL_VOID_HOT    := Color(0.10, 0.11, 0.13)
const COL_TEXT        := Color(0.92, 0.90, 0.85)
const COL_TEXT_DIM    := Color(0.65, 0.62, 0.55)
const COL_TEXT_FAINT  := Color(0.42, 0.40, 0.35)

const TABS := ["Weapons", "Armor", "Consumables", "Misc"]
# 3-column layout. Empty slot_id = spacer.
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
var _doll_slots: Dictionary = {}    # slot_id -> _StoneSlot

func open_with(loadout: Dictionary) -> void:
	_loadout = loadout
	if is_inside_tree():
		_refresh_all()

func _ready() -> void:
	anchor_right = 1.0; anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_panel()
	_refresh_all()

# --- Stone-frame Control. Draws the same chunky D2 frame as
#     HUDSkillSquare so panels match the UI bar exactly. ----------------
class _StoneFrame extends Control:
	const PAD := 6   # how far inside the frame content starts
	const COL_STONE_DARK  := Color(0.10, 0.11, 0.12)
	const COL_BRONZE_DARK := Color(0.18, 0.20, 0.22)
	const COL_BRONZE_MID  := Color(0.32, 0.34, 0.36)
	const COL_GOLD        := Color(0.55, 0.55, 0.52)
	const COL_VOID        := Color(0.05, 0.06, 0.07)
	@export var hot: bool = false
	func _draw() -> void:
		var w: int = int(size.x)
		var h: int = int(size.y)
		# Drop shadow.
		draw_rect(Rect2(2, 4, w, h), Color(0, 0, 0, 0.55), true)
		# Outer dark stone.
		draw_rect(Rect2(0, 0, w, h), COL_STONE_DARK, true)
		# Bronze rim (3 px chunky).
		draw_rect(Rect2(2, 2, w - 4, h - 4), COL_BRONZE_DARK, true)
		draw_rect(Rect2(3, 3, w - 6, h - 6), COL_BRONZE_MID, true)
		# Gold pinstripe.
		draw_rect(Rect2(4, 4, w - 8, h - 8), COL_GOLD, true)
		# Inner stone ledge.
		draw_rect(Rect2(5, 5, w - 10, h - 10), COL_STONE_DARK, true)
		# Cavity.
		draw_rect(Rect2(6, 6, w - 12, h - 12), COL_VOID, true)
		# Top sheen.
		draw_rect(Rect2(6, 6, w - 12, max(2, (h - 12) / 8)), Color(1, 1, 1, 0.05), true)
		# Bottom shadow.
		draw_rect(Rect2(6, h - 8, w - 12, 2), Color(0, 0, 0, 0.4), true)
		# Gold corner studs (4 small triangles).
		_corner_tri(4, 4, 4, 0)
		_corner_tri(w - 4, 4, 4, 1)
		_corner_tri(4, h - 4, 4, 2)
		_corner_tri(w - 4, h - 4, 4, 3)
	func _corner_tri(x: int, y: int, ts: int, corner: int) -> void:
		var pts := PackedVector2Array()
		match corner:
			0: pts = PackedVector2Array([Vector2(x, y), Vector2(x + ts, y), Vector2(x, y + ts)])
			1: pts = PackedVector2Array([Vector2(x, y), Vector2(x - ts, y), Vector2(x, y + ts)])
			2: pts = PackedVector2Array([Vector2(x, y), Vector2(x + ts, y), Vector2(x, y - ts)])
			_: pts = PackedVector2Array([Vector2(x, y), Vector2(x - ts, y), Vector2(x, y - ts)])
		draw_colored_polygon(pts, COL_GOLD)

# --- Slot tile. Same draw, reacts to hover/filled state. -----------------
class _StoneSlot extends Button:
	const COL_STONE_DARK  := Color(0.10, 0.11, 0.12)
	const COL_BRONZE_DARK := Color(0.18, 0.20, 0.22)
	const COL_BRONZE_MID  := Color(0.32, 0.34, 0.36)
	const COL_GOLD        := Color(0.55, 0.55, 0.52)
	const COL_GOLD_HI     := Color(0.78, 0.76, 0.70)
	const COL_VOID        := Color(0.05, 0.06, 0.07)
	const COL_VOID_HOT    := Color(0.10, 0.11, 0.13)
	var filled: bool = false :
		set(v): filled = v; queue_redraw()
	var slot_id: String = ""
	func _ready() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
	func _draw() -> void:
		var w: int = int(size.x)
		var h: int = int(size.y)
		var mode: int = get_draw_mode()
		var rim: Color = COL_GOLD_HI if (mode == DRAW_HOVER or mode == DRAW_HOVER_PRESSED) else COL_GOLD
		var cavity: Color = COL_VOID_HOT if (mode == DRAW_HOVER or mode == DRAW_HOVER_PRESSED) else COL_VOID
		# Drop shadow.
		draw_rect(Rect2(2, 3, w, h), Color(0, 0, 0, 0.5), true)
		# Stone outer.
		draw_rect(Rect2(0, 0, w, h), COL_STONE_DARK, true)
		# Bronze rim.
		draw_rect(Rect2(1, 1, w - 2, h - 2), COL_BRONZE_DARK, true)
		draw_rect(Rect2(2, 2, w - 4, h - 4), COL_BRONZE_MID, true)
		# Gold pinstripe (brighter on hover).
		draw_rect(Rect2(3, 3, w - 6, h - 6), rim, true)
		# Inner stone.
		draw_rect(Rect2(4, 4, w - 8, h - 8), COL_STONE_DARK, true)
		# Cavity.
		draw_rect(Rect2(5, 5, w - 10, h - 10), cavity, true)
		# Top sheen + bottom shadow.
		draw_rect(Rect2(5, 5, w - 10, 1), Color(1, 1, 1, 0.06), true)
		draw_rect(Rect2(5, h - 6, w - 10, 1), Color(0, 0, 0, 0.5), true)
		# Gold corner studs (smaller for slots).
		_corner_tri(3, 3, 3, 0, rim)
		_corner_tri(w - 3, 3, 3, 1, rim)
		_corner_tri(3, h - 3, 3, 2, rim)
		_corner_tri(w - 3, h - 3, 3, 3, rim)
		# Tick mark for empty slots — 4×1 px gold sliver in upper-left of cavity.
		if not filled:
			draw_rect(Rect2(7, 7, 4, 1), COL_GOLD, true)
	func _corner_tri(x: int, y: int, ts: int, corner: int, col: Color) -> void:
		var pts := PackedVector2Array()
		match corner:
			0: pts = PackedVector2Array([Vector2(x, y), Vector2(x + ts, y), Vector2(x, y + ts)])
			1: pts = PackedVector2Array([Vector2(x, y), Vector2(x - ts, y), Vector2(x, y + ts)])
			2: pts = PackedVector2Array([Vector2(x, y), Vector2(x + ts, y), Vector2(x, y - ts)])
			_: pts = PackedVector2Array([Vector2(x, y), Vector2(x - ts, y), Vector2(x, y - ts)])
		draw_colored_polygon(pts, col)

# --- Build ----------------------------------------------------------------

func _build_panel() -> void:
	# Dim backdrop.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.anchor_right = 1.0; dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# Centered stone frame holding everything.
	var center := CenterContainer.new()
	center.anchor_right = 1.0; center.anchor_bottom = 1.0
	add_child(center)

	var frame := _StoneFrame.new()
	frame.custom_minimum_size = Vector2(780, 580)
	center.add_child(frame)

	# Inner padding inside the cavity.
	var pad := MarginContainer.new()
	pad.anchor_right = 1.0; pad.anchor_bottom = 1.0
	pad.add_theme_constant_override("margin_left", 18)
	pad.add_theme_constant_override("margin_right", 18)
	pad.add_theme_constant_override("margin_top", 14)
	pad.add_theme_constant_override("margin_bottom", 18)
	frame.add_child(pad)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
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

# --- Header ---------------------------------------------------------------

func _build_header() -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)

	var title := Label.new()
	title.text = "EQUIPMENT"
	title.add_theme_color_override("font_color", COL_GOLD_HI)
	title.add_theme_font_size_override("font_size", 16)
	hb.add_child(title)

	# Tab strip — custom buttons.
	var tabs_hb := HBoxContainer.new()
	tabs_hb.add_theme_constant_override("separation", 4)
	tabs_hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in TABS.size():
		var b := _make_tab_button(TABS[i], i)
		tabs_hb.add_child(b)
	hb.add_child(tabs_hb)

	_gold_label = Label.new()
	_gold_label.text = "0g"
	_gold_label.add_theme_color_override("font_color", COL_GOLD_HI)
	_gold_label.add_theme_font_size_override("font_size", 14)
	_gold_label.custom_minimum_size = Vector2(60, 0)
	hb.add_child(_gold_label)

	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.add_theme_color_override("font_color", COL_TEXT_DIM)
	close.add_theme_color_override("font_hover_color", COL_GOLD_HI)
	close.add_theme_font_size_override("font_size", 18)
	close.custom_minimum_size = Vector2(28, 28)
	close.pressed.connect(_on_close)
	hb.add_child(close)
	return hb

func _make_tab_button(label: String, idx: int) -> Button:
	var b := Button.new()
	b.text = label
	b.flat = true
	b.toggle_mode = false
	b.add_theme_color_override("font_color", COL_TEXT_DIM if idx != _active_tab else COL_GOLD_HI)
	b.add_theme_color_override("font_hover_color", COL_GOLD_HI)
	b.add_theme_font_size_override("font_size", 12)
	b.custom_minimum_size = Vector2(82, 28)
	b.pressed.connect(_on_tab_changed.bind(idx))
	b.set_meta("tab_idx", idx)
	# Custom draw via a stone bg behind the text — wrap in a small panel.
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_STONE_DARK if idx != _active_tab else COL_BRONZE_DARK
	sb.border_color = COL_GOLD if idx == _active_tab else COL_BRONZE_DARK
	sb.border_width_bottom = 2
	sb.content_margin_left = 10; sb.content_margin_right = 10
	sb.content_margin_top = 6; sb.content_margin_bottom = 6
	b.add_theme_stylebox_override("normal", sb)
	var hov := sb.duplicate() as StyleBoxFlat
	hov.bg_color = COL_BRONZE_DARK
	hov.border_color = COL_GOLD_HI
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", hov)
	return b

# --- Paper-doll ----------------------------------------------------------

func _build_paperdoll() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)

	var hdr := Label.new()
	hdr.text = "PAPER DOLL"
	hdr.add_theme_color_override("font_color", COL_GOLD)
	hdr.add_theme_font_size_override("font_size", 11)
	v.add_child(hdr)

	# Inner stone frame around the slot grid (recessed look).
	var inner := _StoneFrame.new()
	inner.custom_minimum_size = Vector2(320, 380)
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(inner)

	var grid_pad := MarginContainer.new()
	grid_pad.anchor_right = 1.0; grid_pad.anchor_bottom = 1.0
	grid_pad.add_theme_constant_override("margin_left", 16)
	grid_pad.add_theme_constant_override("margin_right", 16)
	grid_pad.add_theme_constant_override("margin_top", 18)
	grid_pad.add_theme_constant_override("margin_bottom", 18)
	inner.add_child(grid_pad)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid_pad.add_child(grid)

	for entry in PAPERDOLL_SLOTS:
		var label_text: String = entry[0]
		var slot_id: String = entry[1]
		if slot_id == "":
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(56, 70)
			grid.add_child(spacer)
		else:
			grid.add_child(_make_paperdoll_slot(label_text, slot_id))
	return v

func _make_paperdoll_slot(label_text: String, slot_id: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var btn := _StoneSlot.new()
	btn.custom_minimum_size = Vector2(56, 56)
	btn.slot_id = slot_id
	btn.pressed.connect(_on_doll_slot_pressed.bind(slot_id))
	v.add_child(btn)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_color_override("font_color", COL_GOLD)
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(lbl)
	_doll_slots[slot_id] = btn
	return v

# --- Backpack ------------------------------------------------------------

func _build_backpack() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)

	var hdr := Label.new()
	hdr.text = "BACKPACK"
	hdr.add_theme_color_override("font_color", COL_GOLD)
	hdr.add_theme_font_size_override("font_size", 11)
	v.add_child(hdr)

	var inner := _StoneFrame.new()
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(inner)

	var pad := MarginContainer.new()
	pad.anchor_right = 1.0; pad.anchor_bottom = 1.0
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 14)
	pad.add_theme_constant_override("margin_bottom", 14)
	inner.add_child(pad)

	_bag_grid = GridContainer.new()
	_bag_grid.columns = 8
	_bag_grid.add_theme_constant_override("h_separation", 4)
	_bag_grid.add_theme_constant_override("v_separation", 4)
	pad.add_child(_bag_grid)
	return v

# --- Refresh -------------------------------------------------------------

func _refresh_all() -> void:
	if _gold_label == null:
		return
	_gold_label.text = "%dg" % Inventory.get_gold(_loadout)
	_refresh_paperdoll()
	_refresh_backpack()

func _refresh_paperdoll() -> void:
	for slot_id in _doll_slots.keys():
		var btn: _StoneSlot = _doll_slots[slot_id]
		var folder: String = String(_loadout.get(slot_id, ""))
		for c in btn.get_children():
			c.queue_free()
		btn.filled = (folder != "")
		if folder != "":
			var icon := _make_item_icon(_item_id_for_folder(folder))
			if icon:
				icon.anchor_right = 1.0; icon.anchor_bottom = 1.0
				icon.offset_left = 6; icon.offset_top = 6
				icon.offset_right = -6; icon.offset_bottom = -6
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
	var btn := _StoneSlot.new()
	btn.custom_minimum_size = Vector2(50, 50)
	if item_id == "":
		btn.filled = false
	else:
		btn.filled = true
		var icon := _make_item_icon(item_id)
		if icon:
			icon.anchor_right = 1.0; icon.anchor_bottom = 1.0
			icon.offset_left = 6; icon.offset_top = 6
			icon.offset_right = -6; icon.offset_bottom = -6
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
				# HD item icons render with LINEAR filter so they stay
				# crisp / detailed regardless of the world's NEAREST
				# default. The icon textures are deliberately HD.
				r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
				r.mouse_filter = Control.MOUSE_FILTER_IGNORE
				return r
	return null

func _item_id_for_folder(folder: String) -> String:
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

# --- Signals -------------------------------------------------------------

func _on_tab_changed(idx: int) -> void:
	_active_tab = idx
	# Rebuild the header so tab styling reflects the new selection. Cheap.
	_refresh_backpack()

func _on_close() -> void:
	closed.emit()
	queue_free()

func _on_doll_slot_pressed(slot_id: String) -> void:
	var folder: String = String(_loadout.get(slot_id, ""))
	if folder == "":
		return
	var iid: String = _item_id_for_folder(folder)
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
