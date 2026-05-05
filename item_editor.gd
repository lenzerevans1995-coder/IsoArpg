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
const SHOW_BODY := {
	ItemsDB.Slot.HEAD: true, ItemsDB.Slot.HANDS: true,
	ItemsDB.Slot.CHEST: true, ItemsDB.Slot.LEGS: true,
	ItemsDB.Slot.SHOES: true, ItemsDB.Slot.BELT: true,
	ItemsDB.Slot.BAG: true,
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
	split.split_offset = 280
	add_child(split)

	# --- left: TreeView grouped by slot ---
	_tree = Tree.new()
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.item_selected.connect(_on_tree_item_selected)
	split.add_child(_tree)

	# --- right: preview + info + actions ---
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(right)

	# Preview pane — a SubViewport hosting a LayeredCharacter so armor
	# shows worn over a body and weapons render in isolation.
	_preview_holder = SubViewportContainer.new()
	_preview_holder.stretch = true
	_preview_holder.custom_minimum_size = Vector2(384, 384)
	_preview_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(_preview_holder)
	_preview_vp = SubViewport.new()
	_preview_vp.size = Vector2i(384, 384)
	_preview_vp.transparent_bg = true
	_preview_vp.disable_3d = true
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_holder.add_child(_preview_vp)
	_preview_char = LayeredCharacterScript.new()
	# Center the rig in the viewport — the sprite is 128×128 anchored top-left,
	# so push it into view.
	(_preview_char as Node2D).position = Vector2(192, 256)
	(_preview_char as Node2D).scale = Vector2(2, 2)
	_preview_vp.add_child(_preview_char)

	_info_label = Label.new()
	_info_label.text = "Select an item on the left."
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(_info_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)

	var btns := HBoxContainer.new()
	right.add_child(btns)

	_save_btn = Button.new()
	_save_btn.text = "Save"
	_save_btn.disabled = true
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
	# In-editor: surface the resource in Godot's Inspector.
	if Engine.is_editor_hint():
		var ed := Engine.get_singleton("EditorInterface") if Engine.has_singleton("EditorInterface") else null
		if ed and ed.has_method("inspect_object"):
			ed.call("inspect_object", _selected_meta)

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
	# Refresh the tree label so renamed items show their new base_name.
	_populate_tree()

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

func _refresh_preview(entry: Dictionary) -> void:
	if _preview_char == null or not is_instance_valid(_preview_char):
		return
	# Clear every layer first so the previous selection doesn't bleed
	# through (e.g. a sword shouldn't keep showing when we click a hat).
	for layer in ["body", "head", "hands", "chest", "legs", "shoes", "belt",
			"bag", "mainhand", "offhand", "mount"]:
		_preview_char.call("clear_layer", layer)
	var slot_id: int = int(entry["slot"])
	# Show a body underneath for armor pieces so they read as worn.
	if SHOW_BODY.get(slot_id, false):
		_preview_char.call("equip", "body", "NakedBody")
	var layer_name: String = String(SLOT_TO_LAYER.get(slot_id, ""))
	if layer_name != "":
		_preview_char.call("equip", layer_name, String(entry["folder"]))
	# Idle anim, SE-ish facing (row 1) — reads more dynamically than E.
	_preview_char.call("set_direction", 1)
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
