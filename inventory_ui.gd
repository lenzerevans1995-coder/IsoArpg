extends Control
class_name InventoryUI

const Inventory := preload("res://inventory.gd")

# Modal inventory grid. Shows owned items grouped by slot category, with a
# right-side detail panel and an Equip button. Press I to toggle.

signal closed()

const COL_BG := Color(0.06, 0.07, 0.10, 0.94)
const COL_PANEL := Color(0.12, 0.14, 0.18)
const COL_PANEL_EDGE := Color(0.28, 0.24, 0.16)
const COL_ROW := Color(0.16, 0.18, 0.22)
const COL_TEXT := Color(0.92, 0.90, 0.85)
const COL_MUTED := Color(0.65, 0.62, 0.55)
const COL_ACCENT := Color(0.86, 0.72, 0.36)
const COL_ACCENT_HI := Color(1.0, 0.86, 0.46)

const SLOT_LABELS := {
	ItemsDB.Slot.HEAD: "Head",
	ItemsDB.Slot.CHEST: "Chest",
	ItemsDB.Slot.LEGS: "Legs",
	ItemsDB.Slot.SHOES: "Shoes",
	ItemsDB.Slot.HANDS: "Hands",
	ItemsDB.Slot.BELT: "Belt",
	ItemsDB.Slot.BAG: "Bag",
	ItemsDB.Slot.MAINHAND: "Weapon",
	ItemsDB.Slot.OFFHAND: "Offhand",
	ItemsDB.Slot.SHIELD: "Shield",
	ItemsDB.Slot.MOUNT: "Mount",
}

var _loadout: Dictionary = {}
var _selected_id: String = ""
var _gold_label: Label
var _detail_label: Label
var _equip_btn: Button
var _list: VBoxContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_loadout = Loadout.load_or_default()
	Inventory.ensure_inventory(_loadout)
	_build_ui()
	_refresh_list()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 540)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 20)
	pad.add_theme_constant_override("margin_right", 20)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pad.add_child(v)

	# Header.
	var header := HBoxContainer.new()
	v.add_child(header)
	var title := Label.new()
	title.text = "INVENTORY"
	title.add_theme_color_override("font_color", COL_ACCENT)
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_gold_label = Label.new()
	_gold_label.add_theme_color_override("font_color", COL_ACCENT_HI)
	_gold_label.add_theme_font_size_override("font_size", 18)
	header.add_child(_gold_label)

	# Body: scrollable list left, detail right.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	var detail := PanelContainer.new()
	detail.custom_minimum_size = Vector2(240, 0)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_theme_stylebox_override("panel", _row_style())
	body.add_child(detail)
	var dpad := MarginContainer.new()
	dpad.add_theme_constant_override("margin_left", 12)
	dpad.add_theme_constant_override("margin_right", 12)
	dpad.add_theme_constant_override("margin_top", 12)
	dpad.add_theme_constant_override("margin_bottom", 12)
	detail.add_child(dpad)
	var dv := VBoxContainer.new()
	dpad.add_child(dv)
	_detail_label = Label.new()
	_detail_label.add_theme_color_override("font_color", COL_TEXT)
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dv.add_child(_detail_label)
	_equip_btn = Button.new()
	_equip_btn.text = "Equip"
	_equip_btn.disabled = true
	_equip_btn.add_theme_stylebox_override("normal", _button_style(COL_ACCENT))
	_equip_btn.add_theme_stylebox_override("hover", _button_style(COL_ACCENT_HI))
	_equip_btn.add_theme_color_override("font_color", Color.BLACK)
	_equip_btn.add_theme_color_override("font_hover_color", Color.BLACK)
	_equip_btn.pressed.connect(_on_equip_pressed)
	dv.add_child(_equip_btn)

	# Footer: Close.
	var footer := HBoxContainer.new()
	v.add_child(footer)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", COL_MUTED)
	close_btn.add_theme_color_override("font_hover_color", COL_TEXT)
	close_btn.pressed.connect(_close)
	footer.add_child(close_btn)

func _refresh_list() -> void:
	_gold_label.text = "Gold: %d" % Inventory.get_gold(_loadout)
	for child in _list.get_children():
		child.queue_free()
	# Group items by slot category.
	var items: Array = Inventory.get_items(_loadout)
	if items.is_empty():
		var empty := Label.new()
		empty.text = "  (empty — use loot, shops, or crafting to acquire gear)"
		empty.add_theme_color_override("font_color", COL_MUTED)
		_list.add_child(empty)
		return
	var by_slot: Dictionary = {}
	for id in items:
		var it := _find_item(String(id))
		if it.is_empty():
			continue
		var slot: int = it["slot"]
		if not by_slot.has(slot):
			by_slot[slot] = []
		by_slot[slot].append(it)
	for slot in by_slot.keys():
		var section := Label.new()
		section.text = SLOT_LABELS.get(slot, "Item")
		section.add_theme_color_override("font_color", COL_ACCENT)
		section.add_theme_font_size_override("font_size", 14)
		_list.add_child(section)
		for it in by_slot[slot]:
			_list.add_child(_make_item_row(it))

func _make_item_row(item: Dictionary) -> Control:
	var bg := PanelContainer.new()
	bg.custom_minimum_size = Vector2(0, 36)
	bg.add_theme_stylebox_override("panel", _row_style())
	var btn := Button.new()
	btn.text = "  " + String(item["display"])
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.flat = true
	btn.add_theme_color_override("font_color", COL_TEXT)
	btn.add_theme_color_override("font_hover_color", COL_ACCENT_HI)
	btn.pressed.connect(func(): _select(String(item["id"])))
	bg.add_child(btn)
	return bg

func _select(id: String) -> void:
	_selected_id = id
	var item := _find_item(id)
	if item.is_empty():
		_detail_label.text = ""
		_equip_btn.disabled = true
		return
	var lines: Array = [
		"[b]%s[/b]" % item["display"],
		"Slot: %s" % SLOT_LABELS.get(item["slot"], "?"),
		"Source: %s" % String(item["source"]).capitalize(),
	]
	if int(item.get("weapon_class", ItemsDB.WeaponClass.NONE)) != ItemsDB.WeaponClass.NONE:
		var class_names := {
			ItemsDB.WeaponClass.MELEE: "Melee",
			ItemsDB.WeaponClass.RANGED: "Ranged",
			ItemsDB.WeaponClass.MAGIC: "Magic",
		}
		lines.append("Class: %s" % class_names.get(int(item["weapon_class"]), "—"))
	_detail_label.text = "\n".join(lines)
	_equip_btn.disabled = false

func _on_equip_pressed() -> void:
	if _selected_id == "":
		return
	if Inventory.equip(_loadout, _selected_id):
		Loadout.save(_loadout)
		_selected_id = ""
		_detail_label.text = "Equipped."
		_equip_btn.disabled = true
		_refresh_list()

func _close() -> void:
	closed.emit()
	queue_free()

func _find_item(id: String) -> Dictionary:
	for it in ItemsDB.build_catalog():
		if it["id"] == id:
			return it
	return {}

# --- Stylebox helpers ------------------------------------------------------

func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COL_PANEL
	s.border_color = COL_PANEL_EDGE
	s.set_border_width_all(2)
	s.set_corner_radius_all(8)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 8
	return s

func _row_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COL_ROW
	s.set_corner_radius_all(4)
	return s

func _button_style(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(6)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s
