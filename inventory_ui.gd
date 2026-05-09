extends Control
class_name InventoryUI

# Inventory panel — drawn in the same stone / bronze / gold pixel-art
# style as HUDSkillSquare and HUDStoneButton (the existing UI bar).
# Custom Control._draw() per frame instead of StyleBoxFlat so the
# chunky D2-style frame, gold pinstripe, and corner studs match the
# rest of the HUD exactly.

const Inventory := preload("res://inventory.gd")
const RarityVisuals := preload("res://loot/rarity_visuals.gd")
const ItemMetadataScript := preload("res://loot/item_metadata.gd")

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
const LayeredCharacter := preload("res://layered_character.gd")
const Loadout := preload("res://loadout.gd")
# Slot lists for the two flanking columns + top/bottom rows. Slot ids
# match ItemsDB.SLOT_LAYER keys so equipping flows directly.
const LEFT_SLOTS := [
	["HEAD", "head"],
	["CHEST", "chest"],
	["MAINHAND", "mainhand"],
	["BELT", "belt"],
]
const RIGHT_SLOTS := [
	["HANDS", "hands"],
	["BAG", "bag"],
	["OFFHAND", "offhand"],
	["SHIELD", "shield"],
]
const BOTTOM_SLOTS := [
	["LEGS", "legs"],
	["SHOES", "shoes"],
	["MOUNT", "mount"],
]

var _loadout: Dictionary = {}
var _active_tab: int = 0
var _gold_label: Label
var _bag_grid: GridContainer
var _doll_slots: Dictionary = {}    # slot_id -> _StoneSlot
var _detail_panel: Control          # hover-tooltip pane on the side
var _detail_text: Label
var _scroll: ScrollContainer        # cached so we can invert wheel input

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
		# (Top sheen removed — read as a light grey rectangle at the top
		# edge of the paper-doll / backpack cards.)
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
	# When set, replaces the gold pinstripe with the rarity color so
	# the slot reads as Magic / Rare / Unique / Legendary at a glance.
	# Color.WHITE = use the default gold rim.
	var rarity_color: Color = Color.WHITE :
		set(v): rarity_color = v; queue_redraw()
	func _ready() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
	func _draw() -> void:
		var w: int = int(size.x)
		var h: int = int(size.y)
		var mode: int = get_draw_mode()
		var rim: Color = COL_GOLD_HI if (mode == DRAW_HOVER or mode == DRAW_HOVER_PRESSED) else COL_GOLD
		# Rarity rim: when the slot holds a non-common item, paint the
		# pinstripe in the rarity color (brighter on hover).
		if filled and rarity_color != Color.WHITE:
			rim = rarity_color.lightened(0.25) if (mode == DRAW_HOVER or mode == DRAW_HOVER_PRESSED) else rarity_color
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
		# (Empty-slot tick mark removed — was reading as a stray dash.)
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
	# Wide enough for the 6-col x 64px backpack + paper-doll without
	# the ScrollContainer's reserved scrollbar gutter eating a column.
	frame.custom_minimum_size = Vector2(1120, 700)
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

	# Hover popup — floating tooltip, not a sidebar. Added to the root
	# so it can position above any slot in the panel.
	_build_detail_popup()

# --- Header ---------------------------------------------------------------

func _build_header() -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)

	var title := Label.new()
	title.text = "EQUIPMENT"
	title.add_theme_color_override("font_color", COL_GOLD_HI)
	title.add_theme_font_size_override("font_size", 16)
	hb.add_child(title)

	# Tabs are rendered as a separate strip butting the inventory
	# panel below — see _build_tab_strip / page.add_child below.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)

	# Gold counter — coin icon + number aligned by giving them the SAME
	# row height. The coins_drop.png art sits at the bottom of its
	# canvas; cropping the texture region to its content bbox snaps
	# the visible coins to the rect center so they line up with the
	# label baseline.
	var gold_box := HBoxContainer.new()
	gold_box.add_theme_constant_override("separation", 6)
	gold_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var coin_size: Vector2 = Vector2(48, 48)
	var coin := TextureRect.new()
	var coin_path := "res://assets/drops/gold_drop/coins_drop.png"
	if ResourceLoader.exists(coin_path):
		var raw: Texture2D = load(coin_path)
		var atlas := AtlasTexture.new()
		atlas.atlas = raw
		# Hand-cropped region — pulls the coin pile out of the bottom
		# of the source frame and skips the transparent top half.
		var w: int = raw.get_width()
		var h: int = raw.get_height()
		atlas.region = Rect2(0, h * 0.45, w, h * 0.55)
		coin.texture = atlas
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	coin.custom_minimum_size = coin_size
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	gold_box.add_child(coin)
	_gold_label = Label.new()
	_gold_label.text = "0"
	_gold_label.add_theme_color_override("font_color", COL_GOLD_HI)
	_gold_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_gold_label.add_theme_constant_override("outline_size", 3)
	_gold_label.add_theme_font_size_override("font_size", 18)
	_gold_label.custom_minimum_size = Vector2(60, coin_size.y)
	_gold_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gold_box.add_child(_gold_label)
	hb.add_child(gold_box)

	# Close button — same chunky stone style as HUDStoneButton: dark
	# outer + bronze rim + gold pinstripe + cavity, sinks 1 px on press.
	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(44, 44)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.add_theme_color_override("font_color", COL_GOLD)
	close.add_theme_color_override("font_hover_color", COL_GOLD_HI)
	close.add_theme_color_override("font_pressed_color", COL_GOLD)
	close.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	close.add_theme_constant_override("outline_size", 3)
	close.add_theme_font_size_override("font_size", 16)
	close.add_theme_stylebox_override("normal", _close_btn_style(false))
	close.add_theme_stylebox_override("hover",  _close_btn_style(true))
	close.add_theme_stylebox_override("pressed", _close_btn_style(true))
	close.pressed.connect(_on_close)
	hb.add_child(close)
	return hb

func _close_btn_style(hot: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_VOID_HOT if hot else COL_VOID
	sb.border_color = COL_GOLD_HI if hot else COL_GOLD
	sb.border_width_left = 2; sb.border_width_top = 2
	sb.border_width_right = 2; sb.border_width_bottom = 2
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 2
	sb.shadow_offset = Vector2(0, 2)
	# Equal margins on all four sides so the cavity is square.
	sb.content_margin_left = 6; sb.content_margin_right = 6
	sb.content_margin_top = 6; sb.content_margin_bottom = 6
	return sb

var _tab_buttons: Array = []

func _build_tab_strip() -> Control:
	# Row of tab buttons that butt the inventory panel below — each tab
	# has top + left + right border but NO bottom border, so the active
	# tab visually merges with the frame underneath. Selected tab uses
	# the panel's bg color (no separator); inactive tabs sit on a
	# darker fill so they read as recessed.
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 0)
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Left padding so the leftmost tab doesn't crowd the frame edge.
	var pad_l := Control.new()
	pad_l.custom_minimum_size = Vector2(18, 0)
	hb.add_child(pad_l)
	_tab_buttons.clear()
	for i in TABS.size():
		var b := _make_tab_button(TABS[i], i)
		hb.add_child(b)
		_tab_buttons.append(b)
	# Right side filler so the strip extends to the panel's right edge.
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(fill)
	return hb

func _make_tab_button(label: String, idx: int) -> Button:
	var b := Button.new()
	b.text = label
	b.toggle_mode = false
	b.add_theme_font_size_override("font_size", 13)
	b.custom_minimum_size = Vector2(108, 36)
	b.pressed.connect(_on_tab_changed.bind(idx))
	b.set_meta("tab_idx", idx)
	_apply_tab_style(b, idx == _active_tab)
	return b

func _apply_tab_style(b: Button, is_active: bool) -> void:
	var normal := StyleBoxFlat.new()
	if is_active:
		# Selected tab — gold rim on top + sides, fill matches the
		# panel below so the bottom edge "opens" into the inventory
		# frame.
		normal.bg_color = COL_STONE_DARK
		normal.border_color = COL_GOLD
		normal.border_width_top = 3
		normal.border_width_left = 2
		normal.border_width_right = 2
		normal.border_width_bottom = 0
	else:
		# Inactive — recessed, dim border, no bottom (still butts panel).
		normal.bg_color = Color(0.06, 0.07, 0.09)
		normal.border_color = COL_BRONZE_DARK
		normal.border_width_top = 2
		normal.border_width_left = 2
		normal.border_width_right = 2
		normal.border_width_bottom = 0
	normal.corner_radius_top_left = 4
	normal.corner_radius_top_right = 4
	normal.content_margin_left = 14; normal.content_margin_right = 14
	normal.content_margin_top = 8; normal.content_margin_bottom = 6
	b.add_theme_stylebox_override("normal", normal)
	# Hover — bronze rim brightens slightly, fill lifts.
	var hov := normal.duplicate() as StyleBoxFlat
	if not is_active:
		hov.bg_color = Color(0.10, 0.11, 0.13)
		hov.border_color = COL_GOLD
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", hov)
	# Text color
	if is_active:
		b.add_theme_color_override("font_color", COL_GOLD_HI)
		b.add_theme_color_override("font_hover_color", COL_GOLD_HI)
	else:
		b.add_theme_color_override("font_color", COL_TEXT_DIM)
		b.add_theme_color_override("font_hover_color", COL_GOLD_HI)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	b.add_theme_constant_override("outline_size", 3)

# --- Paper-doll ----------------------------------------------------------

var _preview_vp: SubViewport
var _preview_char: Node2D    # LayeredCharacter inside the preview viewport

func _build_detail_popup() -> void:
	# Floating popup that follows the cursor — sits above the rest of
	# the inventory UI so it overlays slots while hovering. Hidden by
	# default; shown via _show_item_detail when the user hovers a slot.
	var inner := _StoneFrame.new()
	inner.custom_minimum_size = Vector2(220, 0)
	inner.visible = false
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.z_index = 50
	add_child(inner)
	_detail_panel = inner
	var pad := MarginContainer.new()
	pad.anchor_right = 1.0; pad.anchor_bottom = 1.0
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 12)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(pad)
	_detail_text = Label.new()
	_detail_text.text = ""
	_detail_text.add_theme_color_override("font_color", COL_GOLD_HI)
	_detail_text.add_theme_font_size_override("font_size", 11)
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_detail_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(_detail_text)

func _process(_dt: float) -> void:
	if _detail_panel and _detail_panel.visible:
		# Resize the StoneFrame to match the label content + padding so
		# the chunky background covers all of the text. _StoneFrame is
		# a plain Control (not a Container), so it doesn't auto-grow
		# from its children — we set the size explicitly each tick.
		var label_min: Vector2 = _detail_text.get_minimum_size()
		var pad := Vector2(28, 24)
		var fit := Vector2(max(label_min.x + pad.x, 200.0), label_min.y + pad.y)
		_detail_panel.size = fit
		# Track mouse + clamp on-screen.
		var mp: Vector2 = get_global_mouse_position()
		var pos := mp + Vector2(16, 18)
		var screen: Vector2 = size
		if pos.x + fit.x > screen.x:
			pos.x = mp.x - fit.x - 8
		if pos.y + fit.y > screen.y:
			pos.y = screen.y - fit.y - 4
		_detail_panel.position = pos

func _build_paperdoll() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)

	var inner := _StoneFrame.new()
	inner.custom_minimum_size = Vector2(460, 520)
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(inner)

	var pad := MarginContainer.new()
	pad.anchor_right = 1.0; pad.anchor_bottom = 1.0
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 14)
	pad.add_theme_constant_override("margin_bottom", 14)
	inner.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	pad.add_child(col)

	# --- Center band: left slots | live player preview | right slots ----
	var middle := HBoxContainer.new()
	middle.add_theme_constant_override("separation", 8)
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(middle)

	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 8)
	for entry in LEFT_SLOTS:
		left_col.add_child(_make_paperdoll_slot(entry[0], entry[1]))
	middle.add_child(left_col)

	# Live player preview: SubViewport at native resolution holding a
	# LayeredCharacter mirroring the player's loadout. Re-equips when
	# the user changes gear so the silhouette updates instantly.
	# Phase 2.2: bigger character preview so the equipped silhouette
	# reads clearly. ~50% larger than the previous 180x280 viewport.
	var preview_holder := SubViewportContainer.new()
	preview_holder.stretch = true
	preview_holder.custom_minimum_size = Vector2(260, 400)
	preview_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_holder.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	middle.add_child(preview_holder)
	_preview_vp = SubViewport.new()
	_preview_vp.size = Vector2i(260, 400)
	_preview_vp.transparent_bg = true
	_preview_vp.disable_3d = true
	_preview_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview_holder.add_child(_preview_vp)
	_preview_char = LayeredCharacter.new()
	(_preview_char as Node2D).position = Vector2(130, 320)
	(_preview_char as Node2D).scale = Vector2(2.0, 2.0)
	_preview_char.set("_direction", 1)   # SE-facing reads as more 3D
	_preview_vp.add_child(_preview_char)

	var right_col := VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 8)
	for entry in RIGHT_SLOTS:
		right_col.add_child(_make_paperdoll_slot(entry[0], entry[1]))
	middle.add_child(right_col)

	# --- Bottom row of slots (legs / shoes / mount) --------------------
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 8)
	for entry in BOTTOM_SLOTS:
		bottom.add_child(_make_paperdoll_slot(entry[0], entry[1]))
	col.add_child(bottom)
	return v

func _make_paperdoll_slot(label_text: String, slot_id: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	var btn := _StoneSlot.new()
	btn.custom_minimum_size = Vector2(80, 80)
	btn.slot_id = slot_id
	btn.pressed.connect(_on_doll_slot_pressed.bind(slot_id))
	btn.mouse_entered.connect(func():
		var folder: String = String(_loadout.get(slot_id, ""))
		var iid: String = _item_id_for_folder(folder) if folder != "" else ""
		_show_item_detail(iid))
	btn.mouse_exited.connect(_show_item_detail.bind(""))
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
	# Negative separation overlaps the tab strip 2 px down into the
	# frame, hiding the frame's outermost stone-dark band so the tab
	# bottom merges directly into the bronze/gold rim. Plain 0 left a
	# visible 2 px dark strip between tab and panel.
	v.add_theme_constant_override("separation", -2)

	# Tab strip sits ON TOP of the inventory panel, butting its top
	# edge. Lives inside the bag column so its width matches the bag.
	v.add_child(_build_tab_strip())

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

	# Scroll wrapper so the bag grid stays inside the inventory frame
	# even when items overflow. 6 columns × N rows; vertical scroll only.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.gui_input.connect(_on_scroll_gui_input)
	_scroll = scroll
	pad.add_child(scroll)
	var vbar: VScrollBar = scroll.get_v_scroll_bar()
	if vbar:
		vbar.custom_minimum_size = Vector2(0, 0)
		vbar.modulate = Color(0, 0, 0, 0)
	# Center the grid horizontally inside the scroll container.
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_bag_grid = GridContainer.new()
	_bag_grid.columns = 6
	_bag_grid.add_theme_constant_override("h_separation", 6)
	_bag_grid.add_theme_constant_override("v_separation", 6)
	center.add_child(_bag_grid)
	return v

# --- Refresh -------------------------------------------------------------

func _refresh_all() -> void:
	if _gold_label == null:
		return
	_gold_label.text = "%d" % Inventory.get_gold(_loadout)
	_refresh_paperdoll()
	_refresh_backpack()

func _refresh_paperdoll() -> void:
	for slot_id in _doll_slots.keys():
		var btn: _StoneSlot = _doll_slots[slot_id]
		var folder: String = String(_loadout.get(slot_id, ""))
		for c in btn.get_children():
			c.queue_free()
		btn.filled = (folder != "")
		btn.rarity_color = Color.WHITE
		if folder != "":
			var iid: String = _item_id_for_folder(folder)
			btn.rarity_color = _rarity_color_for(iid)
			var icon := _make_item_icon(iid)
			if icon:
				icon.anchor_right = 1.0; icon.anchor_bottom = 1.0
				icon.offset_left = 6; icon.offset_top = 6
				icon.offset_right = -6; icon.offset_bottom = -6
				btn.add_child(icon)
	# Sync the live player preview rig.
	if _preview_char != null:
		Loadout.apply(_preview_char, _loadout)

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
	# 6 cols × 12 rows = 72 cells. ScrollContainer reveals more as the
	# inventory fills. Round up to the next full row.
	var min_cells: int = 72
	var rounded: int = max(min_cells, int(ceil(idx / 6.0) * 6))
	for i in range(idx, rounded):
		_bag_grid.add_child(_make_backpack_cell(""))

func _make_backpack_cell(item_id: String) -> Control:
	var btn := _StoneSlot.new()
	# 64 px cells match the paper-doll slots and give HD icons room to
	# breathe. Was 50 — way too small with 6 px inner padding.
	btn.custom_minimum_size = Vector2(80, 80)
	if item_id == "":
		btn.filled = false
		btn.rarity_color = Color.WHITE
	else:
		btn.filled = true
		btn.rarity_color = _rarity_color_for(item_id)
		var icon := _make_item_icon(item_id)
		if icon:
			icon.anchor_right = 1.0; icon.anchor_bottom = 1.0
			icon.offset_left = 2; icon.offset_top = 2
			icon.offset_right = -2; icon.offset_bottom = -2
			btn.add_child(icon)
		btn.set_meta("item_id", item_id)
		btn.pressed.connect(_on_bag_slot_pressed.bind(item_id))
		btn.mouse_entered.connect(_show_item_detail.bind(item_id))
		btn.mouse_exited.connect(_show_item_detail.bind(""))
	return btn

func _make_item_icon(item_id: String) -> TextureRect:
	if item_id == "":
		return null
	var paths := [
		"res://assets/generated/icons/%s.png" % item_id,
		"res://assets/generated/ground/%s.png" % item_id,
	]
	for p in paths:
		if not ResourceLoader.exists(p):
			continue
		var t: Texture2D = load(p)
		if t == null:
			continue
		# Baker now tight-crops each icon to its content bbox, so the
		# texture is the item filling ~82% of its frame. No extra crop
		# pass needed at runtime — render the whole texture.
		var r := TextureRect.new()
		r.texture = t
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return r
	return null

# (Legacy alpha-bbox helpers kept for potential future use; not called
# now that the baker pre-crops.)
static var _icon_bbox_cache: Dictionary = {}

func _make_item_icon_legacy(item_id: String) -> TextureRect:
	if item_id == "":
		return null
	var paths := [
		"res://assets/generated/icons/%s.png" % item_id,
		"res://assets/generated/ground/%s.png" % item_id,
	]
	for p in paths:
		if not ResourceLoader.exists(p):
			continue
		var t: Texture2D = load(p)
		if t == null:
			continue
		# Crop to the non-transparent bounding box. The baked icons
		# have their actual content occupying only ~10-20 px inside a
		# 128x128 frame (loot bake artifact), so without cropping the
		# texture is 95% empty space and shows the item at ~10 px.
		var bbox: Rect2 = _icon_bbox_cache.get(p, Rect2())
		if bbox.size == Vector2.ZERO:
			bbox = _find_content_bbox(t)
			_icon_bbox_cache[p] = bbox
		if bbox.size.x <= 0 or bbox.size.y <= 0:
			# Empty image — skip.
			continue
		var atlas := AtlasTexture.new()
		atlas.atlas = t
		atlas.region = bbox
		var r := TextureRect.new()
		r.texture = atlas
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return r
	return null

# Find the alpha bounding box of a Texture2D — the smallest rect
# containing all non-transparent pixels. Used to crop oversized baked
# icons so the actual item fills its inventory slot.
func _find_content_bbox(tex: Texture2D) -> Rect2:
	var img: Image = tex.get_image()
	if img == null:
		return Rect2()
	var w: int = img.get_width()
	var h: int = img.get_height()
	var min_x: int = w; var min_y: int = h
	var max_x: int = -1; var max_y: int = -1
	# Scan with a stride to keep this cheap; baked icons aren't that
	# big and the cache lookup means we only pay once per item_id.
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > 0.05:
				if x < min_x: min_x = x
				if y < min_y: min_y = y
				if x > max_x: max_x = x
				if y > max_y: max_y = y
	if max_x < min_x or max_y < min_y:
		return Rect2()
	# Add ~25 % of the content size as breathing room on each side so
	# cropped icons don't fill the slot to the edges. Keeps the gold
	# rim visible around the item.
	var cw: int = max_x - min_x + 1
	var ch: int = max_y - min_y + 1
	var pad: int = int(max(cw, ch) * 0.6)
	min_x = max(0, min_x - pad)
	min_y = max(0, min_y - pad)
	max_x = min(w - 1, max_x + pad)
	max_y = min(h - 1, max_y + pad)
	return Rect2(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)

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
	# Repaint each tab so the active state reflects the new selection.
	for i in _tab_buttons.size():
		_apply_tab_style(_tab_buttons[i], i == idx)
	_refresh_backpack()

func _on_close() -> void:
	closed.emit()
	queue_free()

## (Removed: _on_reset_pressed. Reset button dropped per Phase 1.4.)

func _on_scroll_gui_input(ev: InputEvent) -> void:
	# Invert mouse-wheel scroll direction so wheel-down moves the view
	# down through the content. Default Godot behavior matched the user's
	# "down is up" complaint; this flip restores the natural ARPG feel.
	if ev is InputEventMouseButton and _scroll:
		var mb := ev as InputEventMouseButton
		if not mb.pressed:
			return
		var step: int = 40
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll.scroll_vertical += step
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll.scroll_vertical -= step
			get_viewport().set_input_as_handled()

func _rarity_color_for(item_id: String) -> Color:
	# Read item metadata; if is_unique, use the unique tier color (or
	# the per-item glow_color). Otherwise default white = no rim tint.
	var meta := _meta_for_item(item_id)
	if meta == null:
		return Color.WHITE
	if "is_unique" in meta and bool(meta.is_unique):
		if "unique_glow_color" in meta and meta.unique_glow_color != Color.WHITE:
			return meta.unique_glow_color
		return RarityVisuals.color_for(3)   # Unique tier
	return Color.WHITE

func _meta_for_item(item_id: String) -> Resource:
	if item_id == "":
		return null
	var entry: Dictionary = {}
	for e in ItemsDB.build_catalog():
		if String(e.get("id", "")) == item_id:
			entry = e
			break
	if entry.is_empty():
		return null
	var slot_name: String = ItemsDB.Slot.keys()[int(entry.get("slot", 0))].to_lower()
	var path: String = "res://data/items/%s/%s.tres" % [slot_name, item_id]
	if not FileAccess.file_exists(path):
		return null
	var r: Resource = load(path)
	return r if r is ItemMetadataScript else null

func _show_item_detail(item_id: String) -> void:
	if _detail_text == null:
		return
	if item_id == "":
		_detail_panel.visible = false
		return
	_detail_panel.visible = true
	var entry: Dictionary = {}
	for e in ItemsDB.build_catalog():
		if String(e.get("id", "")) == item_id:
			entry = e
			break
	if entry.is_empty():
		_detail_text.text = "[%s]" % item_id
		return
	var slot_name: String = ItemsDB.Slot.keys()[int(entry.get("slot", 0))].to_lower()
	var meta := _meta_for_item(item_id)
	var lines: Array[String] = []
	# Title — name (uppercased), tinted via Label modulate after build.
	lines.append(String(entry.get("display", item_id)).to_upper())
	# Sub: slot — weapon class for mainhand
	var sub_line: String = "%s" % slot_name.capitalize()
	if int(entry.get("slot", -1)) == ItemsDB.Slot.MAINHAND:
		var wc: int = int(entry.get("weapon_class", 0))
		var wc_name := ["NONE", "Melee", "Ranged", "Magic"]
		if wc >= 0 and wc < wc_name.size():
			sub_line = "Mainhand — %s" % wc_name[wc]
	lines.append(sub_line)
	if meta != null:
		# Base stats.
		if "min_damage" in meta and "max_damage" in meta:
			var mn: int = int(meta.min_damage); var mx: int = int(meta.max_damage)
			if mn > 0 or mx > 0:
				lines.append("Damage: %d–%d" % [mn, mx])
		if "armor" in meta and int(meta.armor) > 0:
			lines.append("Armor: %d" % int(meta.armor))
		# Affixes — one line each. Format depends on whether the affix
		# is a flat add or percent. We don't know without loading
		# affix_db; show the field directly if present.
		if "affixes" in meta and meta.affixes is Array:
			for a in meta.affixes:
				lines.append(_format_affix(a))
		# Unique flag + flavor.
		if "is_unique" in meta and bool(meta.is_unique):
			lines.append("")
			lines.append("Unique")
			if "flavor_text" in meta and String(meta.flavor_text) != "":
				lines.append(String(meta.flavor_text))
	_detail_text.text = "\n".join(lines)
	# Tint the whole tooltip toward the rarity color (subtle modulate
	# so the chrome stays readable).
	var rcol: Color = _rarity_color_for(item_id)
	if rcol == Color.WHITE:
		_detail_text.add_theme_color_override("font_color", COL_GOLD_HI)
	else:
		_detail_text.add_theme_color_override("font_color", rcol.lightened(0.15))

func _format_affix(a: Variant) -> String:
	if a is Dictionary:
		var stat: String = String(a.get("stat", "?"))
		var amount: float = float(a.get("amount", 0.0))
		var is_pct: bool = bool(a.get("percent", false))
		if is_pct:
			return "%s +%d%%" % [stat.capitalize(), int(round(amount))]
		var sign: String = "+" if amount >= 0 else ""
		return "%s%d to %s" % [sign, int(round(amount)), stat.capitalize()]
	return String(a)

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
