@tool
extends Control
class_name ItemEditor

# Naming editor for the items_db catalog. TreeView grouped by slot,
# selecting an item loads (or stubs) its res://data/items/<slot>/<id>.tres,
# and edits go through Godot's Inspector via EditorInterface.
#
# Run by opening item_editor.tscn and pressing F6 in the editor, or
# instancing this Control inside a tool scene.

const ItemsDB := preload("res://items_db.gd")
const ItemMetadataScript := preload("res://item_metadata.gd")
const LayeredCharacterScript := preload("res://layered_character.gd")
const META_DIR := "res://data/items"
# Slot id -> LayeredCharacter layer. Mirrors ItemsDB.SLOT_LAYER but with
# explicit fallbacks for slots that don't have a 1:1 layer mapping.
const SLOT_TO_LAYER := {
	ItemsDB.Slot.HEAD: "head",
	ItemsDB.Slot.HANDS: "hands",
	ItemsDB.Slot.CHEST: "chest",
	ItemsDB.Slot.LEGS: "legs",
	ItemsDB.Slot.SHOES: "shoes",
	ItemsDB.Slot.BELT: "belt",
	ItemsDB.Slot.BAG: "bag",
	ItemsDB.Slot.MAINHAND: "mainhand",
	ItemsDB.Slot.OFFHAND: "offhand",
	ItemsDB.Slot.SHIELD: "offhand",
	ItemsDB.Slot.MOUNT: "mount",
}
# Slots that read better with a body underneath (armor reads as worn).
# Every slot reads better with a body underneath. Weapons / shields /
# offhands need a body so they look "held"; mounts render behind body
# so the rig reads as "player on mount". Empty dict logic kept for
# future "show alone" overrides.
const SHOW_BODY := {
	ItemsDB.Slot.HEAD: true, ItemsDB.Slot.HANDS: true,
	ItemsDB.Slot.CHEST: true, ItemsDB.Slot.LEGS: true,
	ItemsDB.Slot.SHOES: true, ItemsDB.Slot.BELT: true,
	ItemsDB.Slot.BAG: true, ItemsDB.Slot.MOUNT: true,
	ItemsDB.Slot.MAINHAND: true, ItemsDB.Slot.OFFHAND: true,
	ItemsDB.Slot.SHIELD: true,
}

var _tree: Tree
var _info_label: Label
var _save_btn: Button
var _bake_btn: Button
var _validate_btn: Button
var _preview_holder: SubViewportContainer
var _preview_vp: SubViewport
var _preview_char: Node2D
var _selected_item: Dictionary = {}     # current items_db catalog entry
var _selected_meta: Resource = null     # ItemMetadata loaded/created on selection

# In-scene field editors (so we don't depend on Godot's Inspector)
var _f_base_name: LineEdit
var _f_can_drop: CheckBox
var _f_drop_weight: SpinBox
var _f_min_zone: SpinBox
var _f_max_zone: SpinBox
var _f_is_unique: CheckBox
var _f_unique_name: LineEdit

# Preview state
const DIR_LETTERS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
var _preview_dir: int = 1               # 0=E, 1=SE…
var _preview_zoom: float = 2.0
var _preview_pan: Vector2 = Vector2(140, 200)  # rig anchor inside the viewport
var _preview_wield: bool = false        # show a sample sword for armor checks
var _preview_mount: bool = false        # show character on mount_1 (when item isn't a mount)
var _preview_tint: Color = Color.WHITE  # tint applied to the selected item's layer
var _dragging: bool = false
var _dir_btn: Button
var _zoom_lbl: Label

func _ready() -> void:
	if Engine.is_editor_hint() and not is_inside_tree():
		return
	_build_ui()
	_populate_tree()

func _build_ui() -> void:
	custom_minimum_size = Vector2(900, 600)
	anchor_right = 1.0
	anchor_bottom = 1.0
	var split := HSplitContainer.new()
	split.anchor_right = 1.0
	split.anchor_bottom = 1.0
	# Narrow left pane — TreeView shows only IDs + names, doesn't need
	# more than ~160px. Drag the splitter to widen if you need it.
	split.split_offset = 160
	add_child(split)

	# --- left: TreeView grouped by slot ---
	_tree = Tree.new()
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(140, 0)
	_tree.hide_root = true
	# Tighten the row spacing — default Tree leaves a ton of vertical air.
	_tree.add_theme_constant_override("v_separation", 0)
	_tree.add_theme_constant_override("h_separation", 4)
	_tree.add_theme_font_size_override("font_size", 11)
	_tree.item_selected.connect(_on_tree_item_selected)
	split.add_child(_tree)

	# --- right: scrollable content area + sticky action bar ---
	var right_root := VBoxContainer.new()
	right_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(right_root)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_root.add_child(scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(right)

	# Preview controls row.
	var ctrl := HBoxContainer.new()
	right.add_child(ctrl)
	_dir_btn = Button.new()
	_dir_btn.text = "Dir: SE"
	_dir_btn.tooltip_text = "Click to rotate (8 dirs)"
	_dir_btn.pressed.connect(_on_dir_pressed)
	ctrl.add_child(_dir_btn)
	var zout := Button.new(); zout.text = "−"
	zout.pressed.connect(func(): _set_zoom(_preview_zoom - 0.5))
	ctrl.add_child(zout)
	_zoom_lbl = Label.new(); _zoom_lbl.text = "2.0x"
	ctrl.add_child(_zoom_lbl)
	var zin := Button.new(); zin.text = "+"
	zin.pressed.connect(func(): _set_zoom(_preview_zoom + 0.5))
	ctrl.add_child(zin)
	var wield := CheckBox.new(); wield.text = "Wield"
	wield.toggled.connect(func(v): _preview_wield = v; _refresh_preview(_selected_item))
	ctrl.add_child(wield)
	var mount := CheckBox.new(); mount.text = "Mount"
	mount.toggled.connect(func(v): _preview_mount = v; _refresh_preview(_selected_item))
	ctrl.add_child(mount)

	# Preview pane — a SubViewport hosting a LayeredCharacter so armor
	# shows worn over a body and weapons render in isolation.
	_preview_holder = SubViewportContainer.new()
	_preview_holder.stretch = true
	_preview_holder.custom_minimum_size = Vector2(280, 280)
	_preview_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Mouse on the preview: middle-button drag pans, wheel zooms.
	_preview_holder.gui_input.connect(_on_preview_input)
	right.add_child(_preview_holder)
	_preview_vp = SubViewport.new()
	_preview_vp.size = Vector2i(280, 280)
	_preview_vp.transparent_bg = true
	_preview_vp.disable_3d = true
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_holder.add_child(_preview_vp)
	_preview_char = LayeredCharacterScript.new()
	# Center the rig in the viewport — the sprite is 128×128 anchored top-left,
	# so push it into view.
	(_preview_char as Node2D).position = Vector2(140, 200)
	(_preview_char as Node2D).scale = Vector2(_preview_zoom, _preview_zoom)
	_preview_vp.add_child(_preview_char)

	# Swatch strip — clickable colors from data/swatch_palette.json. Click
	# to apply as modulate tint on the selected item's layer.
	var swatch_row := _build_swatch_row()
	right.add_child(swatch_row)

	_info_label = Label.new()
	_info_label.text = "Select an item on the left."
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(_info_label)

	# In-scene field grid — no Inspector dependency.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(grid)

	_f_base_name = _add_string_field(grid, "Base Name")
	_f_can_drop = _add_check_field(grid, "Can Drop")
	_f_drop_weight = _add_spin_field(grid, "Drop Weight", 0.0, 100.0, 0.1)
	_f_min_zone = _add_spin_field(grid, "Min Zone Lvl", 1, 999, 1)
	_f_max_zone = _add_spin_field(grid, "Max Zone Lvl", 1, 999, 1)
	_f_is_unique = _add_check_field(grid, "Is Unique")
	_f_unique_name = _add_string_field(grid, "Unique Name")

	# Wire field changes back into the loaded resource so Save persists them.
	_f_base_name.text_changed.connect(func(v): if _selected_meta: _selected_meta.base_name = v)
	_f_can_drop.toggled.connect(func(v): if _selected_meta: _selected_meta.can_drop = v)
	_f_drop_weight.value_changed.connect(func(v): if _selected_meta: _selected_meta.drop_weight = float(v))
	_f_min_zone.value_changed.connect(func(v): if _selected_meta: _selected_meta.min_zone_level = int(v))
	_f_max_zone.value_changed.connect(func(v): if _selected_meta: _selected_meta.max_zone_level = int(v))
	_f_is_unique.toggled.connect(func(v): if _selected_meta: _selected_meta.is_unique = v)
	_f_unique_name.text_changed.connect(func(v): if _selected_meta: _selected_meta.unique_name = v)

	# Enter on either name field saves immediately. Shortcut for the
	# 'type → enter → next item' workflow.
	_f_base_name.text_submitted.connect(func(_v): _on_save_pressed())
	_f_unique_name.text_submitted.connect(func(_v): _on_save_pressed())

	# Sticky action bar lives in right_root (not the scroll container)
	# so Save / Validate / Bake stay visible no matter how far the user
	# scrolls.
	var btns := HBoxContainer.new()
	btns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_root.add_child(btns)

	_save_btn = Button.new()
	_save_btn.text = "Save"
	_save_btn.disabled = true
	_save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_btn.pressed.connect(_on_save_pressed)
	btns.add_child(_save_btn)

	_validate_btn = Button.new()
	_validate_btn.text = "Validate"
	_validate_btn.pressed.connect(_on_validate_pressed)
	btns.add_child(_validate_btn)

	_bake_btn = Button.new()
	_bake_btn.text = "Bake all icons"
	_bake_btn.disabled = true              # icon_baker.gd not built yet
	_bake_btn.tooltip_text = "Implemented in icon_baker.gd (next pass)"
	btns.add_child(_bake_btn)

func _populate_tree() -> void:
	_tree.clear()
	var root: TreeItem = _tree.create_item()
	var by_slot: Dictionary = {}        # slot label -> Array of catalog entries
	for entry in ItemsDB.build_catalog():
		var slot_id: int = int(entry["slot"])
		var slot_name: String = ItemsDB.Slot.keys()[slot_id]
		var key: String = slot_name
		if int(entry["weapon_class"]) != ItemsDB.WeaponClass.NONE:
			key = "%s (%s)" % [slot_name, ItemsDB.WeaponClass.keys()[int(entry["weapon_class"])]]
		var arr: Array = by_slot.get(key, [])
		arr.append(entry)
		by_slot[key] = arr
	var keys: Array = by_slot.keys()
	keys.sort()
	for k in keys:
		var slot_node: TreeItem = _tree.create_item(root)
		slot_node.set_text(0, "%s (%d)" % [k, by_slot[k].size()])
		slot_node.set_selectable(0, false)
		# Start collapsed — 13 slot headers fit on screen; click to drill in.
		slot_node.collapsed = true
		for entry in by_slot[k]:
			var leaf: TreeItem = _tree.create_item(slot_node)
			leaf.set_text(0, _label_for(entry))
			leaf.set_metadata(0, entry)

func _label_for(entry: Dictionary) -> String:
	var meta_path: String = _meta_path_for(entry)
	if FileAccess.file_exists(meta_path):
		var res: Resource = load(meta_path)
		if res is ItemMetadataScript and String(res.base_name) != "":
			return "%s — %s" % [String(entry["id"]), String(res.base_name)]
	# Unnamed: show the id with a dot prefix so "needs naming" is obvious.
	return "· %s" % String(entry["id"])

func _meta_path_for(entry: Dictionary) -> String:
	var slot_name: String = ItemsDB.Slot.keys()[int(entry["slot"])].to_lower()
	return "%s/%s/%s.tres" % [META_DIR, slot_name, String(entry["id"])]

func _on_tree_item_selected() -> void:
	var ti: TreeItem = _tree.get_selected()
	if ti == null:
		return
	var entry = ti.get_metadata(0)
	if not (entry is Dictionary):
		return
	_selected_item = entry
	_selected_meta = _load_or_stub(entry)
	_info_label.text = _info_text_for(entry, _selected_meta)
	_save_btn.disabled = false
	_refresh_preview(entry)
	_load_fields_from_meta(_selected_meta)

func _load_or_stub(entry: Dictionary) -> Resource:
	var path: String = _meta_path_for(entry)
	if FileAccess.file_exists(path):
		var res: Resource = load(path)
		if res is ItemMetadataScript:
			return res
	# Stub — create in-memory only; Save writes to disk.
	var m: Resource = ItemMetadataScript.new()
	m.item_id = String(entry["id"])
	m.slot = int(entry["slot"])
	m.weapon_class = int(entry["weapon_class"])
	return m

func _on_save_pressed() -> void:
	if _selected_meta == null or _selected_item.is_empty():
		return
	var path: String = _meta_path_for(_selected_item)
	var dir: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var err: int = ResourceSaver.save(_selected_meta, path)
	if err != OK:
		_info_label.text = "Save FAILED (err=%d) → %s" % [err, path]
		return
	_info_label.text = "Saved → %s" % path
	# Update only the selected leaf's label — full _populate_tree() would
	# wipe the user's expansion state.
	var ti: TreeItem = _tree.get_selected()
	if ti != null:
		ti.set_text(0, _label_for(_selected_item))

func _on_validate_pressed() -> void:
	var unnamed: Array[String] = []
	var bad_drop_weight: Array[String] = []
	for entry in ItemsDB.build_catalog():
		var path: String = _meta_path_for(entry)
		if not FileAccess.file_exists(path):
			unnamed.append(String(entry["id"]))
			continue
		var res: Resource = load(path)
		if res is ItemMetadataScript:
			if String(res.base_name) == "":
				unnamed.append(String(entry["id"]))
			if float(res.drop_weight) <= 0.0 and bool(res.can_drop):
				bad_drop_weight.append(String(entry["id"]))
	var lines: Array[String] = []
	lines.append("Unnamed: %d" % unnamed.size())
	if not unnamed.is_empty():
		lines.append("  " + ", ".join(unnamed.slice(0, 10)) + ("…" if unnamed.size() > 10 else ""))
	lines.append("Droppable but weight=0: %d" % bad_drop_weight.size())
	if not bad_drop_weight.is_empty():
		lines.append("  " + ", ".join(bad_drop_weight))
	_info_label.text = "\n".join(lines)

func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_set_zoom(_preview_zoom + 0.25)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_set_zoom(_preview_zoom - 0.25)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_preview_pan += mm.relative
		if _preview_char and is_instance_valid(_preview_char):
			(_preview_char as Node2D).position = _preview_pan

func _on_dir_pressed() -> void:
	_preview_dir = (_preview_dir + 1) % 8
	_dir_btn.text = "Dir: %s" % DIR_LETTERS[_preview_dir]
	if _preview_char:
		_preview_char.call("set_direction", _preview_dir)

func _set_zoom(z: float) -> void:
	_preview_zoom = clampf(z, 1.0, 5.0)
	_zoom_lbl.text = "%.1fx" % _preview_zoom
	if _preview_char:
		(_preview_char as Node2D).scale = Vector2(_preview_zoom, _preview_zoom)

func _build_swatch_row() -> Control:
	# Pull the 81-swatch palette so tint testing matches what artists
	# can roll on items in-game (no off-palette colors).
	var palette: Array = []
	const PAL := "res://data/swatch_palette.json"
	if FileAccess.file_exists(PAL):
		var f := FileAccess.open(PAL, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Array:
			palette = parsed
	var grid := GridContainer.new()
	grid.columns = 27        # 81 = 27 × 3 — keeps swatch row compact
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for hex in palette:
		var b := Button.new()
		b.custom_minimum_size = Vector2(14, 14)
		b.flat = false
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(String(hex))
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		var col := Color(String(hex))
		b.tooltip_text = String(hex)
		b.pressed.connect(func(): _apply_tint(col))
		grid.add_child(b)
	# A "reset" cell so it's easy to clear the tint back to neutral.
	var reset := Button.new()
	reset.text = "✕"
	reset.tooltip_text = "Reset tint to white"
	reset.pressed.connect(func(): _apply_tint(Color.WHITE))
	grid.add_child(reset)
	return grid

func _apply_tint(c: Color) -> void:
	_preview_tint = c
	if _selected_item.is_empty() or _preview_char == null:
		return
	var slot_id: int = int(_selected_item["slot"])
	var layer_name: String = String(SLOT_TO_LAYER.get(slot_id, ""))
	if layer_name != "":
		_preview_char.call("set_tint", layer_name, c)

func _add_string_field(grid: GridContainer, label: String) -> LineEdit:
	var l := Label.new(); l.text = label; grid.add_child(l)
	var le := LineEdit.new()
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(le)
	return le

func _add_check_field(grid: GridContainer, label: String) -> CheckBox:
	var l := Label.new(); l.text = label; grid.add_child(l)
	var cb := CheckBox.new()
	grid.add_child(cb)
	return cb

func _add_spin_field(grid: GridContainer, label: String, lo: float, hi: float, step: float) -> SpinBox:
	var l := Label.new(); l.text = label; grid.add_child(l)
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	grid.add_child(sb)
	return sb

func _load_fields_from_meta(meta: Resource) -> void:
	# Suppress signals while loading so field setters don't echo back into
	# the resource on every assignment.
	_f_base_name.set_block_signals(true)
	_f_can_drop.set_block_signals(true)
	_f_drop_weight.set_block_signals(true)
	_f_min_zone.set_block_signals(true)
	_f_max_zone.set_block_signals(true)
	_f_is_unique.set_block_signals(true)
	_f_unique_name.set_block_signals(true)
	_f_base_name.text = String(meta.base_name)
	_f_can_drop.button_pressed = bool(meta.can_drop)
	_f_drop_weight.value = float(meta.drop_weight)
	_f_min_zone.value = int(meta.min_zone_level)
	_f_max_zone.value = int(meta.max_zone_level)
	_f_is_unique.button_pressed = bool(meta.is_unique)
	_f_unique_name.text = String(meta.unique_name)
	_f_base_name.set_block_signals(false)
	_f_can_drop.set_block_signals(false)
	_f_drop_weight.set_block_signals(false)
	_f_min_zone.set_block_signals(false)
	_f_max_zone.set_block_signals(false)
	_f_is_unique.set_block_signals(false)
	_f_unique_name.set_block_signals(false)

func _refresh_preview(entry: Dictionary) -> void:
	if _preview_char == null or not is_instance_valid(_preview_char):
		return
	if entry.is_empty():
		return
	# Clear every layer first so the previous selection doesn't bleed
	# through (e.g. a sword shouldn't keep showing when we click a hat).
	for layer in ["body", "head", "hands", "chest", "legs", "shoes", "belt",
			"bag", "mainhand", "offhand", "mount"]:
		_preview_char.call("clear_layer", layer)
		_preview_char.call("set_tint", layer, Color.WHITE)
	var slot_id: int = int(entry["slot"])
	# Body underneath for armor (so armor reads as worn) AND whenever
	# the user toggled Wield or Mount (so we have something to attach
	# the weapon / mount preview to).
	var needs_body: bool = SHOW_BODY.get(slot_id, false) or _preview_wield or _preview_mount
	if needs_body:
		_preview_char.call("equip", "body", "NakedBody")
	var layer_name: String = String(SLOT_TO_LAYER.get(slot_id, ""))
	if layer_name != "":
		_preview_char.call("equip", layer_name, String(entry["folder"]))
		_preview_char.call("set_tint", layer_name, _preview_tint)
	# Wield-test: stick a sample sword on for armor previews so we can
	# check how a chest reads while the player is mid-attack.
	if _preview_wield and slot_id != ItemsDB.Slot.MAINHAND:
		_preview_char.call("equip", "mainhand", "Melee1")
	# Mount-test: same idea — show what a piece looks like while mounted.
	if _preview_mount and slot_id != ItemsDB.Slot.MOUNT:
		_preview_char.call("equip", "mount", "Mount1")
	_preview_char.call("set_direction", _preview_dir)
	_preview_char.call("play_anim", "Idle", 12.0, true, Callable())

func _info_text_for(entry: Dictionary, meta: Resource) -> String:
	var slot_name: String = ItemsDB.Slot.keys()[int(entry["slot"])]
	var disk: String = "(stub — not saved yet)"
	if FileAccess.file_exists(_meta_path_for(entry)):
		disk = _meta_path_for(entry)
	var name_str: String = String(meta.base_name) if String(meta.base_name) != "" else "(unnamed)"
	return "ID:    %s\nSlot:  %s\nName:  %s\nFile:  %s\n\nEdit fields in the Inspector, then Save." % [
		String(entry["id"]), slot_name, name_str, disk
	]
